# Pyrola

`pyrola` is designed to provide a multi-language supported REPL experience in Neovim. It allows you to program interactively, quickly inspect variables in real-time, and view images of output.

## Features

- **Real-time REPL**: Execute code in real-time within Neovim.
- **Semantic Code Block Selection**: Select and send specific code blocks for evaluation.
- **Environment Variable Inspector**: Debug by inspecting environment variables.
- **Rough Image Viewer**: Preview output of images with a rough resolution.
- **Lightweight and Low-level**: Efficiently designed to integrate seamlessly into your workflow.

## Installation

### Prerequisites

To use `pyrola`, you need to install the following Python packages:

```bash
pip install pynvim jupyter-client prompt-toolkit
```

Additionally, you will need to install [timg](https://github.com/hzeller/timg), a textual terminal image viewer. For example, on Debian-based systems, you can install it using:

```bash
apt install timg
```

Then, install `pyrola` using `lazy.nvim` as follows:

```lua
return {
    "matarina/pyrola.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    build = ":UpdateRemotePlugins",
    config = function(_, opts)
        local pyrola = require("pyrola")
        pyrola.setup({
            kernel_map = { -- Map Jupyter kernel names to Neovim filetypes
                python = "python3",
                r = "ir",
                cpp = "xcpp14"
            },
            split_horizen = false, -- Split terminal direction
            split_ratio = 0.3 -- Split terminal size
        })

        -- Set key mappings
        vim.keymap.set("n", "<Enter>", function()
            pyrola.send_statement_definition()
        end, { noremap = true })

        vim.keymap.set("v", '<leader>vs', function()
            require('pyrola').send_visual_to_repl()
        end, { noremap = true })

        vim.keymap.set("n", "<leader>is", function()
            pyrola.inspect()
        end, { noremap = true })

        -- Treesitter configuration
        require("nvim-treesitter.configs").setup({
            ensure_installed = { "cpp", "r", "python" }, -- Ensure installed Treesitter language parsers
            auto_install = true
        })
    end,
}
```

## Usage

`pyrola` is developed based on communication between the Jupyter kernel and client. Any language listed with a Jupyter kernel can theoretically be supported. For example, to run a Python REPL environment with `pyrola`, you need to install the Python Jupyter kernel, e.g., `ipykernel`. For your specific language and kernel, you should explicitly specify it in the `kernel_map` options, e.g., `{ kernel_map = { python = "python3" } }`. The index corresponds to your filetype, which can be checked with the command: `echo &filetype`. The values are your kernel names.

You can also configure the split terminal direction and size using the options `split_horizen` and `split_ratio`. For semantic code parsing and sending to the terminal, the Treesitter language parser is necessary. You need to install the parser in your Treesitter Lua configuration if you do not want to specify it explicitly in the `pyrola` Lua config.

For sending large code blocks, visual selection is available, allowing you to bind keys to send code selected in visual mode to the terminal. To inspect variables, bind keys to `pyrola.inspect()`, and trigger it when the cursor is on the variables you want to inspect. This feature currently supports Python and R, with plans to add more languages in the future. Contributions to add variable inspectors for your preferred languages are welcome!

### Key Bindings

Below are the recommended key bindings to use with `pyrola`:

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

        -- Query information about the specific object under the cursor
        vim.keymap.set("n", '<leader>is', function()
            require('pyrola').inspect()
        end, { noremap = true })
    end
})
```

## Credit

- [Jupyter Team](https://github.com/jupyter/jupyter)
- [nvim-python-repl](https://github.com/geg2102/nvim-python-repl): `pyrola` is inspired by `nvim-python-repl` from the very beginning.

## Contributing

Contributions are welcome! `pyrola` is newly born and highly actively maintained. Any issues will receive a real-time response. For higher quality image rendering, terminal graphic protocols like Kitty or Sixel are not currently supported in the Neovim terminal buffer, as discussed in [this issue](https://github.com/neovim/neovim/issues/30889). Keep an eye on any progress in the future!


