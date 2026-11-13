-- Run directly: nvim -u /path/to/pyrola.nvim/examples/minimal-init.lua demo.py
-- Activate your project's Python venv before launching Neovim.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.g.mapleader = ' '
vim.o.swapfile = false
vim.o.termguicolors = true
vim.cmd('filetype plugin indent on')
local p = require('pyrola').setup({})
vim.keymap.set('n', '<leader>pt', p.toggle_split, {desc='Pyrola: toggle REPL'})
local function attach(buf)
    if vim.bo[buf].buftype ~= '' then return end
    for key, method in pairs({
        ['<CR>']='send_statement_definition', ['<leader>vb']='send_buffer_to_repl',
        ['<leader>is']='inspect', ['<leader>ig']='show_globals',
        ['<leader>ik']='interrupt_kernel', ['<leader>im']='open_history_manager',
        ['<leader>vc']='send_cell_to_repl', [']c']='next_cell', ['[c']='previous_cell',
    }) do
        vim.keymap.set('n', key, p[method], {buffer=buf, desc='Pyrola: '..method})
    end
    vim.keymap.set('x', '<leader>vs', p.send_visual_to_repl, {buffer=buf})
end
vim.api.nvim_create_autocmd('FileType', {
    pattern={'python','r','cpp','julia'}, callback=function(ev) attach(ev.buf) end,
})
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.tbl_contains({'python','r','cpp','julia'}, vim.bo[buf].filetype) then attach(buf) end
end
