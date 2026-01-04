<div align="center">

![Cool Text - Pyrola 475027950360735](https://github.com/user-attachments/assets/4d55bf4a-2a8c-402e-8c38-8038638e7bc4)

</div>

# Pyrola

`pyrola` is  crafted to deliver a multi-language supported REPL (Read-Eval-Print Loop) experience within the Neovim environment. This innovative tool empowers users to engage in interactive programming, enabling them to swiftly inspect variables in real-time and visualize output images seamlessly.
## DEMO

## Features
[![Watch the video](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=S3arFOPnD40)
- **Multi-language support**: Pyrola design based jupyter kernel, all language with jupyter kernel can be runned in pyrola.
- **Real-time REPL**: Execute code dynamically within Neovim, allowing for immediate feedback and interaction.
- **Semantic Code Block Selection**: Effortlessly select and dispatch specific code blocks for evaluation, enhancing the coding workflow.
- **Environment Variable Inspector**: Facilitate debugging by inspecting environment variables directly within the REPL.
- **Image Viewer**: Preview image outputs with a high or rough resolution, providing a quick visual reference without the need for external viewers.
- **Lightweight and Low-level**: Designed with efficiency in mind, `pyrola` integrates seamlessly into your existing workflow without unnecessary overhead.

## Installation

### 1) Python + Jupyter prerequisites

Pyrola talks to Jupyter kernels through Neovim's Python provider. Install the core Python deps first:

```bash
python3 -m pip install --user pynvim jupyter-client prompt-toolkit pillow pygments
```

Then install a Jupyter kernel for each language you want to use. For Python:

```bash
python3 -m pip install --user ipykernel
python3 -m ipykernel install --user --name python3
```

For other languages, install their Jupyter kernels and use the kernel name in `kernel_map`:

- R: `IRkernel::installspec()` (from R)
- C++: `xeus-cling` (kernel name varies by install)

### 2) Image preview helper (recommended)

Pyrola can render images inside the REPL. It uses [timg](https://github.com/hzeller/timg) for terminal previews. On Debian/Ubuntu:

```bash
apt install timg
```

Note for tmux: image hide/show on pane or window switches relies on focus events. Pyrola will try to enable tmux focus events for the current session. To configure it yourself, add `set -g focus-events on` to `~/.tmux.conf`, or disable the auto toggle with `image = { tmux_focus_events = false }` in `pyrola.setup`. If focus events are unreliable in your setup, enable the polling fallback with `image = { tmux_pane_poll = true, tmux_pane_poll_interval = 500 }`. For more precise square floats, tune the cell size mapping with `image = { cell_width = 10, cell_height = 20 }`, or allow tmux auto-detection (default) and disable it with `image = { tmux_cell_size = false }`.

### 3) Install the plugin (lazy.nvim)

Add Pyrola to your plugin manager and run `:UpdateRemotePlugins` once after install (or keep the build step below):

```lua
  {
    "matarina/pyrola.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    build = ":UpdateRemotePlugins",
    config = function()
        local pyrola = require("pyrola")
        pyrola.setup({
            kernel_map = {
                python = "python3",
                r = "ir",
                cpp = "xcpp14"
            },
            split_horizen = false,
            split_ratio = 0.3,
            send_buffer_key = "<leader>vb",
            image_manager_key = "<leader>im"
        })

        -- Key mappings
        vim.keymap.set("n", "<Enter>", function() pyrola.send_statement_definition() end, { noremap = true })
        vim.keymap.set("v", '<leader>vs', function() require('pyrola').send_visual_to_repl() end, { noremap = true})
        vim.keymap.set("n", "<leader>vb", function() pyrola.send_buffer_to_repl() end, { noremap = true })
        vim.keymap.set("n", "<leader>is", function() pyrola.inspect() end, { noremap = true })
    end,
  },

  -- SEPARATE Treesitter Configuration
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
        -- NOTE: The module name is now 'nvim-treesitter' (not .configs or .config)
        local ts = require("nvim-treesitter")

        ts.setup({
            -- In the new version, 'install_dir' is often required or defaults to site
            install_dir = vim.fn.stdpath('data') .. '/site'
        })

        -- NEW WAY to install parsers via Lua
        ts.install({  "r", "python", "lua", "vim", "vimdoc" })
    end
  }
```

Note: `send_buffer_key` and `image_manager_key` create default mappings during setup. If you keep those defaults, you can omit the manual mappings for those actions.

## Usage

### Start a REPL

1. Open a file with a filetype that exists in `kernel_map` (check with `:echo &filetype`).
2. Run `:Pyrola init` to start the kernel and open the REPL split.

If you change kernel names or add languages, update `kernel_map` in `pyrola.setup`.

### Send code

- Current statement/block: `pyrola.send_statement_definition()`
- Visual selection: `pyrola.send_visual_to_repl()`
- Whole buffer: `pyrola.send_buffer_to_repl()`

Treesitter improves block detection for `send_statement_definition()`. Install the parser for your language if block selection feels off.

### Inspect variables

Use `pyrola.inspect()` while your cursor is on a symbol. This currently supports Python and R (easy to extend).

### Image history manager

Press `<leader>im` (default) to open the image manager float. When the manager is focused:

- `h`: previous image
- `l`: next image
- `q`: close the window

### Key Bindings

Below are recommended key bindings. Adjust to taste:

```lua
-- nvim_ds_repl plugin configuration --
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
    pattern = {"*.py", "*.R"},
    callback = function()
        -- Execute the current statement or block under the cursor
        vim.keymap.set("n", '<CR>', function()
            require('pyrola').send_statement_definition()
        end, { noremap = true })

        -- Execute the selected visual block of code
        vim.keymap.set("v", '<leader>vs', function()
            require('pyrola').send_visual_to_repl()
        end, { noremap = true })

        -- Execute the whole buffer
        vim.keymap.set("n", '<leader>vb', function()
            require('pyrola').send_buffer_to_repl()
        end, { noremap = true })

        -- Query information about the specific object under the cursor
        vim.keymap.set("n", '<leader>is', function()
            require('pyrola').inspect()
        end, { noremap = true })

        -- Open image history manager
        vim.keymap.set("n", '<leader>im', function()
            require('pyrola.image').open_history_manager()
        end, { noremap = true })
    end
})
```

## Credit

- [Jupyter Team](https://github.com/jupyter/jupyter)
- [nvim-python-repl](https://github.com/geg2102/nvim-python-repl): `pyrola` draws inspiration from the foundational work of `nvim-python-repl`.

## Contributing

Contributions are  welcome ! `pyrola` is in its nascent stages and is actively maintained. Any reported issues will receive prompt attention. For enhanced image rendering capabilities, terminal graphic protocols such as Kitty or Sixel are not yet supported within the Neovim terminal buffer, as discussed in [this issue](https://github.com/neovim/neovim/issues/30889). Stay tuned for future developments and improvements!
