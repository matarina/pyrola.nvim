#!/usr/bin/env python3
"""Exercise Pyrola in real Kitty/Neovim/Jupyter sessions, without UI mocks.

Run with the plugin's Python environment:
  .venv/bin/python tests/real_execution.py --languages python r

Requires Kitty, Neovim, Xvfb, ffmpeg, NumPy, Matplotlib and pandas. R also
requires R/IRkernel on PATH (or an installed ir kernelspec). Results and
screenshots are written under artifacts/real-execution. Uses its own X display.
"""

import argparse
import base64
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import traceback

import pynvim
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/real-execution'

INIT = r"""
vim.opt.rtp:prepend(vim.env.PYROLA_TEST_ROOT)
vim.g.mapleader = ' '
vim.o.swapfile = false
vim.o.termguicolors = true
vim.o.number = true
vim.o.laststatus = 2
vim.cmd('filetype plugin indent on')
vim.cmd.colorscheme('habamax')
vim.g.live_notifications = {}
vim.notify = function(msg, level)
    -- vim.g tables are copies; assign explicitly for the external test runner.
    local notes = vim.g.live_notifications
    notes[#notes+1] = {message=msg, level=level or 2}
    vim.g.live_notifications = notes
end
local p = require('pyrola').setup({
    python_path=vim.env.PYROLA_TEST_PYTHON,
    split_ratio=0.52,
    image={protocol='kitty', inline='kitty', max_width_ratio=0.85, max_height_ratio=0.45},
})
vim.g.live_ready_count = 0
local on_ready = p._on_repl_ready
p._on_repl_ready = function()
    vim.g.live_ready_count = vim.g.live_ready_count + 1
    on_ready()
end
for lhs, method in pairs({['<CR>']='send_statement_definition',
    ['<Space>vb']='send_buffer_to_repl', ['<Space>is']='inspect',
    ['<Space>ig']='show_globals', ['<Space>ik']='interrupt_kernel',
    ['<Space>im']='open_history_manager'}) do
    vim.keymap.set('n', lhs, p[method])
end
vim.keymap.set('x', '<Space>vs', p.send_visual_to_repl)
"""


def wait(check, label, timeout=35):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.05)
    raise AssertionError('Timed out: ' + label)


