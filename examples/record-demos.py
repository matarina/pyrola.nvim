#!/usr/bin/env python3
"""Record real Neovim/Kitty sessions, including bitmap plots, as README GIFs.

Linux dependencies: Xvfb, Kitty, FFmpeg, Neovim 0.12+, a Python Tree-sitter
parser in Neovim's runtime path, and the plugin requirements plus ipykernel,
NumPy, and Matplotlib in the Python running this script.

Run from any directory: python3 examples/record-demos.py
Temporary videos, logs, and verification results go in artifacts/readme-recordings.
The recorder owns a separate X display and never types into the user's desktop.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import pynvim

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'artifacts/readme-recordings'
OUTPUT = ROOT / 'docs/gifs'
WIDTH, HEIGHT, FPS = 1280, 800, 10

SOURCES = {
    'send-code': '''# Send Python from the editor to a live kernel.
# Enter: semantic block | Space v s: selection

values = [12, 18, 24, 30]

def summarize(items):
    mean = sum(items) / len(items)
    return {"count": len(items), "mean": mean}

print("Summary:", summarize(values))

scaled = [value * 2 for value in values]
print("Scaled:", scaled)
print("Total:", sum(scaled))
''',
    'inspect-variables': '''# Inspect live objects without adding print calls.
# Space v b: run buffer | Space i g: globals
# Enter: inspect a global | Space i s: inspect

import numpy as np

measurements = np.array([
    [1.2, 2.4, 3.6],
    [2.0, 4.0, 6.0],
    [3.1, 6.2, 9.3],
])
column_means = measurements.mean(axis=0)
experiment = {"name": "dose response", "runs": 3}
print("Measurements:", measurements.shape)
print("Column means:", column_means)
''',
    'plots-and-history': '''# Bitmap plots stay attached to REPL output.
# Space i m: image history | h / l: browse | q: close

import numpy as np
import matplotlib.pyplot as plt

x = np.linspace(0, 2 * np.pi, 160)

def plot_signal(label, y, color):
    fig, ax = plt.subplots(figsize=(5.4, 2.8))
    ax.plot(x, y, color=color, linewidth=2.5)
    ax.set(title=label, xlabel="Time", ylabel="Signal")
    ax.grid(alpha=0.2)
    fig.tight_layout()
    plt.show()

plot_signal("Sine wave", np.sin(x), "#0d9488")
plot_signal("Cosine wave", np.cos(x), "#7c3aed")
print("Both plots are saved in image history.")
''',
    'interrupt-recover': '''# Interrupt a running cell and keep your variables.
# Enter: run | Space i k: interrupt kernel

import time
answer = 42

print("Starting a 30-second calculation...")
time.sleep(30)

print("Kernel recovered. Answer:", answer)
print("Next calculation:", answer * 2)
''',
}


def wait_for(check, label, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.05)
    raise RuntimeError(f'Timed out: {label}')


class Demo:
    def __init__(self, nvim):
        self.nvim = nvim
        self.source = None

    def lua(self, code, *args):
        return self.nvim.exec_lua(code, *args)

    def caption(self, text):
        self.nvim.vars['demo_caption'] = text
        self.nvim.command('redraw!')
        time.sleep(0.5)

    def keys(self, keys, pause=0.4):
        self.nvim.input(keys)
        time.sleep(pause)

    def at(self, text, column=0):
        lines = self.nvim.current.buffer[:]
        row = next(i for i, line in enumerate(lines, 1) if line.startswith(text))
        self.nvim.current.window.cursor = (row, column)
        self.nvim.command('normal! zz')

    def terminal(self):
        return self.lua("return vim.api.nvim_buf_get_lines(require('pyrola').term.bufid, 0, -1, false)")

    def output(self, text):
        wait_for(lambda: text in '\n'.join(self.terminal()), f'REPL output {text!r}')
        wait_for(lambda: self.lua("return require('pyrola').status()") == 'ready', 'kernel ready')

    def enter(self, text):
        self.at(text)
        self.keys('<CR>')
        wait_for(lambda: self.lua("return require('pyrola').status()") == 'ready', 'cell complete')

    def floats(self):
        return self.lua("return vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= '' end, vim.api.nvim_list_wins())")

    def close_floats(self):
        self.lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.api.nvim_win_get_config(w).relative ~= '' then vim.api.nvim_win_close(w, true) end end")
        self.nvim.api.set_current_win(self.source)

    def load(self, name, title):
        self.close_floats()
        self.nvim.command('edit ' + str(WORK / (name + '.py')))
        self.source = self.nvim.current.window.handle
        self.nvim.vars['demo_title'] = 'PYROLA  /  ' + title
        self.caption('Live Python kernel  |  Mappings use Space as <leader>')


def send_code(d):
    d.caption('Enter  /  Send the statement under the cursor')
    d.enter('values =')
    d.caption('Enter  /  Send a complete function with Tree-sitter')
    d.enter('def summarize')
    d.enter('print("Summary:')
    d.output("Summary: {'count': 4, 'mean': 21.0}")
    time.sleep(1.3)
    d.caption('V + j j, then Space v s  /  Send a visual selection')
    d.at('scaled =')
    d.keys('Vjj', pause=1)
    d.keys(' vs')
    d.output('Total: 168')
    time.sleep(2)


def inspect_variables(d):
    d.caption('Space v b  /  Send the entire buffer')
    d.keys(' vb')
    d.output('Measurements: (3, 3)')
    time.sleep(0.8)
    d.caption('Space i g  /  Browse live global variables')
    d.keys(' ig')
    wait_for(lambda: len(d.floats()) == 1, 'globals float')
    d.at('measurements')
    time.sleep(1.8)
    d.caption('Enter  /  Inspect the selected array: type, shape, values')
    d.keys('<CR>')
    wait_for(lambda: len(d.floats()) == 2, 'array inspector')
    assert 'NumPy Array' in '\n'.join(d.nvim.current.buffer[:])
    time.sleep(2.5)
    d.keys('q')
    d.keys('q')
    d.nvim.api.set_current_win(d.source)
    d.at('experiment =')
    d.caption('Space i s  /  Inspect the symbol under the cursor')
    d.keys(' is')
    wait_for(lambda: len(d.floats()) == 1, 'dictionary inspector')
    assert 'dose response' in '\n'.join(d.nvim.current.buffer[:])
    time.sleep(2.5)
    d.keys('q')


def plots(d):
    d.caption('Space v b  /  Render full-color Matplotlib plots inline')
    d.keys(' vb')
    d.output('Both plots are saved in image history.')
    wait_for(lambda: d.lua("return #require('pyrola.image').history") == 2, 'two plot images')
    time.sleep(2)
    d.caption('Ctrl-W l, Ctrl-U  /  Plots scroll with their REPL output')
    d.keys('<C-w>l')
    d.keys('<C-\\><C-n>')
    d.lua('vim.wo.statusline = vim.go.statusline')
    before = d.nvim.eval('winsaveview().topline')
    d.keys('<C-u>', pause=1.8)
    assert d.nvim.eval('winsaveview().topline') < before, 'The REPL viewport did not scroll'
    d.keys('<C-d>G', pause=1)
    d.nvim.api.set_current_win(d.source)
    d.caption('Space i m  /  Open a larger floating image preview')
    d.keys(' im')
    wait_for(lambda: d.lua("return require('pyrola.image').manager_active"), 'image history open')
    time.sleep(1.5)
    d.caption('h  /  Previous plot: sine wave')
    d.keys('h', pause=1.8)
    assert d.lua("return require('pyrola.image').history_index") == 1
    d.caption('l  /  Next plot: cosine wave')
    d.keys('l', pause=1.8)
    assert d.lua("return require('pyrola.image').history_index") == 2
    d.caption('q  /  Close the preview and return to your code')
    d.keys('q', pause=1.3)


def interrupt(d):
    d.caption('Enter  /  Run setup statements in the same kernel')
    d.enter('import time')
    d.enter('answer =')
    d.enter('print("Starting')
    d.output('Starting a 30-second calculation...')
    d.caption('Enter  /  Start a long-running calculation')
    d.at('time.sleep')
    started = time.monotonic()
    d.keys('<CR>')
    wait_for(lambda: d.lua("return require('pyrola').status()") == 'busy', 'busy kernel')
    time.sleep(1.5)
    d.caption('Space i k  /  Interrupt without restarting the kernel')
    d.keys(' ik')
    # The console may display ^C rather than a Python traceback. Verify that
    # the 30-second cell finishes early and the same kernel accepts more work.
    wait_for(lambda: d.lua("return require('pyrola').status()") == 'ready', 'interrupt recovery', timeout=10)
    assert time.monotonic() - started < 15, 'The sleep was not interrupted early'
    time.sleep(1)
    d.caption('Enter  /  Keep working with the existing variables')
    d.enter('print("Kernel recovered')
    d.enter('print("Next calculation')
    d.output('Next calculation: 84')
    time.sleep(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=SOURCES, help='Re-record one demo')
    args = parser.parse_args()
    for tool in ('Xvfb', 'kitty', 'ffmpeg', 'nvim'):
        if not shutil.which(tool):
            raise SystemExit(f'Missing executable: {tool}')
    WORK.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, source in SOURCES.items():
        (WORK / (name + '.py')).write_text(source)
    children = []
    nvim = None
    with tempfile.TemporaryDirectory(prefix='pyrola-record-') as temp:
        try:
            # Let Xvfb choose an unused display instead of claiming the desktop.
            read_fd, write_fd = os.pipe()
            xlog = (WORK / 'xvfb.log').open('w')
            server = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0', f'{WIDTH}x{HEIGHT}x24', '-nolisten', 'tcp', '-ac'], pass_fds=(write_fd,), stdout=xlog, stderr=xlog)
            children.append(server)
            os.close(write_fd)
            with os.fdopen(read_fd) as stream:
                display = ':' + stream.readline().strip()
            env = dict(os.environ, DISPLAY=display, LIBGL_ALWAYS_SOFTWARE='1', PYROLA_DEMO_ROOT=str(ROOT), PYROLA_DEMO_PYTHON=sys.executable)
            env.pop('WAYLAND_DISPLAY', None)
            command = ['kitty', '--config', 'NONE', '--title', 'Pyrola README recordings']
            for option in (f'initial_window_width={WIDTH}', f'initial_window_height={HEIGHT}', 'remember_window_size=no', 'window_padding_width=8', 'font_family=monospace', 'font_size=13', 'background=#101820', 'foreground=#e2e8f0', 'cursor_blink_interval=0', 'enable_audio_bell=no', 'confirm_os_window_close=0', 'linux_display_server=x11'):
                command += ['-o', option]
            results = []
            verification = WORK / 'verification.json'
            if args.only and verification.exists():
                results = [item for item in json.loads(verification.read_text()) if item['demo'] != args.only]
            for name, title, action in (
                ('send-code', '01  Send code from your editor', send_code),
                ('inspect-variables', '02  Explore live Python objects', inspect_variables),
                ('plots-and-history', '03  Inline plots and image history', plots),
                ('interrupt-recover', '04  Interrupt and keep working', interrupt),
            ):
                if args.only and name != args.only:
                    continue
                # A fresh editor/kernel keeps each recording independent.
                socket = str(Path(temp) / (name + '.sock'))
                with (WORK / (name + '-kitty.log')).open('w') as klog:
                    editor = subprocess.Popen(command + ['nvim', '-u', str(ROOT / 'examples/recording-init.lua'), '-i', 'NONE', '--listen', socket, str(WORK / (name + '.py'))], env=env, cwd=ROOT, stdout=klog, stderr=klog)
                children.append(editor)
                wait_for(lambda: Path(socket).exists(), 'Neovim RPC socket')
                nvim = pynvim.attach('socket', path=socket)
                wait_for(lambda: nvim.eval("exists(':Pyrola')") == 2 and nvim.current.buffer.options['filetype'] == 'python', 'demo configuration loaded')
                d = Demo(nvim)
                assert d.lua("local ok = pcall(vim.treesitter.get_parser, 0, 'python'); return ok"), 'Install the Python Tree-sitter parser first'
                d.source = nvim.current.window.handle
                nvim.command('Pyrola init')
                wait_for(lambda: d.lua("return require('pyrola').status()") == 'ready', 'kernel startup')
                nvim.api.set_current_win(d.source)
                d.load(name, title)
                video = WORK / (name + '.mkv')
                with (WORK / (name + '.log')).open('w') as log:
                    recorder = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'x11grab', '-draw_mouse', '0', '-framerate', str(FPS), '-video_size', f'{WIDTH}x{HEIGHT}', '-i', display + '.0', '-c:v', 'ffv1', str(video)], stdout=log, stderr=log)
                    children.append(recorder)
                    time.sleep(0.5)
                    try:
                        action(d)
                    finally:
                        recorder.send_signal(signal.SIGINT)
                        recorder.wait(timeout=15)
                    if recorder.returncode not in (0, 255):
                        raise RuntimeError(f'Recording failed: {name}; see {log.name}')
                gif = OUTPUT / (name + '.gif')
                subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(video), '-filter_complex', '[0:v]split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle', '-loop', '0', str(gif)], check=True)
                results.append({'demo': name, 'verified': True, 'bytes': gif.stat().st_size})
                print(f'PASS {name}: {gif.stat().st_size / 1024:.0f} KiB', flush=True)
                nvim.command('qa!', async_=True)
                nvim.close()
                nvim = None
                editor.wait(timeout=15)
            (WORK / 'verification.json').write_text(json.dumps(results, indent=2) + '\n')
        finally:
            if nvim is not None:
                try:
                    nvim.command('qa!')
                except (EOFError, OSError):
                    pass
                nvim.close()
            for child in reversed(children):
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()


if __name__ == '__main__':
    main()
