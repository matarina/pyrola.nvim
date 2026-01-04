<div align="center">




</div><img width="2004" height="538" alt="logo" src="https://github.com/user-attachments/assets/f4e9d2f9-488a-4d02-9cea-a7ced4c44011" />


# Pyrola

If you are seeking an alternative to Jupyter, Spyder, or RStudio, Pyrola is the solution. Designed to deliver a multi-language REPL (Read-Eval-Print Loop) experience within Neovim, this tool helps users—particularly data scientists—excel at interactive programming. It enables real-time variable inspection and image visualization. Since it is based on Jupyter, in theory, any language with a Jupyter kernel can be integrated into Pyrola.

## DEMO
<div align="center">
  <a href="https://www.youtube.com/watch?v=S3arFOPnD40">
    <img src="https://img.youtube.com/vi/S3arFOPnD40/0.jpg" alt="Watch the video" style="width:100%;">
  </a>
</div>

## Features
[![Watch the video](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=S3arFOPnD40)
- **Multi-language support**: Pyrola design based jupyter kernel, all language with jupyter kernel can be shiped  in pyrola.
- **Real-time REPL**: Execute code dynamically within Neovim, allowing for immediate feedback and interaction.
- **multi  Code Block Selection method **: you can sending code by  semantic code block identficatin based treesitter syntax parser , or visual selction and whole buffer one click to repl console .
- **Environment Variable Inspector**: Facilitate debugging by inspecting environment variables, check its atttibution (class, type) directly within the REPL.(currently only python and R supported )
- **Image Viewer**: Preview image outputs with a high (kitty image protoal based ) or rough (unicode/ascii based)resolution, providing a quick visual reference without the need for external viewers.
- **history image viewer**: stored history image and browse hisotry plotted iamge in neovim float window 

## Installation

### 1) default setup 

Add Pyrola to your plugin manager ,lazy example below :

```lua
  {
    "matarina/pyrola.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    build = ":UpdateRemotePlugins",
    config = function()
        local pyrola = require("pyrola")
        pyrola.setup({
            kernel_map = {
                python = "py3", --jupyter kenrel  name 
                r = "ir"
 
            },
            split_horizen = false,
            split_ratio = 0.3,
            send_buffer_key = "<leader>vb",
            image_manager_key = "<leader>im"
        })

        -- Default Key mappings, Adjust to taste:
-- semantic code blcok sending based current cursor position
        vim.keymap.set("n", "<Enter>", function() pyrola.send_statement_definition() end, { noremap = true })
-- visual selection  code blcok sending based selection region .
        vim.keymap.set("v", '<leader>vs', function() require('pyrola').send_visual_to_repl() end, { noremap = true})
-- whole buffer   code blcok sending 
        vim.keymap.set("n", "<leader>vb", function() pyrola.send_buffer_to_repl() end, { noremap = true })
 -- whole buffer  sending 
        vim.keymap.set("n", "<leader>is", function() pyrola.inspect() end, { noremap = true })
 -- history image viewer 
        vim.keymap.set("n", '<leader>im', function()  pyrola.open_history_manager() end, { noremap = true })
    end,
  },

  -- Treesitter is necessary , and the language parser specified in  kernel_map should be ensure  installed . 
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
        ts.install({  "r", "python", "lua"}) -- PYthon and R is necessary as metioned in pyrola setup
    end
  }
```

### 2) python + pip in path 

Pyrola is developed base pynvim , so make sure python  and pip is availabel in path. vritual env list conda is highly recommand. for conda exampel ,setup init lua and then  activate conda env  , will automatly prompt you to install related  dependencies python packages
 or you can install them manually
```bash
python3 -m pip install --user pynvim jupyter-client prompt-toolkit pillow pygments
```

Then install a Jupyter kernel for each language you want to use.
 For Python example:

```bash
python3 -m pip install --user ipykernel
python3 -m ipykernel install --user --name py3 # name "py3" must Identical to the name in kernel_map
```

For other languages, install their Jupyter kernels and use the kernel name in `kernel_map`:

- R: `IRkernel::installspec()` (from R)
- C++: `xeus-cling` (kernel name varies by install)

### 2) Image preview helper (recommended)

Pyrola can render images inside the REPL. for high quality image view, kitty terminal is necessary . for repl console membeded pixel iamge view, [timg](https://github.com/hzeller/timg) is necessasry . On Debian/Ubuntu:

```bash
apt install timg
```

Note for tmux: image hide/show on pane or window switches relies on focus events. Pyrola will try to enable tmux focus events for the current session. To configure it yourself, add `set -g focus-events on` to `~/.tmux.conf`, or disable the auto toggle with `image = { tmux_focus_events = false }` in `pyrola.setup`. If focus events are unreliable in your setup, enable the polling fallback with `image = { tmux_pane_poll = true, tmux_pane_poll_interval = 500 }`. For more precise square floats, tune the cell size mapping with `image = { cell_width = 10, cell_height = 20 }`, or allow tmux auto-detection (default) and disable it with `image = { tmux_cell_size = false }`.




## Usage

### Start a REPL

1. Open a file with a filetype that exists in `kernel_map` (check with `:echo &filetype`).
2. Run `:Pyrola init` to start the kernel and open the REPL split.

If you change kernel names or add languages, update `kernel_map` in `pyrola.setup`.

### Send code

- Current statement/block: `pyrola.send_statement_definition()`
- Visual selection: `pyrola.send_visual_to_repl()`
- Whole buffer: `pyrola.send_buffer_to_repl()`


### Inspect variables

Use `pyrola.inspect()` while your cursor is on a symbol. This currently supports Python and R (easy to extend by yourself , contribution welcome!).

### Image history manager

Press `<leader>im` (default) to open the image manager float. When the manager is focused:

- `h`: previous image
- `l`: next image
- `q`: close the window



## Credit

- [Jupyter Team](https://github.com/jupyter/jupyter)
- [nvim-python-repl](https://github.com/geg2102/nvim-python-repl): `pyrola` draws inspiration from the foundational work of `nvim-python-repl`.

## Contributing

Contributions are  welcome ! `pyrola` is in its nascent stages and is actively maintained. Any reported issues will receive prompt attention. For enhanced image rendering capabilities, terminal graphic protocols such as Kitty or Sixel are not yet supported within the Neovim terminal buffer, as discussed in [this issue](https://github.com/neovim/neovim/issues/30889). Stay tuned for future developments and improvements!