class Session:
    def __init__(self, nvim, language, display):
        self.n = nvim
        self.language = language
        self.display = display
        self.source = nvim.current.window.handle
        self.results = []

    def lua(self, code, *args):
        return self.n.exec_lua(code, *args)

    def check(self, name, action):
        started = time.monotonic()
        try:
            action()
            self.results.append({'name': name, 'status': 'PASS', 'seconds': round(time.monotonic()-started, 2)})
            print(f'PASS {self.language}: {name}', flush=True)
        except Exception:
            self.results.append({'name': name, 'status': 'FAIL', 'traceback': traceback.format_exc()})
            if name.startswith('plot history '):
                print(f'FAIL {self.language}: {name}',flush=True)
                self.lua("for _,w in ipairs(vim.api.nvim_list_wins()) do if vim.api.nvim_win_get_config(w).relative~='' then vim.api.nvim_win_close(w,true) end end")
                self.n.api.set_current_win(self.source)
                return
            raise

    def keys(self, value):
        self.n.input(value)
        time.sleep(0.15)

    def fixture(self, code):
        self.n.api.set_current_win(self.source)
        self.n.current.buffer[:] = code.splitlines()
        self.n.current.window.cursor = (1, 0)

    def terminal(self):
        return '\n'.join(self.lua("return vim.api.nvim_buf_get_lines(require('pyrola').term.bufid,0,-1,false)"))

    def ready(self):
        wait(lambda: self.lua("return require('pyrola').status()") == 'ready', 'REPL ready')

    def output(self, text):
        wait(lambda: text in self.terminal(), repr(text))
        self.ready()

    def run(self, code, output=None):
        self.fixture(code)
        self.lua("require('pyrola').send_buffer_to_repl()")
        if output:
            self.output(output)
        else:
            self.ready()

    def content(self):
        return '\n'.join(self.n.current.buffer[:])

    def inspect(self, symbol, expected):
        self.fixture(symbol)
        self.keys(' is')
        wait(lambda:self.lua("return vim.api.nvim_win_get_config(0).relative")!='','inspector float')
        assert self.lua("return vim.api.nvim_win_get_config(0).relative") != '', self.content()
        assert expected in self.content(), self.content()
        win=self.n.current.window.handle
        self.keys('q')
        wait(lambda:not self.n.api.win_is_valid(win),'inspector closed')

    def screenshot(self, name):
        time.sleep(2)
        if getattr(self, 'desktop', False):
            windows=json.loads(subprocess.check_output(['cua-driver','call','list_windows','--json','{}']))['windows']
            window=next(w for w in windows if w['pid']==self.editor_pid)
            path=OUT / f'{self.language}-{name}.png'
            path.unlink(missing_ok=True)
            payload=dict(pid=window['pid'],window_id=window['window_id'],session=f'pyrola-live-{self.editor_pid}',include_accessibility_tree=False,max_image_dimension=0,screenshot_out_file=str(path))
            subprocess.run(['cua-driver','call','get_window_state','--json',json.dumps(payload)],stdout=subprocess.DEVNULL,check=True)
            assert path.is_file(), 'CUA did not save a new screenshot'
            return path
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'x11grab',
                        '-video_size', '1440x1000', '-i', self.display+'.0',
                        '-frames:v', '1', str(OUT / f'{self.language}-{name}.png')], check=True, timeout=15)
        return OUT / f'{self.language}-{name}.png'

    def dump(self):
        (OUT / f'{self.language}-terminal.txt').write_text(self.terminal())
        (OUT / f'{self.language}-notifications.json').write_text(json.dumps(self.n.vars.get('live_notifications', []), indent=2))

    def assert_plot_pixels(self, path, colors, region=None):
        with Image.open(path) as image:
            # Check the actual curve colors, including transparent R plots.
            if region:
                image=image.crop(region)
            pixels=list(image.convert('RGB').get_flattened_data())
        for color in colors:
            count=sum(sum(abs(a-b) for a,b in zip(pixel,color))<60 for pixel in pixels)
            assert count>120, f'Plot color {color} missing from {path.name}: {count} pixels'


