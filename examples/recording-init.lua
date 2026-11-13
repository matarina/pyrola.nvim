-- Minimal configuration used by record-demos.py; no user plugins are loaded.
local root = assert(vim.env.PYROLA_DEMO_ROOT)
vim.opt.rtp:prepend(root)
vim.g.mapleader = ' '
vim.o.termguicolors = true
vim.o.number = true
vim.o.swapfile = false
vim.o.showmode = false
vim.o.showcmd = false
vim.o.laststatus = 3
vim.o.showtabline = 2
vim.o.mouse = 'a'
vim.o.guicursor = 'a:block-blinkon0'
vim.o.shortmess = 'IatToOFc'
vim.cmd.colorscheme('habamax')
vim.api.nvim_set_hl(0, 'DemoTitle', {fg='#111827', bg='#5eead4', bold=true})
vim.api.nvim_set_hl(0, 'DemoCaption', {fg='#e2e8f0', bg='#243244', bold=true})
vim.api.nvim_set_hl(0, 'Normal', {fg='#e2e8f0', bg='#101820'})
vim.api.nvim_set_hl(0, 'NormalFloat', {fg='#e2e8f0', bg='#152331'})
vim.api.nvim_set_hl(0, 'CursorLine', {bg='#1c2d3b'})
vim.g.demo_title = 'PYROLA  /  Interactive Python in Neovim'
vim.g.demo_caption = 'Ready'
vim.o.tabline = "%#DemoTitle# %{get(g:, 'demo_title', '')}%=%#DemoTitle# Neovim + Kitty "
vim.o.statusline = "%#DemoCaption# %{get(g:, 'demo_caption', '')}%=%#DemoCaption# Python / Jupyter "
vim.cmd('filetype plugin indent on')
vim.cmd('syntax on')
local pyrola = require('pyrola').setup({
    python_path = assert(vim.env.PYROLA_DEMO_PYTHON),
    kernel_map = {python = 'python3'},
    split_ratio = 0.50,
    image = {protocol='kitty', inline='kitty', max_width_ratio=0.78, max_height_ratio=0.78},
})
vim.api.nvim_create_autocmd('FileType', {
    pattern='python',
    callback=function(ev)
        vim.wo.cursorline = true
        vim.treesitter.start(ev.buf, 'python')
        for lhs, method in pairs({
            ['<CR>']='send_statement_definition',
            ['<leader>vb']='send_buffer_to_repl',
            ['<leader>is']='inspect',
            ['<leader>ig']='show_globals',
            ['<leader>ik']='interrupt_kernel',
            ['<leader>im']='open_history_manager',
        }) do
            vim.keymap.set('n', lhs, pyrola[method], {buffer=ev.buf, silent=true})
        end
        vim.keymap.set('x', '<leader>vs', pyrola.send_visual_to_repl, {buffer=ev.buf, silent=true})
    end,
})
