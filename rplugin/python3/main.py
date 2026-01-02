import json
import time

import pynvim
from jupyter_client import BlockingKernelClient, KernelManager

from vari_inspector import get_python_inspector, get_r_inspector


@pynvim.plugin
class PyrolaPlugin:
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernel_manager = None
        self.client = None

    def _disconnect_client(self):
        if not self.client:
            return
        try:
            self.client.stop_channels()
        except Exception:
            pass
        self.client = None

    @pynvim.function("InitKernel", sync=True)
    def init_kernel(self, args):
        """Initialize Jupyter kernel and return connection file path."""
        if not args:
            self.nvim.err_write("Pyrola: missing kernel name\n")
            return None

        kernel_name = args[0]
        try:
            self.kernel_manager = KernelManager(kernel_name=kernel_name)
            self.kernel_manager.start_kernel()
            self.client = self.kernel_manager.client()
            self.client.start_channels()
            return self.kernel_manager.connection_file
        except Exception as exc:
            self.nvim.err_write(f"Kernel initialization failed: {exc}\n")
            self._disconnect_client()
            return None

    def _connect_kernel(self, connection_file):
        """Connect to the Jupyter kernel using the connection file."""
        try:
            with open(connection_file, "r", encoding="utf-8") as file_handle:
                connection_info = json.load(file_handle)

            self.client = BlockingKernelClient()
            self.client.load_connection_info(connection_info)
            self.client.start_channels()
            return True
        except Exception as exc:
            print(f"Connection error: {exc}")
            self._disconnect_client()
            return False

    def _handle_kernel_message(self):
        """Handle messages from the kernel."""
        try:
            msg = self.client.get_iopub_msg(timeout=1)
        except Exception as exc:
            print(f"Message handling error: {exc}")
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

    @pynvim.function("ExecuteKernelCode", sync=True)
    def execute_code(self, args):
        """Execute code in the Jupyter kernel."""
        if len(args) < 3:
            return "Error: missing arguments"

        filetype, connection_file, inspected_variable = args

        if filetype == "python":
            code = get_python_inspector(inspected_variable)
        elif filetype == "r":
            code = get_r_inspector(inspected_variable)
        else:
            return "Error: unsupported kernel"

        try:
            if not self._connect_kernel(connection_file):
                return "Error: Failed to connect to kernel"

            self.client.execute(code)

            outputs = []
            while True:
                msg = self._handle_kernel_message()
                if msg == "IDLE":
                    break
                if msg is not None:
                    outputs.append(msg)

            return "\n".join(outputs) if outputs else "No output received"
        except Exception as exc:
            print(f"Execution error: {exc}")
            return f"Execution error: {exc}"
        finally:
            self._disconnect_client()

    @pynvim.function("ShutdownKernel", sync=True)
    def shutdown_kernel(self, args):
        """Shutdown the Jupyter kernel."""
        if len(args) < 2:
            return False

        _, connection_file = args
        try:
            if not self._connect_kernel(connection_file):
                return False

            # Send shutdown request
            self.client.shutdown()

            # Wait for confirmation (optional, but recommended)
            timeout = 0.2
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    msg = self.client.get_iopub_msg(timeout=0.5)
                    if (
                        msg["msg_type"] == "status"
                        and msg["content"]["execution_state"] == "dead"
                    ):
                        break
                except Exception:
                    pass

            if self.kernel_manager:
                self.kernel_manager.shutdown_kernel(now=True)
                self.kernel_manager = None

            return True
        except Exception as exc:
            self.nvim.err_write(f"Kernel shutdown failed: {exc}\n")
            return False
        finally:
            self._disconnect_client()
