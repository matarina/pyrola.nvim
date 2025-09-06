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

Subsequently, you can install `pyrola` using `lazy.nvim` by incorporating the following configuration into your Neovim setup:

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
            split_horizen = false, -- Define the terminal split direction
            split_ratio = 0.3 -- Set the terminal split size
        })

        -- Define key mappings for enhanced functionality
        vim.keymap.set("n", "<Enter>", function()
            pyrola.send_statement_definition()
        end, { noremap = true })

        vim.keymap.set("v", '<leader>vs', function()
            require('pyrola').send_visual_to_repl()
        end, { noremap = true })

        vim.keymap.set("n", "<leader>is", function()
            pyrola.inspect()
        end, { noremap = true })

        -- Configure Treesitter for enhanced code parsing
        require("nvim-treesitter.configs").setup({
            ensure_installed = { "cpp", "r", "python" }, -- Ensure the necessary Treesitter language parsers are installed
            auto_install = true
        })
    end,
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

