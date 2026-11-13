# Recording the feature demos

The four GIFs in this directory are recordings of real Neovim/Kitty sessions
using a live Python/Jupyter kernel. FFmpeg captures the terminal pixels so Kitty
bitmap plots appear in the GIFs as they do on screen. No output is mocked.

On Linux, install:

- `nvim` 0.12 or newer, `kitty` 0.28 or newer, `Xvfb`, and `ffmpeg`.
- A Python Tree-sitter parser in Neovim's runtime path (for example, install
  `python` through `nvim-treesitter` in your normal Neovim setup).
- The plugin's Python requirements plus `ipykernel`, `numpy`, and `matplotlib`,
  installed in the Python environment used to run the recorder.
- A `python3` Jupyter kernel using that environment. To register it, run
  `python3 -m ipykernel install --user --name python3`.

From the repository root, run:

```sh
python3 examples/record-demos.py
```

To refresh just one clip, add `--only plots-and-history` (or another GIF's name
without the `.gif` extension).

The recorder uses `examples/recording-init.lua` and a separate Xvfb display.
It sends the documented mappings through Neovim's input API, waits for real
kernel output, and verifies the results before saving each GIF. Each demo gets
a fresh editor and kernel. The user's desktop and Neovim config are unchanged.

The output is four looping 1280 × 800 GIFs at 10 frames per second. Temporary
lossless videos, Python examples, logs, and `verification.json` are kept under
the ignored `artifacts/readme-recordings/` directory. Review the resulting GIFs
before committing them.
