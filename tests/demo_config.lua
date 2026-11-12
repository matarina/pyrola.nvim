local root=vim.fn.getcwd()
vim.env.PYROLA_DEMO_ROOT=root
vim.env.PYROLA_PLOT_OUTPUT=vim.fn.tempname()
vim.bo.filetype='python'
dofile(root..'/examples/demo-init.lua')
local function has_enter(buf)
    for _,map in ipairs(vim.api.nvim_buf_get_keymap(buf,'n')) do
        if map.lhs=='<CR>' and map.desc=='Pyrola: send semantic statement' then return true end
    end
    return false
end
local function test()
    assert(has_enter(0),'Saved demo omitted Enter on the initial source buffer')
    local nextbuf=vim.api.nvim_create_buf(true,false)
    vim.api.nvim_set_current_buf(nextbuf)
    vim.bo.filetype='python'
    assert(has_enter(nextbuf),'New Python buffers did not receive Enter')
    local scratch=vim.api.nvim_create_buf(false,true)
    vim.api.nvim_set_current_buf(scratch)
    vim.bo.filetype='python'
    assert(not has_enter(scratch),'Code keybindings leaked into special buffers')
    print('PASS: real demo config installs Enter in existing/new source buffers only')
end
local ok,err=xpcall(test,debug.traceback)
vim.fn.delete(vim.env.PYROLA_PLOT_OUTPUT,'rf')
if not ok then io.stderr:write(err..'\n');vim.cmd('cquit 1') end
vim.cmd('qa!')
