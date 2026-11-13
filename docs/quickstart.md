# A minimal Python setup

Use Neovim 0.11+ and Python 3.10+. For full-resolution inline plots, use Neovim
0.12+ in Kitty 0.28+. These commands work on Linux and macOS; they do not change
your existing Neovim configuration.

```sh
git clone https://github.com/matarina/pyrola.nvim.git ~/.local/share/pyrola.nvim
mkdir -p ~/pyrola-demo
cd ~/pyrola-demo
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r ~/.local/share/pyrola.nvim/rplugin/python3/requirements.txt ipykernel numpy matplotlib
```

Save this as `demo.py`:

```python
# %% Data
import sys
import numpy as np
import matplotlib.pyplot as plt
print(sys.executable)  # Should point inside ~/pyrola-demo/.venv
x = np.arange(10)

# %% Plot
plt.plot(x, x ** 2)
plt.show()
```

Launch from the same activated shell:

```sh
nvim -u ~/.local/share/pyrola.nvim/examples/minimal-init.lua demo.py
```

Run `:Pyrola init`. In the source pane, press **Space v b** to execute the file,
or **Space v c** to execute the current `# %%` cell. **]c** and **[c** navigate
cells. **Space p t** hides/shows the REPL without restarting the kernel.
**Space i m** opens image history; **h/l** browse plots and **q** closes it.

You do not need `:UpdateRemotePlugins`, a Neovim Python provider, a plugin
manager, or Tree-sitter for buffer/selection/cell execution. Without a parser,
Enter sends the current line. Install a Python Tree-sitter parser if you want
Enter to select complete functions and statements automatically.

The activated environment supplies both Pyrola's Python server and its managed
`pyrola_python` kernel. `:Pyrola setup` can install Pyrola's dependencies and
register the managed kernel too; NumPy and Matplotlib are extra example packages.

## Add Pyrola to Kickstart

Keep the same activated venv when starting your usual Neovim configuration.
The [current Kickstart](https://github.com/nvim-lua/kickstart.nvim) uses
`vim.pack`. Append this to your Kickstart `init.lua`:

```lua
vim.pack.add({{src='https://github.com/matarina/pyrola.nvim'}})
local pyrola = require('pyrola').setup({})
vim.keymap.set('n', '<leader>pv', pyrola.send_buffer_to_repl)
vim.keymap.set('x', '<leader>ps', pyrola.send_visual_to_repl)
vim.keymap.set('n', '<leader>pc', pyrola.send_cell_to_repl)
vim.keymap.set('n', '<leader>pt', pyrola.toggle_split)
vim.keymap.set('n', '<leader>pi', pyrola.inspect)
vim.keymap.set('n', '<leader>pm', pyrola.open_history_manager)
```

Then open `demo.py` and run `:Pyrola init`. These `p` mappings avoid replacing
Kickstart's Enter binding. Kickstart can manage your Tree-sitter parsers normally.

If your older Kickstart uses **lazy.nvim**, enable its `custom.plugins` import
and create `lua/custom/plugins/pyrola.lua` in your config directory:

```lua
return {{
  'matarina/pyrola.nvim',
  config = function()
    local p = require('pyrola').setup({})
    vim.keymap.set('n', '<leader>pv', p.send_buffer_to_repl)
    vim.keymap.set('x', '<leader>ps', p.send_visual_to_repl)
    vim.keymap.set('n', '<leader>pc', p.send_cell_to_repl)
    vim.keymap.set('n', '<leader>pt', p.toggle_split)
  end,
}}
```

Run `:Lazy sync` once. Remove an old `build = ':UpdateRemotePlugins'` line.

## Use a different project kernel

You can keep Pyrola's server environment separate from the code's kernel.
Install `ipykernel` in the project environment and register its own name:

```sh
/path/to/project/.venv/bin/python -m pip install ipykernel
/path/to/project/.venv/bin/python -m ipykernel install --user --name my-project
```

Configure your existing setup (replace paths with your actual paths):

```lua
require('pyrola').setup({
  python_path = '/path/to/pyrola-runtime/.venv/bin/python',
  kernel_map = {python = 'my-project'},
})
```

The server environment needs Pyrola's requirements; the project kernel needs
the libraries your code imports. Use the exact registered name, not `python3`,
unless that is the kernel you registered. Print `sys.executable` in the REPL to
confirm the code uses the project environment.
