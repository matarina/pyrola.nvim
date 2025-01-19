import sys
import os
import signal
import json
import time
import asyncio
from prompt_toolkit.formatted_text import HTML
from typing import Optional, List
from jupyter_client import BlockingKernelClient
from queue import Empty
import argparse
from prompt_toolkit import print_formatted_text
from prompt_toolkit import PromptSession
from prompt_toolkit.history import InMemoryHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.filters import Condition
from prompt_toolkit.formatted_text import ANSI
from prompt_toolkit.shortcuts import PromptSession
from prompt_toolkit.styles import Style
from prompt_toolkit.layout.processors import ConditionalProcessor, BeforeInput
from prompt_toolkit.buffer import Buffer
from prompt_toolkit.filters import to_filter
import re


import re

class ReplInterpreter:
    def __init__(self, connection_file: Optional[str] = None):
        self.buffer: List[str] = []
        self._pending_clearoutput = False
        self._executing = False
        self._execution_state = 'idle'
        self.kernel_info = {}
        self.in_multiline = False
        self.multiline_buffer = []
        self._interrupt_requested = False
        
        # Setup prompt toolkit
        self.history = InMemoryHistory()
        self.bindings = self._create_keybindings()
        
        # Define custom style with correct color format
        self.style = Style.from_dict({
            'prompt': '#ff8c00',  
            'continuation': '#ff8c00',
        })
        self.style = Style.from_dict({
            'orange': '#ff8c00',
            'ansired': '#67ebe2 underline',
        })
        

        
        def continuation_prompt(width, line_number, is_soft_wrap):
            return HTML('<orange>.. </orange>')
            
        self.session = PromptSession(
            history=self.history,
            key_bindings=self.bindings,
            enable_history_search=True,
            multiline=True,
            style=self.style,
            prompt_continuation=continuation_prompt,
            message=lambda: HTML('<orange>>> </orange>')
        )

        self._setup_signal_handlers()
        
        if connection_file:
            try:
                with open(connection_file) as f:
                    connection_info = json.load(f)
                self.client = BlockingKernelClient()
                self.client.load_connection_info(connection_info)
                self.client.start_channels()
                self.client.wait_for_ready(timeout=10)
                self.kernelname = connection_info.get("kernel_name")
            except Exception as e:
                print(f"Failed to connect to kernel: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            print("No kernel connection file specified", file=sys.stderr)
            sys.exit(1)



    def _create_keybindings(self):
        kb = KeyBindings()
        
        @kb.add('enter')
        def _(event):
            b = event.current_buffer
            
            if b.document.text.strip():
                # Get the full text including the current line
                full_text = b.document.text
                
                # Check if the input is complete
                status, indent = self.handle_is_complete(full_text)
                
                if status == 'incomplete':
                    self.in_multiline = True
                    event.current_buffer.newline()
                    if indent:
                        event.current_buffer.insert_text(indent)
                else:
                    event.current_buffer.validate_and_handle()
            else:
                if self.buffer:
                    event.current_buffer.newline()
                else:
                    self.in_multiline = False
                    event.current_buffer.validate_and_handle()


        @kb.add('c-c')
        def _(event):
            if self._executing:
                self._interrupt_requested = True
                try:
                    self.client.interrupt_kernel()
                except Exception as e:
                    print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
            else:
                print("\nKeyboardInterrupt")
                self.in_multiline = False
                event.current_buffer.reset()
                
        return kb


    async def interact_async(self, banner: Optional[str] = None):
        print_formatted_text(
            HTML('<orange>Welcome to Pyrola! kernel</orange> <ansired>{}</ansired> <orange>initialized!</orange>'.format(self.kernelname)),
            style=self.style
        )

        while True:
            try:
                # Get input with dynamic prompt
                code = await self.session.prompt_async()
                
                if code.strip() in ('exit', 'quit'):
                   print_formatted_text(
                           HTML('<orange>Shutting down kernel...</orange>'),
                           style=self.style)
                   break
                    
                if code.strip():
                    # Before execution, check if it's complete
                    status, _ = self.handle_is_complete(code)
                    if status == 'incomplete':
                        self.in_multiline = True
                        self.buffer.append(code)
                        continue
                    else:
                        # If we have buffered content, include it
                        if self.buffer:
                            code = '\n'.join(self.buffer + [code])
                            self.buffer.clear()
                        self.in_multiline = False
                        await self.handle_execute(code)
                    
            except KeyboardInterrupt:
                self.in_multiline = False
                self.buffer.clear()
                continue

            except EOFError:
                break

        if hasattr(self, 'client') and self.client is not None:
            self.client.shutdown()
            self.client.stop_channels()





    def init_kernel_info(self):
        timeout = 10
        tic = time.time()
        msg_id = self.client.kernel_info()
        
        while True:
            try:
                reply = self.client.get_shell_msg(timeout=1)
                if reply['parent_header'].get('msg_id') == msg_id:
                    self.kernel_info = reply['content']
                    return
            except Empty:
                if (time.time() - tic) > timeout:
                    raise RuntimeError("Kernel didn't respond to kernel_info_request")

    def _setup_signal_handlers(self):
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum, frame):
        if self._executing:
            self._interrupt_requested = True
            try:
                self.client.interrupt_kernel()
            except Exception as e:
                print(f"\nFailed to interrupt kernel: {e}", file=sys.stderr)
        else:
            print("\nKeyboardInterrupt")

    def handle_is_complete(self, code):
        while self.client.shell_channel.msg_ready():
            self.client.get_shell_msg()
            
        msg_id = self.client.is_complete(code)
        try:
            reply = self.client.get_shell_msg(timeout=0.5)
            if reply['parent_header'].get('msg_id') == msg_id:
                status = reply['content']['status']
                indent = reply['content'].get('indent', '')
                return status, indent
        except Empty:
            pass
        return 'unknown', ''


    async def handle_execute(self, code):

        self._interrupt_requested = False
        
        while self.client.shell_channel.msg_ready():
            self.client.get_shell_msg()
            
        msg_id = self.client.execute(code)
        self._executing = True
        self._execution_state = 'busy'
        
        try:
            while self._execution_state != 'idle' and self.client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    await self.handle_input_request(msg_id, timeout=0.05)
                except Empty:
                    await self.handle_iopub_msgs(msg_id)
                
                await asyncio.sleep(0.01)
            
            while self.client.is_alive():
                if self._interrupt_requested:
                    print("\nKeyboardInterrupt")
                    self._interrupt_requested = False
                    return False

                try:
                    msg = self.client.get_shell_msg(timeout=0.05)
                    if msg['parent_header'].get('msg_id') == msg_id:
                        await self.handle_iopub_msgs(msg_id)
                        content = msg['content']
                        # Set multiline to False only after execution is complete
                        self.in_multiline = False
                        return content['status'] == 'ok'
                except Empty:
                    await asyncio.sleep(0.01)
                    
        finally:
            self._executing = False
            self._interrupt_requested = False
            self.in_multiline = False  # Ensure it's set to False in case of errors
            
        return False



    async def handle_input_request(self, msg_id, timeout=0.1):
        msg = self.client.get_stdin_msg(timeout=timeout)
        if msg_id == msg["parent_header"].get("msg_id"):
            content = msg['content']
            try:
                raw_data = await self.session.prompt_async(content["prompt"])
                if not (self.client.stdin_channel.msg_ready() or 
                       self.client.shell_channel.msg_ready()):
                    self.client.input(raw_data)
            except (EOFError, KeyboardInterrupt):
                print('\n')
                return

    async def handle_iopub_msgs(self, msg_id):
        while self.client.iopub_channel.msg_ready():
            msg = self.client.get_iopub_msg()
            msg_type = msg['header']['msg_type']
            parent_id = msg['parent_header'].get('msg_id')
            
            if parent_id != msg_id:
                continue

            if msg_type == 'status':
                self._execution_state = msg['content']['execution_state']
                
            elif msg_type == 'stream':
                content = msg['content']
                if self._pending_clearoutput:
                    sys.stdout.write("\r")
                    self._pending_clearoutput = False
                    
                if content['name'] == 'stdout':
                    sys.stdout.write(content['text'])
                    sys.stdout.flush()
                elif content['name'] == 'stderr':
                    sys.stderr.write(content['text'])
                    sys.stderr.flush()
            
            elif msg_type in ('execute_result', 'display_data'):
                if self._pending_clearoutput:
                    sys.stdout.write("\r")
                    self._pending_clearoutput = False
                    
                content = msg['content']
                if 'text/plain' in content.get('data', {}):
                    print(content['data']['text/plain'])
                sys.stdout.flush()
            
            elif msg_type == 'error':
                content = msg['content']
                for frame in content['traceback']:
                    print(frame, file=sys.stderr)
                sys.stderr.flush()
                
            elif msg_type == 'clear_output':
                if msg['content'].get('wait', False):
                    self._pending_clearoutput = True
                else:
                    sys.stdout.write("\r")

    def interact(self, banner: Optional[str] = None):
        asyncio.run(self.interact_async(banner))

def main():
    parser = argparse.ArgumentParser(description='Jupyter Console')
    parser.add_argument('--existing', 
                      type=str, 
                      help='Connect to an existing kernel. Specify the connection file path.')
    args = parser.parse_args()

    interpreter = ReplInterpreter(connection_file=args.existing)
    interpreter.interact()

if __name__ == "__main__":
    main()


