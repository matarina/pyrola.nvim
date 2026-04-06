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
import shutil
import subprocess
import threading
import time
from pathlib import Path

from jupyter_client import BlockingKernelClient, KernelManager
from jupyter_client.kernelspec import KernelSpecManager

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
        self._kernel_spec_manager = KernelSpecManager()

    def _start_kernel_client(self, kernel_name, startup_timeout=25):
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
                client.wait_for_ready(timeout=startup_timeout)
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
        thread.join(startup_timeout + 5)

        if thread.is_alive():
            try:
                kernel_manager.shutdown_kernel(now=True)
            except Exception:
                pass
            raise RuntimeError(
                f"Kernel startup timed out after {startup_timeout} seconds for '{kernel_name}'."
            )

        if "exc" in error:
            raise RuntimeError(f"Kernel initialization failed: {error['exc']}")

        client = result.get("client")
        if client is None:
            raise RuntimeError("Kernel initialization failed: no client created")

        return kernel_manager, client

    def _managed_kernel_name(self, filetype):
        return f"pyrola_{filetype}"

    def _managed_display_name(self, filetype):
        display_names = {
            "python": "Pyrola Python",
            "r": "Pyrola R",
            "cpp": "Pyrola C++",
            "julia": "Pyrola Julia",
        }
        return display_names.get(filetype, f"Pyrola {filetype}")

    def _run(self, args):
        proc = subprocess.run(args, capture_output=True, text=True)
        stdout = (proc.stdout or "").strip()
        stderr = (proc.stderr or "").strip()
        return proc.returncode, stdout, stderr

    def _find_kernel_specs(self):
        return self._kernel_spec_manager.find_kernel_specs()

    def _load_kernel_spec(self, name):
        spec = self._kernel_spec_manager.get_kernel_spec(name)
        return spec.to_json(), spec.resource_dir

    def _managed_kernel_dir(self, name):
        return Path(self._kernel_spec_manager.user_kernel_dir) / name

    def _write_kernel_spec(self, name, spec_data, source_dir=None):
        target_dir = self._managed_kernel_dir(name)
        if target_dir.exists():
            shutil.rmtree(target_dir)
        target_dir.parent.mkdir(parents=True, exist_ok=True)
        target_dir.mkdir(parents=True, exist_ok=True)

        if source_dir:
            for entry in Path(source_dir).iterdir():
                if entry.name == "kernel.json":
                    continue
                dest = target_dir / entry.name
                if entry.is_dir():
                    shutil.copytree(entry, dest)
                else:
                    shutil.copy2(entry, dest)

        with open(target_dir / "kernel.json", "w", encoding="utf-8") as fh:
            json.dump(spec_data, fh, indent=1)
            fh.write("\n")

        return str(target_dir)

    def _clone_kernel_spec(self, source_name, target_name, display_name):
        spec_data, source_dir = self._load_kernel_spec(source_name)
        spec_data["display_name"] = display_name
        metadata = spec_data.get("metadata", {})
        metadata["pyrola"] = {"managed": True, "source_kernel": source_name}
        spec_data["metadata"] = metadata
        self._write_kernel_spec(target_name, spec_data, source_dir=source_dir)
        return target_name

    def _find_candidate_kernel(self, *, exact=None, prefixes=None, exclude=None):
        exact = exact or []
        prefixes = prefixes or []
        exclude = exclude or set()
        kernels = self._find_kernel_specs()

        for name in exact:
            if name in kernels and name not in exclude:
                return name

        for prefix in prefixes:
            matches = sorted(name for name in kernels if name.startswith(prefix) and name not in exclude)
            if matches:
                return matches[0]

        return None

    def _find_kernel_by_display_name(self, display_name, exclude=None):
        exclude = exclude or set()
        for name in sorted(self._find_kernel_specs()):
            if name in exclude:
                continue
            spec_data, _ = self._load_kernel_spec(name)
            if spec_data.get("display_name") == display_name:
                return name
        return None

    def _ensure_python_ipykernel(self):
        try:
            import ipykernel  # noqa: F401
        except Exception:
            code, _, stderr = self._run([sys.executable, "-m", "pip", "install", "ipykernel"])
            if code != 0:
                raise RuntimeError(
                    f"Failed to install ipykernel for {sys.executable}: {stderr or 'unknown error'}"
                )

    def _ensure_python_kernel(self, name):
        self._ensure_python_ipykernel()
        spec_data = {
            "argv": [
                sys.executable,
                "-m",
                "ipykernel_launcher",
                "-f",
                "{connection_file}",
            ],
            "display_name": self._managed_display_name("python"),
            "language": "python",
            "metadata": {
                "debugger": True,
                "pyrola": {"managed": True, "source_python": sys.executable},
            },
        }
        source_name = self._find_candidate_kernel(exact=["python3"], exclude={name})
        source_dir = None
        if source_name:
            _, source_dir = self._load_kernel_spec(source_name)
        self._write_kernel_spec(name, spec_data, source_dir=source_dir)
        return {
            "kernel_name": name,
            "display_name": self._managed_display_name("python"),
            "source": sys.executable,
        }

    def _ensure_r_kernel(self, name, runtime_command):
        if not runtime_command:
            source_name = self._find_candidate_kernel(exact=["ir"], exclude={name})
            if source_name:
                self._clone_kernel_spec(source_name, name, self._managed_display_name("r"))
                return {
                    "kernel_name": name,
                    "display_name": self._managed_display_name("r"),
                    "source": source_name,
                }
            raise RuntimeError("R executable not found in PATH; cannot create pyrola_r")

        code, _, stderr = self._run(
            [
                runtime_command,
                "--slave",
                "-e",
                "if (!requireNamespace('IRkernel', quietly=TRUE)) quit(status=2); "
                "IRkernel::installspec(user=TRUE, name='pyrola_r', displayname='Pyrola R')",
            ]
        )
        if code != 0:
            raise RuntimeError(
                "Failed to create pyrola_r. Install IRkernel in the active R environment. "
                f"R: {runtime_command}. Error: {stderr or 'unknown error'}"
            )
        return {
            "kernel_name": name,
            "display_name": self._managed_display_name("r"),
            "source": runtime_command,
        }

    def _ensure_cpp_kernel(self, name):
        source_name = self._find_candidate_kernel(
            exact=["xcpp17", "xcpp14", "xcpp11"],
            prefixes=["xcpp"],
            exclude={name},
        )
        if not source_name:
            raise RuntimeError(
                "No C++ Jupyter kernel found. Install xeus-cling so Pyrola can create pyrola_cpp."
            )

        self._clone_kernel_spec(source_name, name, self._managed_display_name("cpp"))
        return {
            "kernel_name": name,
            "display_name": self._managed_display_name("cpp"),
            "source": source_name,
        }

    def _ensure_julia_kernel(self, name):
        source_name = self._find_candidate_kernel(prefixes=["julia"], exclude={name})
        if not source_name:
            raise RuntimeError(
                "No Julia Jupyter kernel found. Install IJulia so Pyrola can create pyrola_julia."
            )

        self._clone_kernel_spec(source_name, name, self._managed_display_name("julia"))
        return {
            "kernel_name": name,
            "display_name": self._managed_display_name("julia"),
            "source": source_name,
        }

    def _ensure_julia_kernel_from_runtime(self, name, runtime_command):
        display_name = self._managed_display_name("julia")
        code, _, stderr = self._run(
            [
                runtime_command,
                "-e",
                f'using IJulia; installkernel("{display_name}")',
            ]
        )
        if code != 0:
            raise RuntimeError(
                "Failed to create a Julia kernel from the active environment. "
                f"Julia: {runtime_command}. Error: {stderr or 'unknown error'}"
            )

        source_name = self._find_kernel_by_display_name(display_name, exclude={name})
        if not source_name:
            source_name = self._find_candidate_kernel(prefixes=["julia"], exclude={name})
        if not source_name:
            raise RuntimeError("IJulia did not register a usable Julia kernelspec.")

        self._clone_kernel_spec(source_name, name, display_name)
        return {
            "kernel_name": name,
            "display_name": display_name,
            "source": runtime_command,
        }

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

    def ensure_managed_kernel(self, params):
        filetype = params.get("filetype")
        runtime_command = params.get("runtime_command")
        if not filetype:
            raise ValueError("missing filetype")

        name = self._managed_kernel_name(filetype)
        if filetype == "python":
            return self._ensure_python_kernel(name)
        if filetype == "r":
            return self._ensure_r_kernel(name, runtime_command)
        if filetype == "cpp":
            return self._ensure_cpp_kernel(name)
        if filetype == "julia":
            if runtime_command:
                return self._ensure_julia_kernel_from_runtime(name, runtime_command)
            return self._ensure_julia_kernel(name)
        raise ValueError(f"unsupported auto-managed kernel: {filetype}")

    def init_kernel(self, params):
        kernel_name = params.get("kernel_name")
        if not kernel_name:
            raise ValueError("missing kernel_name")
        self._disconnect_client()
        if self.kernel_manager:
            try:
                self.kernel_manager.shutdown_kernel(now=True)
            except Exception:
                pass
            self.kernel_manager = None
        self.kernel_manager, self.client = self._start_kernel_client(kernel_name)
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
        "ensure_managed_kernel": ensure_managed_kernel,
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
