"""Pyrola JSON stdin/stdout server.

Reads newline-delimited JSON requests from stdin, dispatches to kernel
operations, and writes JSON responses to stdout.

Protocol
--------
Request:  {"id": 1, "method": "init_kernel", "params": {"kernel_name": "python3"}}
Response: {"id": 1, "result": {...}}  or  {"id": 1, "error": "..."}

Methods: init_kernel, execute_code, list_globals, interrupt_kernel, shutdown_kernel
"""

import sys

sys.dont_write_bytecode = True

import json
import time

from jupyter_client import BlockingKernelClient, KernelManager

from vari_inspector import (
    get_python_inspector,
    get_python_inspector_call,
    get_r_inspector,
    get_r_inspector_call,
    get_python_globals_list,
    get_r_globals_list,
)


class PyrolaServer:
    def __init__(self):
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
        if self._connection_file:
            self._inspector_initialized.discard(self._connection_file)
        self.client = None
        self._connection_file = None

    def _connect_kernel(self, connection_file):
        if self.client is not None and self._connection_file == connection_file:
            return True
        self._disconnect_client()
        try:
            with open(connection_file, "r", encoding="utf-8") as fh:
                connection_info = json.load(fh)
            self.client = BlockingKernelClient()
            self.client.load_connection_info(connection_info)
            self.client.start_channels()
            self._connection_file = connection_file
            return True
        except Exception as exc:
            self._disconnect_client()
            raise RuntimeError(f"Connection error: {exc}")

    def _handle_kernel_message(self, msg_id=None):
        try:
            msg = self.client.get_iopub_msg(timeout=1)
        except Exception:
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
        outputs = []
        for _ in range(max_iterations):
            msg = self._handle_kernel_message(msg_id)
            if msg == "IDLE":
                break
            if msg is not None:
                outputs.append(msg)
        return outputs

    # ── RPC methods ──────────────────────────────────────────────────

    def init_kernel(self, params):
        kernel_name = params.get("kernel_name")
        if not kernel_name:
            raise ValueError("missing kernel_name")
        self.kernel_manager = KernelManager(kernel_name=kernel_name)
        self.kernel_manager.start_kernel()
        self.client = self.kernel_manager.client()
        self.client.start_channels()
        self._connection_file = self.kernel_manager.connection_file
        return {"connection_file": self.kernel_manager.connection_file}

    def execute_code(self, params):
        filetype = params.get("filetype")
        connection_file = params.get("connection_file")
        inspected_variable = params.get("inspected_variable")
        if not all([filetype, connection_file, inspected_variable]):
            raise ValueError("missing arguments (filetype, connection_file, inspected_variable)")

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
            raise ValueError(f"unsupported kernel: {filetype}")

        self._connect_kernel(connection_file)
        msg_id = self.client.execute(code)
        outputs = self._collect_outputs(msg_id)
        self._inspector_initialized.add(connection_file)
        return {"output": "\n".join(outputs) if outputs else "No output received"}

    def list_globals(self, params):
        filetype = params.get("filetype")
        connection_file = params.get("connection_file")
        if not filetype or not connection_file:
            raise ValueError("missing arguments (filetype, connection_file)")

        if filetype == "python":
            code = get_python_globals_list()
        elif filetype == "r":
            code = get_r_globals_list()
        else:
            raise ValueError(f"unsupported kernel: {filetype}")

        self._connect_kernel(connection_file)
        msg_id = self.client.execute(code)
        outputs = self._collect_outputs(msg_id)
        return {"output": "\n".join(outputs) if outputs else "(no user variables)"}

    def interrupt_kernel(self, params):
        if self.kernel_manager:
            self.kernel_manager.interrupt_kernel()
            return {"interrupted": True}
        return {"interrupted": False}

    def shutdown_kernel(self, params):
        connection_file = params.get("connection_file")
        if connection_file:
            try:
                self._connect_kernel(connection_file)
            except Exception:
                pass

        if self.client:
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

        self._disconnect_client()
        return {"shutdown": True}

    # ── Dispatch ─────────────────────────────────────────────────────

    _methods = {
        "init_kernel": init_kernel,
        "execute_code": execute_code,
        "list_globals": list_globals,
        "interrupt_kernel": interrupt_kernel,
        "shutdown_kernel": shutdown_kernel,
    }

    def dispatch(self, request):
        req_id = request.get("id")
        method_name = request.get("method")
        params = request.get("params", {})

        method = self._methods.get(method_name)
        if not method:
            return {"id": req_id, "error": f"unknown method: {method_name}"}

        try:
            result = method(self, params)
            return {"id": req_id, "result": result}
        except Exception as exc:
            return {"id": req_id, "error": str(exc)}


def main():
    server = PyrolaServer()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            response = {"id": None, "error": f"invalid JSON: {exc}"}
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
            continue

        response = server.dispatch(request)
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()

    # stdin closed — clean up
    server.shutdown_kernel({})


if __name__ == "__main__":
    main()
