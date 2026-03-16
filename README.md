
<div align="center">

</div><img width="2004" height="538" alt="logo" src="https://github.com/user-attachments/assets/f4e9d2f9-488a-4d02-9cea-a7ced4c44011" />

---

# Pyrola

If you are seeking an alternative to **Jupyter**, **Spyder**, or **RStudio** in Neovim, **Pyrola** is the solution.

Pyrola delivers a **multi-language REPL (Read-Eval-Print Loop)** experience inside **Neovim**. It is designed for interactive programming, especially for **data scientists**, and supports:

* Real-time code execution
* Variable inspection
* Image visualization

Since Pyrola is built on Jupyter kernels, **any language** with a Jupyter kernel can be integrated.

---

## Demo

<div align="center">
  <a href="https://www.youtube.com/watch?v=S3arFOPnD40">
    <img src="https://img.youtube.com/vi/S3arFOPnD40/0.jpg" alt="Watch the video" style="width:100%;">
  </a>
</div>

## Features

- **Multi-language support**: Any language with a Jupyter kernel works in Pyrola (Python, R, C++, Julia, etc.).
  ![recording_2026-01-04_07-36-08 - frame at 0m57s](https://github.com/user-attachments/assets/71d3ca3c-4f16-4567-b81c-c9d7e77383bc)

- **Real-time REPL**: Execute code dynamically within Neovim with immediate feedback.

- **Multiple code-sending methods**: Send code via Tree-sitter semantic blocks, visual selection, or entire buffer.

- **Variable inspector**: Inspect variables (class, type, shape, content) directly from the REPL (Python and R).
 ![recording_2026-01-04_07-36-08 - frame at 0m52s](https://github.com/user-attachments/assets/c6668a17-da69-4ae5-ba88-841ec9f3f059)

- **Global variable browser**: View all user globals in a floating window. Press `<CR>` on any variable to inspect it.

- **Image viewer**: Preview image outputs in a floating window via Kitty or iTerm2 terminal protocols.
  ![recording_2026-01-04_07-36-08 - frame at 0m40s](https://github.com/user-attachments/assets/7ad7400c-f251-452b-879f-e9bd39d4f791)

- **Image history**: Browse previously plotted images in a floating window.

- **Reliable interrupts**: Interrupt long-running cells and recover cleanly.

- **One-command setup**: `:Pyrola setup` installs dependencies, ipykernel, and registers your kernel automatically.

- **Auto kernel registration**: When a kernel is missing, Pyrola offers to install and register it for Python filetypes.

---

## Installation

### 1. Plugin setup

Add Pyrola to your plugin manager. Example using `lazy.nvim`:

```lua
{
  "matarina/pyrola.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    local pyrola = require("pyrola")

    pyrola.setup({
      -- Optional: point to a specific Python (conda/venv).
      -- If omitted, uses g:python3_host_prog or "python3".
      -- python_path = "~/miniconda3/envs/ds/bin/python",

      kernel_map = {
        python = "py3", -- Jupyter kernel name for Python files
        r = "ir",       -- Jupyter kernel name for R files
      },
      split_horizontal = false,
      split_ratio = 0.65,
      image = {
        cell_width = 10,
        cell_height = 20,
        max_width_ratio = 0.5,
        max_height_ratio = 0.5,
        offset_row = 0,
        offset_col = 0,
        protocol = "auto", -- auto | kitty | iterm2 | none
      },
    })

    -- Keybindings
    vim.keymap.set("n", "<CR>", pyrola.send_statement_definition, { noremap = true })
    vim.keymap.set("v", "<leader>vs", pyrola.send_visual_to_repl, { noremap = true })
    vim.keymap.set("n", "<leader>vb", pyrola.send_buffer_to_repl, { noremap = true })
    vim.keymap.set("n", "<leader>is", pyrola.inspect, { noremap = true })
    vim.keymap.set("n", "<leader>ig", pyrola.show_globals, { noremap = true })
    vim.keymap.set("n", "<leader>ik", pyrola.interrupt_kernel, { noremap = true })
    vim.keymap.set("n", "<leader>im", pyrola.open_history_manager, { noremap = true })
  end,
},

-- Tree-sitter is required. Install parsers for languages in kernel_map.
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local ts = require("nvim-treesitter")
    ts.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })
    ts.install({ "python", "r", "lua" })
  end,
}
```

### 2. Python environment setup

Pyrola needs a few Python packages. There are three ways to set them up:

#### Option A: One-command setup (recommended)

Open a file whose filetype is in your `kernel_map` and run:

```vim
:Pyrola setup
```

This installs all dependencies via pip. For Python filetypes, it also installs `ipykernel` and registers the kernel matching your `kernel_map`. When finished, run `:Pyrola init` to start.

#### Option B: Manual install

```bash
pip install -r /path/to/pyrola.nvim/rplugin/python3/requirements.txt
pip install ipykernel
python3 -m ipykernel install --user --name py3
```

The kernel name (`py3` above) **must match** the name in your `kernel_map` config.

#### Option C: Auto-prompted install

When you run `:Pyrola init` with missing packages, Pyrola prompts you to install them. If the kernel is missing for a Python file, it offers to install and register it.

### 3. Conda / venv users

Set `python_path` in your config so Pyrola uses the correct interpreter:

```lua
pyrola.setup({
    python_path = "~/miniconda3/envs/ds/bin/python",
    kernel_map = { python = "py3" },
})
```

This takes precedence over `g:python3_host_prog` and the system `python3`.

### 4. Non-Python kernels

Install the appropriate Jupyter kernel and add it to `kernel_map`:

| Language | Kernel install | kernel_map name |
|----------|---------------|-----------------|
| **R** | `IRkernel::installspec()` (run from R) | `ir` |
| **C++** | Install `xeus-cling` | `xcpp17` |
| **Julia** | `using IJulia` (run from Julia) | `julia-1.x` |

### 5. Image preview (optional)

Pyrola renders images in floating windows via **Kitty** or **iTerm2** terminal protocols (`image.protocol = "auto"` detects automatically).

For **embedded pixel images** in the REPL console output, install [timg](https://github.com/hzeller/timg):

```bash
# Debian/Ubuntu
apt install timg

# macOS
brew install timg
```

**tmux users:** Add to `~/.tmux.conf`:

```tmux
set -g focus-events on
set -g allow-passthrough all
```

---

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Pyrola setup` | Install dependencies + register kernel (one-time) |
| `:Pyrola init` | Start kernel and open REPL terminal |

Both commands support tab completion.

### Sending code

| Function | Description |
|----------|-------------|
| `pyrola.send_statement_definition()` | Send the Tree-sitter semantic block under cursor. When REPL is not running, falls back to normal `<CR>`. |
| `pyrola.send_visual_to_repl()` | Send visual selection to REPL. Exits visual mode and moves cursor to next code line. |
| `pyrola.send_buffer_to_repl()` | Send the entire buffer to REPL. |

### Inspecting variables

| Function | Description |
|----------|-------------|
| `pyrola.inspect()` | Inspect the symbol under cursor in a floating window. Uses Tree-sitter to identify the symbol, falls back to `<cword>`. Shows type, shape, content, methods, etc. Supports Python and R. |
| `pyrola.show_globals()` | Show all user variables in a floating window. Press `<CR>` on any entry to inspect it. Press `q` or `<Esc>` to close. |

### Kernel control

| Function | Description |
|----------|-------------|
| `pyrola.interrupt_kernel()` | Send SIGINT to interrupt the running kernel execution. |

### Image history

| Function | Description |
|----------|-------------|
| `pyrola.open_history_manager()` | Open image history browser. Use `h`/`l` to navigate, `q` to close. |
| `pyrola.show_last_image()` | Show the most recent image in a floating window. |
| `pyrola.show_previous_image()` | Navigate to the previous image in history. |
| `pyrola.show_next_image()` | Navigate to the next image in history. |

---

## Configuration reference

```lua
pyrola.setup({
    -- Python interpreter path. Supports ~ expansion.
    -- Priority: python_path > g:python3_host_prog > "python3"
    python_path = nil,

    -- Map Neovim filetypes to Jupyter kernel names.
    -- The kernel name must match what's registered with `jupyter kernelspec list`.
    kernel_map = {
        python = "python3",
        r = "ir",
        cpp = "xcpp17",
    },

    -- REPL terminal split direction and size.
    split_horizontal = false,  -- false = vertical split (right), true = horizontal (bottom)
    split_ratio = 0.65,        -- fraction of editor width/height for the split

    -- Image display settings.
    image = {
        cell_width = 10,        -- terminal cell width in pixels (for size calculations)
        cell_height = 20,       -- terminal cell height in pixels
        max_width_ratio = 0.5,  -- max image width as fraction of editor columns
        max_height_ratio = 0.5, -- max image height as fraction of editor lines
        offset_row = 0,         -- adjust image row position (cells)
        offset_col = 0,         -- adjust image col position (cells)
        protocol = "auto",      -- "auto" | "kitty" | "iterm2" | "none"
    },
})
```

---

## Highlight groups

Floating windows use theme-aware defaults (linked to `FloatBorder`, `FloatTitle`, `NormalFloat`). Highlight groups are automatically refreshed when you change colorscheme. Override them for custom colors:

```lua
-- Inspector window
vim.api.nvim_set_hl(0, "PyrolaInspectorBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyrolaInspectorTitle",  { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyrolaInspectorNormal", { link = "NormalFloat" })

-- Image window
vim.api.nvim_set_hl(0, "PyrolaImageBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyrolaImageTitle",  { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyrolaImageNormal", { link = "NormalFloat" })

-- Globals window
vim.api.nvim_set_hl(0, "PyrolaGlobalsBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyrolaGlobalsTitle",  { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyrolaGlobalsNormal", { link = "NormalFloat" })
```

---

## Troubleshooting

### `:Pyrola init` says "No such kernel"

Your `kernel_map` name doesn't match any installed kernel. Check installed kernels:

```bash
jupyter kernelspec list
```

For Python, register a kernel:

```bash
python3 -m ipykernel install --user --name py3
```

Or just run `:Pyrola setup` in a Python buffer — it does this automatically.

### `:Pyrola init` says "python3 executable not found"

Set `python_path` in your config or `g:python3_host_prog` to a valid Python 3 path:

```lua
pyrola.setup({ python_path = "/usr/bin/python3" })
```

### Images don't display

1. Check your terminal supports Kitty or iTerm2 image protocols.
2. For inline REPL images, install `timg`: `apt install timg` or `brew install timg`.
3. In tmux, ensure `allow-passthrough all` and `focus-events on` are set.

### REPL is unresponsive

Use `pyrola.interrupt_kernel()` to send SIGINT. If the kernel is fully hung, restart with `:Pyrola init`.

---

## TODO

- [ ] **Multi-language variable inspector**: Extend inspection beyond Python and R.

## Credits

* [Jupyter Team](https://github.com/jupyter/jupyter)
* [nvim-python-repl](https://github.com/geg2102/nvim-python-repl) — Pyrola draws inspiration from this project.

## Contributing

Contributions are welcome! Issues and pull requests will receive prompt attention.

**Note:** Terminal graphic protocols such as **Sixel** are not yet supported inside Neovim terminal buffers due to upstream limitations (see [Neovim Issue #30889](https://github.com/neovim/neovim/issues/30889)).
