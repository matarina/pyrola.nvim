# nvim_ds_repl

`nvim_ds_repl` is a Neovim plugin designed to assist data scientists in executing Python and R code line by line. It utilizes sockets and multi-threading to interact with live Python/R server processes, providing a seamless real-time Read-Eval-Print Loop (REPL) experience.

## Features

- **Real-time REPL**: Execute code in real-time within Neovim.
- **Semantic Code Block Selection**: Select and send specific code blocks for evaluation.
- **Environment Variable Inspector**: Debug by inspecting environment variables.
- **Ligh

https://github.com/user-attachments/assets/bc9cd21a-9eba-49d2-855f-59954435e2ed

tweight and Low-level**: Efficiently designed to integrate seamlessly into your workflow.

## Installation
#### Prerequisites
    nvim-treesitter: Required for semantic code identification.
    IPython: Used for the Python REPL terminal.
    Radian: Used for the R REPL terminal.

You can install `nvim_ds_repl` using your preferred plugin manager. Here's an example with `lazy.nvim`:

```lua
return {
    "petrichorma/nvim_ds_repl",
    dependencies = {"nvim-treesitter/nvim-treesitter"},
    config = function()
        -- Configuration goes here
    end,
}
```



Additionally, you need to install the following Python and R tools:

```bash
pip install --user ipython
pip install --user radian
```

Key Bindings

Below are the recommended key bindings to use with nvim_ds_repl:


```lua
-- nvim_ds_repl plugin configuration --
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
    pattern = {"*.py", "*.R"},
    callback = function()
        -- Execute the current statement or block under the cursor
        vim.keymap.set("n", '<CR>', function() 
            require('nvim_ds_repl').send_statement_definition() 
        end, {noremap = true})

        -- Execute the selected visual block of code
        vim.keymap.set("v", '<CR>', function() 
            require('nvim_ds_repl').send_visual_to_repl() 
        end, {noremap = true})

        -- Query global environment variable information
        vim.keymap.set("n", '<leader>wi', function() 
            require('nvim_ds_repl').query_global() 
        end, {noremap = true})

        -- Query information about the specific object under the cursor
        vim.keymap.set("n", '<leader>si', function() 
            require('nvim_ds_repl').inspect() 
        end, {noremap = true})
    end
})
```






