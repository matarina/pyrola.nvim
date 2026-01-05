"""
Direct Python wrapper for Pyrola functions.
Bypasses the remote plugin system for Neovim 0.11+ compatibility.
"""
import sys
import os
import json
import time

# Add the plugin directory to path
plugin_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, plugin_dir)

from jupyter_client import BlockingKernelClient, KernelManager
from vari_inspector import get_python_inspector, get_r_inspector


def init_kernel(kernel_name):
    """Initialize Jupyter kernel and return connection file path."""
    try:
        kernel_manager = KernelManager(kernel_name=kernel_name)
        kernel_manager.start_kernel()
        client = kernel_manager.client()
        client.start_channels()
        return kernel_manager.connection_file
    except Exception as exc:
        return None


def execute_code(filetype, connection_file, code):
    """Execute code in the Jupyter kernel."""
    try:
        with open(connection_file, "r", encoding="utf-8") as f:
            connection_info = json.load(f)
        
        client = BlockingKernelClient()
        client.load_connection_info(connection_info)
        client.start_channels()
        
        client.execute(code)
        
        outputs = []
        while True:
            try:
                msg = client.get_iopub_msg(timeout=1)
                msg_type = msg.get("msg_type")
                if msg_type == "stream":
                    outputs.append(msg["content"]["text"])
                elif msg_type == "execute_result":
                    outputs.append(msg["content"]["data"].get("text/plain", ""))
                elif msg_type == "error":
                    outputs.append(f"Error: {msg['content']['ename']}: {msg['content']['evalue']}")
                elif msg_type == "status" and msg["content"]["execution_state"] == "idle":
                    break
            except Exception:
                break
        
        client.stop_channels()
        return "\n".join(outputs) if outputs else "No output"
    except Exception as exc:
        return f"Error: {exc}"


def shutdown_kernel(connection_file):
    """Shutdown the Jupyter kernel."""
    try:
        with open(connection_file, "r", encoding="utf-8") as f:
            connection_info = json.load(f)
        
        client = BlockingKernelClient()
        client.load_connection_info(connection_info)
        client.start_channels()
        client.shutdown()
        client.stop_channels()
        time.sleep(0.2)
        return True
    except Exception:
        return False


if __name__ == "__main__":
    # Allow command line usage
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "init" and len(sys.argv) > 2:
            result = init_kernel(sys.argv[2])
            if result:
                print(result)
        elif cmd == "execute" and len(sys.argv) > 4:
            result = execute_code(sys.argv[2], sys.argv[3], sys.argv[4])
            print(result)
        elif cmd == "shutdown" and len(sys.argv) > 2:
            shutdown_kernel(sys.argv[2])
