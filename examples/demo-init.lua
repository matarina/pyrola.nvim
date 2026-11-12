local root = vim.env.PYROLA_DEMO_ROOT or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.env.PYROLA_DEMO_ROOT = root
vim.env.PYROLA_PLOT_OUTPUT = vim.env.PYROLA_PLOT_OUTPUT or root .. '/artifacts/linux-python-plot'
vim.fn.mkdir(vim.env.PYROLA_PLOT_OUTPUT, 'p')
vim.o.number = true
vim.o.termguicolors = true
vim.o.swapfile = false
local pyrola = require('pyrola').setup({
    python_path = '/usr/bin/python3',
    kernel_map = {python = 'python3'}, split_ratio = 0.45,
    image = {protocol = 'kitty', max_width_ratio = 0.85, max_height_ratio = 0.8},
})
-- Source mappings are intentionally local to code buffers, never the REPL.
local function attach_pyrola_keys(buf)
    if vim.bo[buf].buftype ~= '' then return end
    local options = {buffer=buf, silent=true, desc='Pyrola: send semantic statement'}
    vim.keymap.set('n', '<CR>', pyrola.send_statement_definition, options)
    for lhs, method in pairs({
        ['<leader>vs']='send_visual_to_repl', ['<leader>vb']='send_buffer_to_repl',
        ['<leader>is']='inspect', ['<leader>ig']='show_globals',
        ['<leader>ik']='interrupt_kernel', ['<leader>im']='open_history_manager',
    }) do
        vim.keymap.set(lhs == '<leader>vs' and 'v' or 'n', lhs, pyrola[method], {buffer=buf, silent=true})
    end
end
local key_group = vim.api.nvim_create_augroup('PyrolaDemoKeys', {clear=true})
vim.api.nvim_create_autocmd('FileType', {
    group=key_group,
    pattern={'python','r','cpp','julia'},
    callback=function(ev) attach_pyrola_keys(ev.buf) end,
})
for _,buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.tbl_contains({'python','r','cpp','julia'}, vim.bo[buf].filetype) then attach_pyrola_keys(buf) end
end
vim.api.nvim_create_autocmd('VimEnter', {once = true, callback = function()
    vim.schedule(function()
        vim.bo.filetype = 'python'
        pyrola.init()
        local timer = vim.uv.new_timer()
        local submitted = false
        timer:start(100, 200, vim.schedule_wrap(function()
            if not submitted and pyrola.status() == 'ready' then
                submitted = true
                pyrola.send_buffer_to_repl()
            end
            if submitted and pyrola.status() == 'ready' and #require('pyrola.image').history > 0 then
                local image = require('pyrola.image')
                vim.fn.writefile({vim.json.encode({status='PASS', nvim=tostring(vim.version()), image_count=#image.history, width=image.current_image_width, height=image.current_image_height})}, vim.env.PYROLA_PLOT_OUTPUT .. '/pyrola-verification.json')
                timer:stop()
                timer:close()
            end
        end))
    end)
end})
