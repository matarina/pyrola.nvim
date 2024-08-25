import threading
import inspect
import os
import types
from textwrap import dedent
from IPython import get_ipython
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import atexit
import io
import sys

ipython = get_ipython()
httpd = None  # Global reference to the server

def query_object_info(obj):
    """
    Query detailed information about a Python object and return it as a formatted string.

    Parameters:
    - obj: The object to inspect.

    Returns:
    - info_str: A formatted string containing the object's type, class, string representation,
                length, docstring, and, if callable, the function signature and init docstring.
    """
    info_lines = []

    # Object Type and Class
    info_lines.append(f"Type: {type(obj).__name__}")
    info_lines.append(f"Class: {obj.__class__.__name__ if hasattr(obj, '__class__') else 'N/A'}")

    # String Representation
    try:
        info_lines.append(f"String : {str(obj)}")
    except Exception as e:
        info_lines.append(f"String : Error - {e}")

    # Length (for collections)
    if hasattr(obj, '__len__'):
        try:
            info_lines.append(f"Length: {len(obj)}")
        except Exception as e:
            info_lines.append(f"Length: Error in calculating length - {e}")
    else:
        info_lines.append(f"Length: N/A")

    # Docstrings
    docstring = inspect.getdoc(obj) or "<No docstring available>"
    info_lines.append(f"Docstring: {docstring}")

    # Callable Signature and Docstring
    if callable(obj):
        try:
            signature = inspect.signature(obj)
            info_lines.append(f"Signature: {obj}{signature}")
        except ValueError as e:
            info_lines.append(f"Signature: Could not retrieve signature - {e}")
        
        # If the object has an __init__ method, get its docstring as well
        if inspect.isclass(obj):
            init_doc = inspect.getdoc(obj.__init__) or "<No __init__ docstring available>"
            info_lines.append(f"Init Docstring: {init_doc}")
        else:
            info_lines.append(f"Init Docstring: N/A")

    # Join all lines into a single formatted string
    info_str = "\n".join(info_lines)

    return info_str

# Define the HTTP request handler
class GlobalEnvHandler(BaseHTTPRequestHandler):

    def _set_headers(self, content_type='application/json'):
        """Helper method to set the headers."""
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.end_headers()

    def capture_output(self, func):
        """Capture the stdout output of a function."""
        captured_output = io.StringIO()
        original_stdout = sys.stdout
        try:
            sys.stdout = captured_output
            func()
            output = captured_output.getvalue()
        finally:
            sys.stdout = original_stdout
        
        return output

    def do_GET(self):
        """Handle GET requests."""
        # Parse the path to determine what action to take
        if self.path == '/query_global':
            self.query_global()
        elif self.path.startswith('/inspect_var'):
            var_name = self.path.split('=')[-1]
            self.inspect_var(var_name)
        else:
            self.send_error(404, "Path not found")

    def query_global(self):
        """Retrieve and return the list of global variables."""
        global_vars = self.capture_output(lambda: ipython.run_line_magic("whos", ""))
        self._set_headers()
        # Convert the output to JSON string
        self.wfile.write(json.dumps({"globals": global_vars}, default=str).encode('utf-8'))

    def inspect_var(self, var_name):
        """Inspect a specific variable by name."""
        try:
            var = globals().get(var_name, None)
            if var is None:
                self.send_error(400, f"Variable '{var_name}' not found.")
                return

            var_info = query_object_info(var)
            self._set_headers()
            self.wfile.write(json.dumps({"info": var_info}, default=str).encode('utf-8'))
        except Exception as e:
            self.send_error(400, f"Error inspecting variable: {e}")

def start_http_server(port):
    global httpd
    server_address = ('', port)
    httpd = HTTPServer(server_address, GlobalEnvHandler)
    print(f"Starting server on port {port}")
    httpd.serve_forever()


def stop_http_server():
    global httpd
    if httpd:
        print("Shutting down server...")
        httpd.shutdown()
        httpd.server_close()
        print("Server shut down.")

# Register the shutdown function to be called on exit
atexit.register(stop_http_server)

def init_python_server(port):
    server_thread = threading.Thread(target=start_http_server, args=(port,))
    server_thread.daemon = True  # Ensure the thread exits when the main program exits
    server_thread.start()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
        init_python_server(port)
    else:
        print("Please provide a port number as an argument.")
