#!/usr/bin/python
import sys
import os
from base64 import standard_b64encode
import termios
import tty
import select

def get_cursor_position():
    # Save current terminal settings
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    
    try:
        # Set terminal to raw mode
        tty.setraw(sys.stdin.fileno())
        
        # Query cursor position
        sys.stdout.buffer.write(b'\033[6n')
        sys.stdout.buffer.flush()
        
        # Read response
        response = ''
        while True:
            r, _, _ = select.select([sys.stdin], [], [], 0.1)
            if not r:
                break
                
            char = sys.stdin.read(1)
            if char == 'R':
                response += char
                break
            response += char
            
        # Parse response (format: \033[{row};{col}R)
        if response.startswith('\033['):
            parts = response[2:].split(';')
            if len(parts) == 2:
                row = int(parts[0])
                col = int(parts[1][:-1])
                return row, col
                
    finally:
        # Restore terminal settings
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    
    return 1, 1  # fallback default

def detect_tmux():
    return os.environ.get('TMUX', '') != ''

def serialize_gr_command(**cmd):
    payload = cmd.pop('payload', None)
    
    # Get current cursor position
    row, col = get_cursor_position()
    
    # Calculate pixel offsets (assuming standard terminal cell size)
    cell_width = 8  # typical terminal cell width in pixels
    cell_height = 16  # typical terminal cell height in pixels
    
    x_offset = 0  # Start from left edge
    y_offset = row * cell_height  # Position image at current row
    
    # Add pixel offsets
    cmd['X'] = x_offset  # absolute x position 
    cmd['Y'] = y_offset  # absolute y position
    
    if detect_tmux():
        cmd['x'] = x_offset
        cmd['y'] = y_offset
        
    cmd = ','.join(f'{k}={v}' for k, v in cmd.items())
    
    graphics_cmd = []
    graphics_cmd.append(b'\033_G')
    graphics_cmd.append(cmd.encode('ascii'))
    if payload:
        graphics_cmd.append(b';')
        graphics_cmd.append(payload)
    graphics_cmd.append(b'\033\\')
    
    if detect_tmux():
        result = []
        result.append(b'\033Ptmux;')
        cmd_bytes = b''.join(graphics_cmd)
        cmd_bytes = cmd_bytes.replace(b'\033', b'\033\033')
        result.append(cmd_bytes)
        result.append(b'\033\\')
        return b''.join(result)
    else:
        return b''.join(graphics_cmd)

def write_chunked(**cmd):
    data = cmd.pop('data').encode('ascii')
    # Use more accurate height calculation
    try:
        import base64
        import io
        from PIL import Image
        # Decode base64 to get actual image dimensions
        img_data = base64.b64decode(data)
        img = Image.open(io.BytesIO(img_data))
        image_height = img.height
        print("image_height",image_height)
    except:
        # Fallback to estimated height if image processing fails
        image_height = 100  # Reduced from 500 to a more reasonable default
    
    cell_height = 16
    terminal_rows = (image_height + cell_height - 1) // cell_height
    
    while data:
        chunk, data = data[:4096], data[4096:]
        m = 1 if data else 0
        cmd_bytes = serialize_gr_command(payload=chunk, m=m, **cmd)
        sys.stdout.buffer.write(cmd_bytes)
        sys.stdout.buffer.flush()
        cmd.clear()
    
    # Adjust cursor position based on environment
    if detect_tmux():
        # Use smaller offset for tmux
        terminal_rows = max(1, terminal_rows // 2)
    
    sys.stdout.write(f"\033[{terminal_rows}B")
    sys.stdout.flush()
    
    # Clear any remaining input
    while True:
        r, _, _ = select.select([sys.stdin], [], [], 0)
        if not r:
            break
        sys.stdin.read(1)


def enable_tmux_passthrough():
    if detect_tmux():
        enable_seq = b'\033Ptmux;\033\033]52;c;1\007\033\\'
        sys.stdout.buffer.write(enable_seq)
        sys.stdout.buffer.flush()



# Enable tmux passthrough first
enable_tmux_passthrough()

# # Send the image with pixel offset parameters
# write_chunked(
#     a='T',          # Transmit and display
#     f=100,          # Format (PNG)
#     t='d',          # Temporary file
#     s=1,            # Suppress responses
#     data=img64
# )