def exercises(s):
    py = s.language == 'python'

    def setup():
        s.n.command('Pyrola setup')
        wait(lambda: s.lua("return require('pyrola')._deps_checked") is True, 'Pyrola setup', 180)
        s.n.command('Pyrola init')
        s.ready()
        assert s.lua("return require('pyrola').active_kernel_name") == 'pyrola_'+s.language
        channel = s.lua("return require('pyrola').term.chanid")
        s.n.command('Pyrola init')
        assert channel == s.lua("return require('pyrola').term.chanid")
    s.check('one-command setup, managed kernel, init and repeat init', setup)

    def buffer():
        code = """import numpy as np
import pandas as pd
answer = 42
arr = np.arange(12).reshape(3, 4)
frame = pd.DataFrame({'dose': [1., 2., 3.], 'response': [2., 4., 6.]})
series = frame['dose']
index = frame.index
experiment = {'name': 'live experiment', 'runs': 3}
def twice(x):
    return x * 2
class Sample:
    label = 'real-object'
sample = Sample()
assert twice(answer) == 84
print('LIVE_' + 'BUFFER', answer)
""" if py else """answer <- 42
arr <- matrix(1:12, nrow=3)
frame <- data.frame(dose=c(1,2,3), response=c(2,4,6))
experiment <- list(name='live experiment', runs=3)
factor_value <- factor(c('treated','control','treated'))
twice <- function(x) {
  x * 2
}
stopifnot(twice(answer) == 84)
cat(paste0('LIVE_', 'BUFFER '), answer, '\\n', sep='')
"""
        s.run(code, 'LIVE_BUFFER 42')
    s.check('whole buffer: real data, function and object definitions', buffer)

    def statement():
        if py:
            s.fixture("def semantic(items):\n    total = sum(items)\n    return total + 10\n\nprint('LIVE_'+'SEMANTIC', semantic([2, 3]))")
            assert s.lua("local ok=pcall(vim.treesitter.get_parser,0,'python'); return ok"), 'Python Tree-sitter parser required'
            s.n.current.window.cursor = (2, 4)
            s.keys('<CR>')
            s.ready()
            s.n.current.window.cursor = (5, 0)
            s.keys('<CR>')
            s.output('LIVE_SEMANTIC 15')
        else:
            s.fixture("statement_value <- 15")
            s.keys('<CR>')
            s.ready()
            s.run("cat(paste0('LIVE_', 'STATEMENT '), statement_value, '\\n', sep='')", 'LIVE_STATEMENT 15')
    s.check('Enter: Python semantic function / R current statement', statement)

    def visual():
        s.fixture("selected_value = 16\nprint('LIVE_'+'VISUAL', selected_value)\nraise RuntimeError('UNSELECTED')" if py else "selected_value <- 16\ncat(paste0('LIVE_', 'VISUAL '), selected_value, '\\n', sep='')\nstop('UNSELECTED')")
        s.keys('Vj')
        s.keys(' vs')
        s.output('LIVE_VISUAL 16')
        assert 'UNSELECTED' not in s.terminal()
    s.check('visual selection excludes unselected code', visual)

    def queue():
        codes = ["import time; time.sleep(0.5); queued = [1]", "queued.append(2)", "queued.append(3); print('LIVE_'+'QUEUE', queued)"] if py else ["Sys.sleep(0.5); queued <- c(1)", "queued <- c(queued,2)", "queued <- c(queued,3); cat(paste0('LIVE_', 'QUEUE '), paste(queued,collapse=','), '\\n', sep='')"]
        # All three submissions occur in one editor callback while the first is busy.
        s.lua(r"""local codes=...; local p=require('pyrola'); vim.api.nvim_set_current_win(_G.live_source)
            for _,code in ipairs(codes) do
                vim.api.nvim_buf_set_lines(0,0,-1,false,vim.split(code,'\n',{plain=true}))
                p.send_buffer_to_repl()
            end""", codes)
        s.output('LIVE_QUEUE [1, 2, 3]' if py else 'LIVE_QUEUE 1,2,3')
        assert s.lua("return #require('pyrola').send_queue") == 0
    s.check('queued sends execute once in submission order', queue)

    def inspection():
        cases = [('answer','42'), ('arr','NumPy Array'), ('frame','Pandas DataFrame'), ('series','Pandas Series'), ('index','RangeIndex'), ('experiment','live experiment'), ('sample','real-object'), ('twice','Function')] if py else [('answer','42'), ('arr','Matrix'), ('frame','Data Frame'), ('experiment','List'), ('factor_value','Levels')]
        for symbol, expected in cases:
            s.inspect(symbol, expected)
        s.inspect('variable_that_does_not_exist', 'NameError' if py else 'not found')
        s.inspect('answer','42')
    s.check('inspect real values, arrays, tables, objects and missing symbol recovery', inspection)

    def globals_browser():
        s.fixture('frame')
        s.keys(' ig')
        wait(lambda:s.lua("return vim.api.nvim_win_get_config(0).relative")!='','globals float')
        assert all(name in s.content() for name in ('answer','arr','frame','experiment')), s.content()
        row = next(i for i,line in enumerate(s.n.current.buffer[:],1) if line.startswith('frame '))
        s.n.current.window.cursor = (row,0)
        globals_win=s.n.current.window.handle
        s.keys('<CR>')
        wait(lambda:s.n.current.window.handle!=globals_win,'globals drill-down inspector')
        assert ('Pandas DataFrame' if py else 'Data Frame') in s.content(), s.content()
        s.screenshot('globals-inspector')
        s.keys('q')
        wait(lambda:s.n.current.window.handle==globals_win,'drill-down inspector closed')
        s.keys('q')
        wait(lambda:not s.n.api.win_is_valid(globals_win),'globals browser closed')
    s.check('globals browser and Enter drill-down to table inspector', globals_browser)

    def errors():
        s.run("raise ValueError('intentional-live-error')" if py else "stop('intentional-live-error')", 'intentional-live-error')
        # The output marker cannot be matched in the echoed submitted code.
        s.run("print('LIVE_'+'RECOVER', answer*2)" if py else "cat(paste0('LIVE_', 'RECOVER '), answer*2, '\\n', sep='')", 'LIVE_RECOVER 84')
        s.run("def invalid(:" if py else "invalid <- )", 'SyntaxError' if py else 'Error in parse')
        s.run("print('LIVE_'+'SYNTAX_RECOVER', answer)" if py else "cat(paste0('LIVE_', 'SYNTAX_RECOVER '), answer, '\\n', sep='')", 'LIVE_SYNTAX_RECOVER 42')
    s.check('runtime and syntax errors preserve kernel and allow next execution', errors)

    def direct_input():
        chan = s.lua("return require('pyrola').term.chanid")
        code = "print('LIVE_'+'DIRECT', answer + 1)" if py else "cat(paste0('LIVE_', 'DIRECT '), answer+1, '\\n', sep='')"
        before=s.n.vars['live_ready_count']
        s.n.api.chan_send(chan, code+'\r')
        s.output('LIVE_DIRECT 43')
        wait(lambda:s.n.vars['live_ready_count']>before,'direct command completed')
        before=s.n.vars['live_ready_count']
        s.n.api.chan_send(chan, '\x1b[A\r')
        wait(lambda: s.terminal().count('LIVE_DIRECT 43') >= 2, 'REPL history execution')
        wait(lambda:s.n.vars['live_ready_count']>before,'history command completed')
    s.check('direct REPL typing and Up/Enter command history', direct_input)

    def multiline_input():
        chan=s.lua("return require('pyrola').term.chanid")
        before=s.n.vars['live_ready_count']
        code="def direct_twice(x):\r    return x * 2\r\r" if py else "direct_twice <- function(x) {\r  x * 2\r}\r"
        s.n.api.chan_send(chan,code)
        wait(lambda:s.n.vars['live_ready_count']>before,'typed multiline function completed')
        s.run("print('LIVE_'+'MULTILINE', direct_twice(answer))" if py else "cat(paste0('LIVE_', 'MULTILINE '),direct_twice(answer),'\\n',sep='')",'LIVE_MULTILINE 84')
    s.check('direct multiline REPL input defines and executes a real function',multiline_input)

    def streams():
        code="import sys; sys.stderr.write('LIVE_'+'STDERR\\n'); print('LIVE_'+'UNICODE 测试 α')" if py else "message(paste0('LIVE_', 'STDERR')); cat(paste0('LIVE_', 'UNICODE 测试 α\\n'))"
        s.run(code,'LIVE_UNICODE 测试 α')
        assert 'LIVE_STDERR' in s.terminal()
    s.check('stdout, stderr and Unicode output delivery',streams)

    def stdin():
        chan = s.lua("return require('pyrola').term.chanid")
        code = "reply=input('LIVE_INPUT_PROMPT: '); print('LIVE_'+'INPUT', reply)" if py else "reply <- readline('LIVE_INPUT_PROMPT: '); cat(paste0('LIVE_', 'INPUT '), reply, '\\n', sep='')"
        before=s.n.vars['live_ready_count']
        s.fixture(code)
        s.lua("require('pyrola').send_buffer_to_repl()")
        # Wait for the actual input prompt after the echoed code.
        wait(lambda: s.terminal().count('LIVE_INPUT_PROMPT:') >= 2, 'kernel stdin prompt')
        s.n.api.chan_send(chan, 'real-response\r')
        s.output('LIVE_INPUT real-response')
        wait(lambda:s.n.vars['live_ready_count']>before,'stdin cell completed')
        s.run("print('LIVE_'+'PROMPT_RESTORED')" if py else "cat(paste0('LIVE_', 'PROMPT_RESTORED\\n'))",'LIVE_PROMPT_RESTORED')
        lines=s.terminal().splitlines()
        command=next(line for line in reversed(lines) if "'PROMPT_RESTORED" in line)
        assert command.startswith('>>'), 'Kernel stdin prompt replaced the normal REPL prompt: '+command
    s.check('kernel stdin input/readline and response delivery', stdin)

    def interrupt():
        code = "import time; print('LIVE_'+'SLEEP_START', flush=True); time.sleep(60)" if py else "cat(paste0('LIVE_', 'SLEEP_START\\n')); flush.console(); Sys.sleep(60)"
        s.fixture(code)
        started = time.monotonic()
        s.keys(' vb')
        wait(lambda: 'LIVE_SLEEP_START' in s.terminal(), 'long cell running')
        assert s.lua("return require('pyrola').status()") == 'busy'
        s.keys(' ik')
        s.ready()
        assert time.monotonic()-started < 15, '60-second cell did not interrupt early'
        s.run("print('LIVE_'+'INTERRUPT_RECOVER', answer)" if py else "cat(paste0('LIVE_', 'INTERRUPT_RECOVER '), answer, '\\n', sep='')", 'LIVE_INTERRUPT_RECOVER 42')
    s.check('interrupt a running 60-second cell and retain prior state', interrupt)

    def manual_busy():
        chan=s.lua("return require('pyrola').term.chanid")
        code="import time; print('LIVE_'+'MANUAL_BUSY', flush=True); time.sleep(60)" if py else "cat(paste0('LIVE_', 'MANUAL_BUSY\\n')); flush.console(); Sys.sleep(60)"
        s.n.api.chan_send(chan,code+'\r')
        wait(lambda:'LIVE_MANUAL_BUSY' in s.terminal(),'direct long-running command')
        wait(lambda:s.lua("return require('pyrola').status()")=='busy','busy status for manually typed code')
        s.lua("require('pyrola').interrupt_kernel()")
        s.ready()
    s.check('manually typed long-running code reports busy and interrupts',manual_busy)

    def plots():
        code = """import matplotlib.pyplot as plt
x = np.linspace(0, 6.28, 120)
for label, y, color in [('Sine', np.sin(x), '#00a0ff'), ('Cosine', np.cos(x), '#ff00a0')]:
    fig, ax = plt.subplots(figsize=(6, 3), dpi=120)
    ax.plot(x, y, color=color, linewidth=2.5)
    ax.set_title(label + ' / real Pyrola execution')
    plt.show()
print('LIVE_'+'PLOTS_DONE')
""" if py else """options(repr.plot.width=6, repr.plot.height=3, repr.plot.res=120, jupyter.plot_mimetypes='image/png')
x <- seq(0,2*pi,length.out=120)
plot(x,sin(x),type='l',col='#00a0ff',lwd=3,main='Sine / real Pyrola execution')
library(ggplot2)
print(ggplot(data.frame(x=x,y=cos(x)),aes(x,y))+geom_line(colour='#ff00a0',linewidth=1.2)+ggtitle('Cosine / ggplot2'))
cat(paste0('LIVE_', 'PLOTS_DONE\\n'))
"""
        s.run(code,'LIVE_PLOTS_DONE')
        wait(lambda: s.lua("return #require('pyrola.image').history") >= 2,'two real PNG plots')
        images = s.lua("return require('pyrola.image').history")
        assert len(images) == 2, f'Expected two plot entries, got {len(images)}'
        for i, entry in enumerate(images):
            raster = base64.b64decode(entry['data'])
            image = Image.open(io.BytesIO(raster))
            assert image.width > 400 and image.height > 200, image.size
            assert image.width == entry['width'] and image.height == entry['height']
            image.save(OUT / f'{s.language}-plot-{i+1}.png')
        assert '\U0010eeee' in s.terminal(), 'Missing real inline bitmap placeholder rows'
        screenshot=s.screenshot('inline-plots')
        s.assert_plot_pixels(screenshot,[(0,160,255),(255,0,160)])
    s.check('real Matplotlib / base R and ggplot2 PNGs render inline', plots)

    def scrolling():
        def state():
            return s.lua("""local t=require('pyrola').term; local rows={}
                for i,line in ipairs(vim.api.nvim_buf_get_lines(t.bufid,0,-1,false)) do
                    if line:find(vim.fn.nr2char(0x10EEEE),1,true) then rows[#rows+1]=i end
                end
                return {rows=rows,top=vim.api.nvim_win_call(t.winid,vim.fn.winsaveview).topline}""")
        before = state()
        s.run("for i in range(100):\n    print('scroll row',i)\nprint('LIVE_'+'SCROLL_DONE')" if py else "for (i in 1:100) cat('scroll row',i,'\\n'); cat(paste0('LIVE_', 'SCROLL_DONE\\n'))",'LIVE_SCROLL_DONE')
        after = state()
        assert before['rows'] == after['rows'] and after['top'] > before['top'], (before, after)
        termwin = s.lua("return require('pyrola').term.winid")
        s.n.api.set_current_win(termwin)
        s.n.command('normal! gg')
        s.keys('<C-e>'); s.keys('<C-y>')
        assert state()['top'] < after['top']
        assert state()['rows'] == before['rows']
        s.screenshot('scrollback')
        s.n.api.set_current_win(s.source)
    s.check('inline plots remain anchored in real terminal scrollback', scrolling)

    def history():
        s.n.api.set_current_win(s.source)
        s.keys(' im')
        assert s.lua("return require('pyrola.image').manager_active")
        s.screenshot('image-history-initial')
        s.keys('h'); assert s.lua("return require('pyrola.image').history_index") == 1
        s.keys('h'); assert s.lua("return require('pyrola.image').history_index") == 1
        s.keys('l'); assert s.lua("return require('pyrola.image').history_index") == 2
        s.keys('l'); assert s.lua("return require('pyrola.image').history_index") == 2
        screenshot=s.screenshot('image-history')
        diagnostic=s.lua("""local i=require('pyrola.image'); local w=i.current_winid
            return {window=vim.api.nvim_win_get_config(w),view=vim.api.nvim_win_call(w,vim.fn.winsaveview),
            pixels=vim.api.nvim_get_hl(0,{name='PyrolaImagePixels',link=false}),
            lines=vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w),0,4,false)}""")
        (OUT/f'{s.language}-history-state.json').write_text(json.dumps(diagnostic,indent=2))
        s.assert_plot_pixels(screenshot,[(255,0,160)],(150,270,1290,700))
        for iteration in range(3):
            s.keys('h')
            s.assert_plot_pixels(s.screenshot(f'history-previous-{iteration}'),[(0,160,255)],(150,270,1290,700))
            s.keys('l')
            s.assert_plot_pixels(s.screenshot(f'history-next-{iteration}'),[(255,0,160)],(150,270,1290,700))
        s.keys('q')
        wait(lambda:not s.lua("return require('pyrola.image').manager_active"),'history q closes viewer')
        for method,index in [('show_last_image',2),('show_previous_image',1),('show_next_image',2)]:
            s.lua("require('pyrola')[...]()",method)
            assert s.lua("return require('pyrola.image').history_index") == index
        s.lua("local w=require('pyrola.image').current_winid; if w then vim.api.nvim_win_close(w,true) end")
        s.n.api.set_current_win(s.source)
        s.keys(' im'); s.keys('<Esc>')
        wait(lambda:not s.lua("return require('pyrola.image').manager_active"),'history Escape closes viewer')
    s.check('plot history h/l/boundaries/q/Escape and public image navigation', history)

    def restart():
        s.n.api.set_current_win(s.source)
        old = s.lua("return require('pyrola').term.chanid")
        s.lua("vim.fn.jobstop(require('pyrola').term.chanid)")
        wait(lambda: s.lua("return require('pyrola').status()") == 'kernel','terminal stopped')
        s.lua("require('pyrola').config.split_horizontal=true")
        s.n.command('Pyrola init'); s.ready()
        assert old != s.lua("return require('pyrola').term.chanid")
        s.run("print('LIVE_'+'REOPEN', answer)" if py else "cat(paste0('LIVE_', 'REOPEN '), answer, '\\n', sep='')",'LIVE_REOPEN 42')
        s.inspect('frame','Pandas DataFrame' if py else 'Data Frame')
    s.check('terminal close/reopen with horizontal split retains kernel values', restart)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--languages', nargs='+', choices=['python','r'], default=['python','r'])
    parser.add_argument('--desktop',action='store_true',help='Use the real desktop and CUA window screenshots')
    args = parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    for tool in ['Xvfb','kitty','nvim','ffmpeg']:
        assert shutil.which(tool), f'Missing {tool}'
    results=[]
    with tempfile.TemporaryDirectory(prefix='pyrola-live-') as tmp:
        temp=Path(tmp)
        init=temp/'init.lua'; init.write_text(INIT)
        read_fd,write_fd=os.pipe()
        with (OUT/'xvfb.log').open('w') as log:
            xvfb=subprocess.Popen(['Xvfb','-displayfd',str(write_fd),'-screen','0','1440x1000x24','-nolisten','tcp','-ac'],pass_fds=(write_fd,),stdout=log,stderr=log)
        os.close(write_fd)
        with os.fdopen(read_fd) as stream:
            display=':'+stream.readline().strip()
        if args.desktop:
            display=os.environ.get('DISPLAY',':0')
        try:
            for language in args.languages:
                env=dict(os.environ, DISPLAY=display, LIBGL_ALWAYS_SOFTWARE='1',
                         PYROLA_TEST_ROOT=str(ROOT),PYROLA_TEST_PYTHON=sys.executable,
                         JUPYTER_DATA_DIR=str(temp/'jupyter'),JUPYTER_RUNTIME_DIR=str(temp/'runtime'))
                env.pop('WAYLAND_DISPLAY',None)
                env.pop('VIRTUAL_ENV',None)
                if args.desktop:
                    env.pop('LIBGL_ALWAYS_SOFTWARE',None)
                # Use isolated Jupyter data, while preserving the installed R runtime.
                socket=str(temp/(language+'.sock'))
                source=temp/('live.'+('py' if language=='python' else 'R'))
                source.write_text('# Real '+language+' execution\n')
                command=['kitty','--config','NONE','--dump-bytes',str(OUT/(language+'-tui.ansi')),'--title','Pyrola real '+language+' tests']
                for opt in ['initial_window_width=1440','initial_window_height=1000','remember_window_size=no','font_size=12','enable_audio_bell=no','confirm_os_window_close=0','linux_display_server=x11']:
                    command+=['-o',opt]
                with (OUT/(language+'-kitty.log')).open('w') as log:
                    editor=subprocess.Popen(command+['nvim','-u',str(init),'-i','NONE','--listen',socket,str(source)],env=env,cwd=ROOT,stdout=log,stderr=log)
                n=None; s=None; connection=None
                try:
                    wait(lambda: Path(socket).exists(),'Neovim RPC socket')
                    n=pynvim.attach('socket',path=socket)
                    wait(lambda: n.eval("exists(':Pyrola')")==2,'Pyrola configuration')
                    n.current.buffer.options['filetype']=language
                    s=Session(n,language,display)
                    s.desktop=args.desktop
                    s.editor_pid=editor.pid
                    if args.desktop:
                        subprocess.run(['i3-msg',f'[title="Pyrola real {language} tests"] floating enable, resize set 1440 1000, move position center'],stdout=subprocess.DEVNULL,check=True)
                    s.lua('_G.live_source=vim.api.nvim_get_current_win()')
                    exercises(s)
                    connection=s.lua("return require('pyrola').connection_file_path")
                    s.dump()
                    n.command('qa!',async_=True)
                    editor.wait(timeout=15)
                    assert not Path(connection).exists(), 'Neovim exit left kernel connection file'
                    s.results.append({'name':'Neovim exit shuts down kernel and removes connection file','status':'PASS'})
                    status='PASS' if all(c['status']=='PASS' for c in s.results) else 'FAIL'
                    results.append({'language':language,'status':status,'checks':s.results})
                except Exception:
                    error=traceback.format_exc()
                    print(error,flush=True)
                    if s:
                        try: s.dump(); s.screenshot('failure')
                        except Exception: pass
                    results.append({'language':language,'status':'FAIL','checks':s.results if s else [],'error':error})
                finally:
                    if n:
                        try: n.command('qa!',async_=True); n.close()
                        except Exception: pass
                    if editor.poll() is None:
                        try: editor.wait(timeout=10)
                        except subprocess.TimeoutExpired: editor.terminate(); editor.wait(timeout=10)
                    (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n')
        finally:
            xvfb.terminate(); xvfb.wait(timeout=10)
    return 0 if all(r['status']=='PASS' for r in results) else 1


if __name__=='__main__':
    raise SystemExit(main())
