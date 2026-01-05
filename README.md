
<div align="center">

</div><img width="2004" height="538" alt="logo" src="https://github.com/user-attachments/assets/f4e9d2f9-488a-4d02-9cea-a7ced4c44011" />

---

# Pyrola

If you are seeking an alternative to **Jupyter**, **Spyder**, or **RStudio** in Neovim, **Pyrola** is the solution.

Pyrola delivers a **multi-language REPL (Read–Eval–Print Loop)** experience inside **Neovim**. It is designed for interactive programming, especially for **data scientists**, and supports:

* Real-time code execution
* Variable inspection
* Image visualization

Since Pyrola is built on Jupyter kernels, **any language** with a Jupyter kernel can be integrated.

---

## DEMO VIDEO

<div align="center">
  <a href="https://www.youtube.com/watch?v=S3arFOPnD40">
    <img src="https://img.youtube.com/vi/S3arFOPnD40/0.jpg" alt="Watch the video" style="width:100%;">
  </a>
</div>

## Features

- **Multi-language support**: Pyrola is designed based on Jupyter kernels; any language with a Jupyter kernel can be shipped and used in Pyrola.
  ![recording_2026-01-04_07-36-08 - frame at 0m57s](https://github.com/user-attachments/assets/71d3ca3c-4f16-4567-b81c-c9d7e77383bc)

- **Real-time REPL**: Execute code dynamically within Neovim, allowing for immediate feedback and interaction.

- **Multiple Code Block Selection Methods**: You can send code via semantic code block identification (based on the Tree-sitter syntax parser), visual selection, or send the entire buffer to the REPL console with one click.

- **Environment Variable Inspector**: Facilitate debugging by inspecting environment variables and checking their attributes (class, type) directly within the REPL (currently only Python and R are supported).
 ![recording_2026-01-04_07-36-08 - frame at 0m52s](https://github.com/user-attachments/assets/c6668a17-da69-4ae5-ba88-841ec9f3f059)

- **Image Viewer**: Preview image outputs with high resolution (via the Kitty image protocol) or rough resolution (Unicode/ASCII based), providing a quick visual reference without the need for external viewers.
  ![recording_2026-01-04_07-36-08 - frame at 0m40s](https://github.com/user-attachments/assets/7ad7400c-f251-452b-879f-e9bd39d4f791)

- **History Image Viewer**: Stores historical images and allows browsing previously plotted images in a Neovim floating window.

## Installation

### 1) Default setup

Add Pyrola to your plugin manager. An example using `lazy.nvim` is provided below:

```lua
{
  "matarina/pyrola.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  build = ":UpdateRemotePlugins",
  config = function()
    local pyrola = require("pyrola")

    pyrola.setup({
      kernel_map = {
        python = "py3", -- Jupyter kernel name
        r = "ir",
      },
      split_horizen = false,
      split_ratio = 0.65, --width of splited REPL terminal
      image = {
        cell_width = 10, -- approximate terminal cell width in pixels
        cell_height = 20, -- approximate terminal cell height in pixels
        max_width_ratio = 0.5, -- image width as a fraction of editor columns
        max_height_ratio = 0.5, -- image height as a fraction of editor lines
        offset_row = 0, -- adjust image row position (cells)
        offset_col = 0, -- adjust image col position (cells)
      },
    })

    -- Default key mappings (adjust to taste)

    -- Send semantic code block under cursor
    vim.keymap.set("n", "<CR>", function()
      pyrola.send_statement_definition()
    end, { noremap = true })

    -- Send visual selection
    vim.keymap.set("v", "<leader>vs", function()
      pyrola.send_visual_to_repl()
    end, { noremap = true })

    -- Send entire buffer
    vim.keymap.set("n", "<leader>vb", function()
      pyrola.send_buffer_to_repl()
    end, { noremap = true })

    -- Inspect variable under cursor
    vim.keymap.set("n", "<leader>is", function()
      pyrola.inspect()
    end, { noremap = true })

    -- Open history image viewer
    vim.keymap.set("n", "<leader>im", function()
      pyrola.open_history_manager()
    end, { noremap = true })
  end,
},

-- Tree-sitter is required.
-- Parsers for languages listed in `kernel_map` must be installed.
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local ts = require("nvim-treesitter")

    ts.setup({
      install_dir = vim.fn.stdpath("data") .. "/site",
    })

    -- Install required parsers
    ts.install({ "python", "r", "lua" })
  end,
}

```

Highlight groups are theme-aware by default (linked to `FloatBorder`, `FloatTitle`, and `NormalFloat`). Override them if you want custom colors:

```lua
vim.api.nvim_set_hl(0, "PyrolaInspectorBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyrolaInspectorTitle", { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyrolaInspectorNormal", { link = "NormalFloat" })
vim.api.nvim_set_hl(0, "PyrolaImageBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyrolaImageTitle", { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyrolaImageNormal", { link = "NormalFloat" })
```

### 2) Python + Pip in PATH

Pyrola is built on `pynvim`, so ensure `python` and `pip` are available in your PATH. Virtual environments (like Conda) are highly recommended.

after setting up your `init.lua` and then activate a Conda environment,  Pyrola will automatically prompt you to install the related Python dependencies when first time run 'Pyrola init',. Alternatively, you can install them manually:

```bash
python3 -m pip install pynvim jupyter-client prompt-toolkit pillow pygments

```

Then, install a Jupyter kernel for each language you want to use.

**Python Example:**

```bash
python3 -m pip install ipykernel
python3 -m ipykernel install --user --name py3
# Note: The name "py3" must be identical to the name used in 'kernel_map' in your Lua config.

```

For other languages, install their Jupyter kernels and use the kernel name in `kernel_map`:

* **R**: `IRkernel::installspec()` (run from R)
* **C++**: `xeus-cling` (kernel name varies by installation)

### 3) Image Preview Helper (Recommended)

Pyrola can render images inside the REPL.

* For **high-quality image viewing**, the [Kitty terminal](https://sw.kovidgoyal.net/kitty/) is necessary.
* For **embedded pixel image viewing** in the REPL console, [timg](https://github.com/hzeller/timg) is required.

On Debian/Ubuntu:

```bash
apt install timg

```

**Note for tmux:**
Image hiding/showing on pane or window switches relies on focus events. to enable tmux focus events for the current session.  configure  the following to your `~/.tmux.conf`:

```tmux
set -g focus-events on
set -g allow-passthrough all

```

## Usage

### Start a REPL

1. Open a file whose `filetype` exists in your `kernel_map`.
```vim
:echo &filetype

```


2. Start the kernel and REPL:
```vim
:Pyrola init

```



### Send Code

* **Current semantic block**:
```lua
pyrola.send_statement_definition()

```


* **Visual selection**:
```lua
pyrola.send_visual_to_repl()

```


* **Whole buffer**:
```lua
pyrola.send_buffer_to_repl()

```



### Inspect Variables

Place the cursor on a symbol and run:

```lua
pyrola.inspect()

```
Currently, Python and R are supported. This is easy to extend, and contributions are welcome!


### Image History Manager

Press `<leader>im` (or your configured key) to open the image manager.

When focused:

* `h` — Previous image
* `l` — Next image
* `q` — Close

## Credits

* [Jupyter Team](https://github.com/jupyter/jupyter)
* [nvim-python-repl](https://github.com/geg2102/nvim-python-repl) — Pyrola draws inspiration from this project.

## Contributing

Contributions are welcome! Pyrola is in its early stages and actively maintained. Issues and pull requests will receive prompt attention.

**Note:** For enhanced image rendering, terminal graphic protocols such as **Sixel** are not yet supported inside Neovim terminal buffers due to upstream limitations (see [Neovim Issue #30889](https://github.com/neovim/neovim/issues/30889)).

Stay tuned for future improvements! 🚀
