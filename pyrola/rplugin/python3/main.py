import socket
import json
import time
import pynvim
from vari_inspector import get_python_inspector, get_r_inspector 
from jupyter_client import KernelManager, BlockingKernelClient

@pynvim.plugin
class PyrolaPlugin(object):
    def __init__(self, nvim):
        self.nvim = nvim
        self.kernel_manager = None
        self.client = None


    @pynvim.function('InitKernel', sync=True)
    def init_kernel(self, args):
        """Initialize Jupyter kernel and return connection file path."""
        try:
            kernel_name = args[0] if args else self.nvim.err_write("failed to got kernel name!")

            self.kernel_manager = KernelManager(kernel_name=kernel_name)

            self.kernel_manager.start_kernel()
            self.client = self.kernel_manager.client()
            self.client.start_channels()

            return self.kernel_manager.connection_file

        except Exception as e:
            self.nvim.err_write(f"Kernel initialization failed: {str(e)}\n")
            return None

    def _connect_kernel(self, connection_file):
        """Connect to the Jupyter kernel using the connection file."""
        try:
            with open(connection_file, 'r') as f:
                connection_info = json.load(f)

            self.client = BlockingKernelClient()
            self.client.load_connection_info(connection_info)
            self.client.start_channels()
            return True
        except Exception as e:
            print(f"Connection error: {e}")
            return False

    def _handle_kernel_message(self):
        """Handle messages from the kernel."""
        try:
            msg = self.client.get_iopub_msg(timeout=1)
            
            if msg['msg_type'] == 'stream':
                return msg['content']['text']
            elif msg['msg_type'] == 'execute_result':
                return msg['content']['data'].get('text/plain')
            elif msg['msg_type'] == 'error':
                return f"Error: {msg['content']['ename']}: {msg['content']['evalue']}"
            elif msg['msg_type'] == 'status' and msg['content']['execution_state'] == 'idle':
                return 'IDLE'
            return None
        except Exception as e:
            print(f"Message handling error: {e}")
            return None

    @pynvim.function('ExecuteKernelCode', sync=True)
    def execute_code(self, args):
        """Execute code in the Jupyter kernel."""
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

            msg_id = self.client.execute(code)
            print(f"Executed with msg_id: {msg_id}")

            outputs = []
            while True:
                msg = self._handle_kernel_message()
                if msg == 'IDLE':
                    break
                if msg is not None:
                    outputs.append(msg)
                    
            return '\n'.join(outputs) if outputs else "No output received"

        except Exception as e:
            print(f"Execution error: {e}")
            return f"Execution error: {str(e)}"

        finally:
            if self.client:
                self.client.stop_channels()
                self.client = None


    @pynvim.function('ShutdownKernel', sync=True)
    def shutdown_kernel(self, args):
        """Shutdown the Jupyter kernel."""
        filetype, connection_file = args
        
        try:
            if not self._connect_kernel(connection_file):
                return False
                
            # Send shutdown request
            self.client.shutdown()
            
            # Wait for confirmation (optional, but recommended)
            timeout = 0.2  # 0.2 seconds timeout
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    msg = self.client.get_iopub_msg(timeout=0.5)
                    if msg['msg_type'] == 'status' and msg['content']['execution_state'] == 'dead':
                        break
                except Exception:
                    pass
                    
            # Clean up resources
            if self.client:
                self.client.stop_channels()
                self.client = None
                
            if self.kernel_manager:
                self.kernel_manager.shutdown_kernel(now=True)
                self.kernel_manager = None
                
            return True
            
        except Exception as e:
            self.nvim.err_write(f"Kernel shutdown failed: {str(e)}\n")
            return False
            
        finally:
            # Ensure channels are stopped even if an error occurs
            if self.client:
                self.client.stop_channels()
                self.client = None



