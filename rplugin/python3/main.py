import sys

sys.dont_write_bytecode = True

import json
import subprocess
import threading
import time

import pynvim
from jupyter_client import BlockingKernelClient, KernelManager

from vari_inspector import (
    get_python_inspector,
    get_python_inspector_call,
    get_r_inspector,
    get_r_inspector_call,
    get_python_globals_list,
    get_r_globals_list,
)


@pynvim.plugin
class PyrolaPlugin:
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernel_manager = None
        self.client = None
        self._connection_file = None
        self._inspector_initialized = set()

    def _disconnect_client(self):
        if not self.client:
            return
        try:
            self.client.stop_channels()
        except Exception:
            pass
        # Clear inspector flag so the next connection re-initializes it.
        if self._connection_file:
            self._inspector_initialized.discard(self._connection_file)
        self.client = None
        self._connection_file = None

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args):
        """Initialize Jupyter kernel and return connection file path."""
        if not args:
            self.nvim.err_write("Pyrola: missing kernel name\n")
            return None

        kernel_name = args[0]
        try:
            result = {}
            error = {}
            kernel_manager = KernelManager(kernel_name=kernel_name)

            def worker():
                try:
                    kernel_manager.start_kernel(
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    client = kernel_manager.client()
                    client.start_channels()
                    client.wait_for_ready(timeout=25)
                    result["client"] = client
                except Exception as exc:
                    error["exc"] = exc
                    client = result.get("client")
                    if client is not None:
                        try:
                            client.stop_channels()
                        except Exception:
                            pass
                    try:
                        kernel_manager.shutdown_kernel(now=True)
                    except Exception:
                        pass

            thread = threading.Thread(target=worker, daemon=True)
            thread.start()
            thread.join(30)
            if thread.is_alive():
                try:
                    kernel_manager.shutdown_kernel(now=True)
                except Exception:
                    pass
                raise RuntimeError(f"Kernel startup timed out for '{kernel_name}'")
            if "exc" in error:
                raise error["exc"]

            self.kernel_manager = kernel_manager
            self.client = result["client"]
            self._connection_file = self.kernel_manager.connection_file
            return self.kernel_manager.connection_file
        except Exception as exc:
            self.nvim.err_write(f"Kernel initialization failed: {exc}\n")
            self._disconnect_client()
            return None

    def _connect_kernel(self, connection_file):
        """Return a live client for connection_file, reusing the cached one if possible."""
        if self.client is not None and self._connection_file == connection_file:
            return True
        self._disconnect_client()
        try:
            with open(connection_file, "r", encoding="utf-8") as file_handle:
                connection_info = json.load(file_handle)

            self.client = BlockingKernelClient()
            self.client.load_connection_info(connection_info)
            self.client.start_channels()
            self._connection_file = connection_file
            return True
        except Exception as exc:
            print(f"Connection error: {exc}")
            self._disconnect_client()
            return False

    def _handle_kernel_message(self, msg_id=None):
        """Handle messages from the kernel."""
        try:
            msg = self.client.get_iopub_msg(timeout=1)
        except Exception as exc:
            print(f"Message handling error: {exc}")
            return None

        if msg_id and msg.get("parent_header", {}).get("msg_id") != msg_id:
            return None

        msg_type = msg.get("msg_type")
        if msg_type == "stream":
            return msg["content"]["text"]
        if msg_type == "execute_result":
            return msg["content"]["data"].get("text/plain")
        if msg_type == "error":
            return f"Error: {msg['content']['ename']}: {msg['content']['evalue']}"
        if msg_type == "status" and msg["content"]["execution_state"] == "idle":
            return "IDLE"
        return None

    def _collect_outputs(self, msg_id, max_iterations=500):
        """Drive the message loop until IDLE and return collected output lines."""
        outputs = []
        for _ in range(max_iterations):
            msg = self._handle_kernel_message(msg_id)
            if msg == "IDLE":
                break
            if msg is not None:
                outputs.append(msg)
        return outputs

    @pynvim.function("ExecuteKernelCode", sync=True)
    def execute_code(self, args):
        """Execute code in the Jupyter kernel."""
        if len(args) < 3:
            return "Error: missing arguments"

        filetype, connection_file, inspected_variable = args

        if filetype == "python":
            if connection_file in self._inspector_initialized:
                code = get_python_inspector_call(inspected_variable)
            else:
                code = get_python_inspector(inspected_variable)
        elif filetype == "r":
            if connection_file in self._inspector_initialized:
                code = get_r_inspector_call(inspected_variable)
            else:
                code = get_r_inspector(inspected_variable)
        else:
            return "Error: unsupported kernel"

        try:
            if not self._connect_kernel(connection_file):
                return "Error: Failed to connect to kernel"

            msg_id = self.client.execute(code)
            outputs = self._collect_outputs(msg_id)
            self._inspector_initialized.add(connection_file)
            return "\n".join(outputs) if outputs else "No output received"
        except Exception as exc:
            self._disconnect_client()
            return f"Execution error: {exc}"

    @pynvim.function("ListKernelGlobals", sync=True)
    def list_kernel_globals(self, args):
        """List all global variables in the kernel."""
        if len(args) < 2:
            return "Error: missing arguments"

        filetype, connection_file = args

        if filetype == "python":
            code = get_python_globals_list()
        elif filetype == "r":
            code = get_r_globals_list()
        else:
            return "Error: unsupported kernel"

        try:
            if not self._connect_kernel(connection_file):
                return "Error: Failed to connect to kernel"

            msg_id = self.client.execute(code)
            outputs = self._collect_outputs(msg_id)
            return "\n".join(outputs) if outputs else "(no user variables)"
        except Exception as exc:
            self._disconnect_client()
            return f"Execution error: {exc}"

    @pynvim.function("InterruptKernel", sync=True)
    def interrupt_kernel(self, args):
        """Interrupt the running kernel via SIGINT."""
        if self.kernel_manager:
            try:
                self.kernel_manager.interrupt_kernel()
                return True
            except Exception as exc:
                self.nvim.err_write(f"Failed to interrupt kernel: {exc}\n")
                return False
        return False

    @pynvim.function("ShutdownKernel", sync=True)
    def shutdown_kernel(self, args):
        """Shutdown the Jupyter kernel."""
        if len(args) < 2:
            return False

        _, connection_file = args
        try:
            if not self._connect_kernel(connection_file):
                return False

            try:
                self.client.shutdown()
            except Exception:
                pass

            timeout = 0.5
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    msg = self.client.get_iopub_msg(timeout=0.1)
                    if (
                        msg["msg_type"] == "status"
                        and msg["content"]["execution_state"] == "dead"
                    ):
                        break
                except Exception:
                    break

            if self.kernel_manager:
                try:
                    self.kernel_manager.shutdown_kernel(now=True)
                except Exception:
                    pass
                self.kernel_manager = None

            return True
        except Exception as exc:
            self.nvim.err_write(f"Kernel shutdown failed: {exc}\n")
            return False
        finally:
            self._disconnect_client()
