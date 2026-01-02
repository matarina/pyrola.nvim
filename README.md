<div align="center">

![Cool Text - Pyrola 475027950360735](https://github.com/user-attachments/assets/4d55bf4a-2a8c-402e-8c38-8038638e7bc4)

</div>

# Pyrola

`pyrola` is  crafted to deliver a multi-language supported REPL (Read-Eval-Print Loop) experience within the Neovim environment. This innovative tool empowers users to engage in interactive programming, enabling them to swiftly inspect variables in real-time and visualize output images seamlessly.
## DEMO
![vlcsnap-2025-01-30-06h11m40s788](https://github.com/user-attachments/assets/fcfb2b7b-637e-43af-9af2-c814431a0ee3)

https://youtu.be/ugyOw3Hop08
## Features

- **Multi-language support**: Pyrola design based jupyter kernel, all language with jupyter kernel can be runned in pyrola.
- **Real-time REPL**: Execute code dynamically within Neovim, allowing for immediate feedback and interaction.
- **Semantic Code Block Selection**: Effortlessly select and dispatch specific code blocks for evaluation, enhancing the coding workflow.
- **Environment Variable Inspector**: Facilitate debugging by inspecting environment variables directly within the REPL.
- **Image Viewer**: Preview image outputs with a high or rough resolution, providing a quick visual reference without the need for external viewers.
- **Lightweight and Low-level**: Designed with efficiency in mind, `pyrola` integrates seamlessly into your existing workflow without unnecessary overhead.

## Installation

### Prerequisites

To harness the full potential of `pyrola`, you must first install the following essential Python packages:

```bash
pip install pynvim jupyter-client prompt-toolkit pillow pygments
```
For image viewer, high quality image preview are based kitty graphic protocol,a  rough pixelized resolution image in console can be available for all terminal.
In addition, you will need to install [timg](https://github.com/hzeller/timg), a terminal-based image viewer. For users on Debian-based systems, the installation can be accomplished with the following command:

```bash
apt install timg
```

Note for tmux: image hide/show on pane or window switches relies on focus events. Pyrola will try to enable tmux focus events for the current session. To configure it yourself, add `set -g focus-events on` to `~/.tmux.conf`, or disable the auto toggle with `image = { tmux_focus_events = false }` in `pyrola.setup`. If focus events are unreliable in your setup, enable the polling fallback with `image = { tmux_pane_poll = true, tmux_pane_poll_interval = 500 }`. For more precise square floats, tune the cell size mapping with `image = { cell_width = 10, cell_height = 20 }`, or allow tmux auto-detection (default) and disable it with `image = { tmux_cell_size = false }`.

Subsequently, you can install `pyrola` using `lazy.nvim` by incorporating the following configuration into your Neovim setup:

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
            send_buffer_key = "<leader>vb"
        })

        -- Key mappings
        vim.keymap.set("n", "<Enter>", function() pyrola.send_statement_definition() end, { noremap = true })
        vim.keymap.set("v", '<leader>vs', function() require('pyrola').send_visual_to_repl() end, { noremap = true})
        vim.keymap.set("n", "<leader>vb", function() pyrola.send_buffer_to_repl() end, { noremap = true })
        vim.keymap.set("n", "<leader>is", function() pyrola.inspect() end, { noremap = true })

        -- Image history keybindings
        vim.keymap.set("n", "<leader>i", function() pyrola.show_last_image() end, { noremap = true, desc = "Show last image" })
        vim.keymap.set("n", "<leader>h", function() pyrola.show_previous_image() end, { noremap = true, desc = "Previous image" })
        vim.keymap.set("n", "<leader>l", function() pyrola.show_next_image() end, { noremap = true, desc = "Next image" })
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

## Usage

`pyrola` operates on the principle of communication between the Jupyter kernel and the client, allowing for a versatile programming experience across various languages. To initiate a Python REPL environment with `pyrola`, you must install the Python Jupyter kernel, such as `ipykernel`. For your specific programming language and kernel, it is crucial to explicitly define it in the `kernel_map` options, for instance, `{ kernel_map = { python = "python3" } }`. The index corresponds to your filetype, which can be verified using the command: `echo &filetype`. The values represent your kernel names.

You can also customize the terminal split direction and size through the options `split_horizen` and `split_ratio`. For semantic code parsing and dispatching to the terminal, the Treesitter language parser is essential. Ensure that the parser is installed in your Treesitter Lua configuration if you prefer not to specify it explicitly in the `pyrola` Lua configuration.

For sending larger code blocks, visual selection is available, allowing you to bind keys to transmit code selected in visual mode to the terminal. To inspect variables, you can bind keys to `pyrola.inspect()`, triggering it when the cursor hovers over the variables you wish to examine. This feature currently supports Python and R, with aspirations to expand support for additional languages in the future. Contributions to enhance variable inspection for your preferred languages are warmly welcomed!

### Key Bindings

Below are the recommended key bindings to optimize your experience with `pyrola`:

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
    end
})
```

## Credit

- [Jupyter Team](https://github.com/jupyter/jupyter)
- [nvim-python-repl](https://github.com/geg2102/nvim-python-repl): `pyrola` draws inspiration from the foundational work of `nvim-python-repl`.

## Contributing

Contributions are  welcome ! `pyrola` is in its nascent stages and is actively maintained. Any reported issues will receive prompt attention. For enhanced image rendering capabilities, terminal graphic protocols such as Kitty or Sixel are not yet supported within the Neovim terminal buffer, as discussed in [this issue](https://github.com/neovim/neovim/issues/30889). Stay tuned for future developments and improvements!
