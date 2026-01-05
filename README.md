<div align="center">




</div><img width="2004" height="538" alt="logo" src="https://github.com/user-attachments/assets/f4e9d2f9-488a-4d02-9cea-a7ced4c44011" />



Got it 👍
Here is the **same cleaned-up README**, but with **your original video image links preserved exactly as you provided them** (no thumbnail substitutions, no rewritten image URLs).
I only corrected formatting, grammar, and structure.

---

# Pyrola

If you are seeking an alternative to **Jupyter**, **Spyder**, or **RStudio**, **Pyrola** is the solution.

Pyrola delivers a **multi-language REPL (Read–Eval–Print Loop)** experience inside **Neovim**. It is designed for interactive programming, especially for **data scientists**, and supports:

* Real-time code execution
* Variable inspection
* Image visualization

Since Pyrola is built on **Jupyter kernels**, **any language with a Jupyter kernel can theoretically be integrated**.

---

## DEMO

<div align="center">
  <a href="https://www.youtube.com/watch?v=S3arFOPnD40">
    <img src="https://img.youtube.com/vi/S3arFOPnD40/0.jpg" alt="Watch the video" style="width:100%;">
  </a>
</div>

---

## Features


* **Multi-language support**
  Pyrola is designed around Jupyter kernels. Any language with a Jupyter kernel can be used in Pyrola.

  ![recording\_2026-01-04\_07-36-08 - frame at 0m57s](https://github.com/user-attachments/assets/71d3ca3c-4f16-4567-b81c-c9d7e77383bc)

* **Real-time REPL**
  Execute code dynamically inside Neovim with immediate feedback.

* **Multiple code block selection methods**

  * Semantic code block detection based on Tree-sitter syntax parsing
  * Visual selection
  * Send the entire buffer to the REPL with one click

* **Environment variable inspector**
  Inspect variables and view their attributes (class, type, etc.) directly inside the REPL.
  *(Currently supported: Python and R)*

  ![recording\_2026-01-04\_07-36-08 - frame at 0m52s](https://github.com/user-attachments/assets/c6668a17-da69-4ae5-ba88-841ec9f3f059)

* **Image viewer**
  Preview image outputs directly in Neovim:

  * High-resolution rendering via **Kitty image protocol**
  * Fallback ASCII/Unicode rendering for rough previews

  ![recording\_2026-01-04\_07-36-08 - frame at 0m40s](https://github.com/user-attachments/assets/7ad7400c-f251-452b-879f-e9bd39d4f791)

* **History image viewer**
  Stores plotted images and allows browsing previous image outputs in a floating Neovim window.

---

## Installation

### 1) Default setup

Add Pyrola to your plugin manager. Example using **lazy.nvim**:

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
      split_ratio = 0.3,
      send_buffer_key = "<leader>vb",
      image_manager_key = "<leader>im",
    })

    -- Semantic code block sending (based on cursor position)
    vim.keymap.set("n", "<CR>", function()
      pyrola.send_statement_definition()
    end, { noremap = true })

    -- Visual selection sending
    vim.keymap.set("v", "<leader>vs", function()
      pyrola.send_visual_to_repl()
    end, { noremap = true })

    -- Send whole buffer
    vim.keymap.set("n", "<leader>vb", function()
      pyrola.send_buffer_to_repl()
    end, { noremap = true })

    -- Inspect variable under cursor
    vim.keymap.set("n", "<leader>is", function()
      pyrola.inspect()
    end, { noremap = true })

    -- History image viewer
    vim.keymap.set("n", "<leader>im", function()
      pyrola.open_history_manager()
    end, { noremap = true })
  end,
}
```

---

### Treesitter (required)

Tree-sitter is required, and the language parsers listed in `kernel_map` must be installed.

```lua
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local ts = require("nvim-treesitter")

    ts.setup({
      install_dir = vim.fn.stdpath("data") .. "/site",
    })

    ts.install({ "python", "r", "lua" })
  end,
}
```

---

### 2) Python + pip in PATH

Pyrola is developed using **pynvim**, so make sure `python` and `pip` are available in your `PATH`.

Using **Conda** or other virtual environments is highly recommended.
After activating your environment, Pyrola will prompt you to install required Python dependencies automatically, or you can install them manually:

```bash
python3 -m pip install --user \
  pynvim \
  jupyter-client \
  prompt-toolkit \
  pillow \
  pygments
```

---

### 3) Install Jupyter kernels

#### Python example

```bash
python3 -m pip install --user ipykernel
python3 -m ipykernel install --user --name py3
```

> The kernel name **must match** the value in `kernel_map`.

#### Other languages

* **R**

  ```r
  IRkernel::installspec()
  ```
* **C++**

  * Install `xeus-cling` (kernel name depends on installation)

---

### 4) Image preview helper (recommended)

For high-quality image rendering:

* **Kitty terminal** is required
* **timg** is required for embedded pixel image rendering

On Debian / Ubuntu:

```bash
apt install timg
```

#### tmux note

Image hide/show behavior depends on focus events. Add the following to `~/.tmux.conf`:

```tmux
set -g focus-events on
set -g allow-passthrough all
```

---

## Usage

### Start a REPL

1. Open a file whose `filetype` exists in `kernel_map`

   ```vim
   :echo &filetype
   ```
2. Start the kernel and REPL:

   ```vim
   :Pyrola init
   ```

---

### Send code

* **Current semantic block**

  ```lua
  pyrola.send_statement_definition()
  ```
* **Visual selection**

  ```lua
  pyrola.send_visual_to_repl()
  ```
* **Whole buffer**

  ```lua
  pyrola.send_buffer_to_repl()
  ```

---

### Inspect variables

Place the cursor on a symbol and run:

```lua
pyrola.inspect()
```

*(Currently supported: Python and R — easy to extend, contributions welcome.)*

---

### Image history manager

Press `<leader>im` to open the image manager.

When focused:

* `h` — previous image
* `l` — next image
* `q` — close

---

## Credit

* [Jupyter Team](https://github.com/jupyter/jupyter)
* [nvim-python-repl](https://github.com/geg2102/nvim-python-repl)
  Pyrola draws inspiration from this project.

---

## Contributing

Contributions are welcome!
Pyrola is in its early stages and actively maintained. Issues and pull requests will receive prompt attention.

For enhanced image rendering, terminal graphic protocols such as **Kitty** or **Sixel** are not yet supported inside Neovim terminal buffers due to upstream limitations:

[https://github.com/neovim/neovim/issues/30889](https://github.com/neovim/neovim/issues/30889)

Stay tuned for future improvements 🚀

---
