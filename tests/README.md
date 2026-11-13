# Testing Pyrola

Run the existing Python and headless Neovim regression checks with:

```sh
./tests/run.sh
```

Run the live application checks with:

```sh
.venv/bin/python -m pip install -r rplugin/python3/requirements.txt ipykernel numpy pandas matplotlib
.venv/bin/python tests/real_execution.py --languages python r
```

The live suite starts actual Kitty windows and Neovim/Jupyter processes on its
own Xvfb display. It sends real keypresses through Neovim's input API and real
code through Pyrola's REPL. It does not replace the terminal, graphics protocol,
kernel, inspector, or Pyrola functions with mocks. Results, logs, original plot
PNGs and screenshots go in `artifacts/real-execution/`.

Prerequisites: Kitty, Neovim 0.12+, Xvfb, ffmpeg, and a Python Tree-sitter parser
on Neovim's runtime path. For R, install R, IRkernel, and ggplot2; expose R on
PATH, or register an `ir` kernelspec. The suite exercises `:Pyrola setup` and
registers its managed kernels in a temporary Jupyter data directory. It uses
the supplied Python environment for dependencies.

Coverage includes setup/init, repeated init, statements/functions, visual
selection, whole buffers, submission order, direct and multiline REPL input,
history, stdout/stderr/Unicode, Python/R inspection, globals drill-down, error
recovery, kernel stdin, prompt restoration, interrupts, busy status, real PNG
plots, inline scrollback, image-history keys and public navigation methods,
terminal reconnection, horizontal splits, and shutdown cleanup. The image
checks verify the distinct curve colors in captured Kitty windows for both
inline plots and repeated history navigation. These pixel checks include
transparent base R graphics and ggplot2 output.

Use `--languages python` or `--languages r` for one language. C++/Julia kernels,
iTerm2, tmux, optional tensor libraries and Neovim 0.11 are not exercised by
this live suite.

On this Linux/i3 desktop, `--desktop` uses the real display with CUA window
captures instead of Xvfb screenshots. This requires `cua-driver` and `i3-msg`.
It opens temporary test windows and closes them when finished. Use this mode
to verify graphics against the desktop renderer as well as software rendering.
