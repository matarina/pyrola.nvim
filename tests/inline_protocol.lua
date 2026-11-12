vim.opt.rtp:prepend(vim.fn.getcwd())
local original_send, original_uis = vim.api.nvim_ui_send, vim.api.nvim_list_uis
local writes = {}
vim.api.nvim_ui_send = function(data) writes[#writes + 1] = data end
vim.api.nvim_list_uis = function() return {{stdout_tty=true}} end
local file = vim.fn.tempname()
vim.fn.writefile({string.rep('A', 9000)}, file)
local function test()
    require('pyrola').setup({image={protocol='kitty'}})
    local inline = require('pyrola.inline')
    local first = inline.render_file(file, 30, 8, 1800, 1170)
    local second = inline.render_file(file, 20, 6, 1800, 1170)
    assert(first:find('\27[38;2;16;0;1m',1,true), 'Missing unique image color')
    assert(second:find('\27[38;2;16;0;2m',1,true), 'Reused an image ID')
    assert(writes[1]:find('U=1',1,true) and writes[1]:find('c=30,r=8',1,true), 'Incorrect inline placement')
    assert(not require('pyrola.image').current_winid, 'Inline output opened a float')
    assert(#require('pyrola.image').history==2, 'History lost inline plots')
    local buf = vim.api.nvim_create_buf(false,true)
    vim.api.nvim_win_set_buf(0,buf)
    local chan = vim.api.nvim_open_term(buf,{})
    vim.api.nvim_chan_send(chan,'before\r\n' .. first:gsub('\n','\r\n') .. 'after\r\n')
    vim.wait(100)
    local lines=vim.api.nvim_buf_get_lines(buf,0,-1,false)
    local placeholder=vim.fn.nr2char(0x10EEEE)
    local function count_placeholders()
        local count=0
        for _,line in ipairs(vim.api.nvim_buf_get_lines(buf,0,-1,false)) do
            if line:find(placeholder,1,true) then count=count+1 end
        end
        return count
    end
    assert(count_placeholders()==8,'PTY did not preserve placeholder rows')
    vim.api.nvim_chan_send(chan, string.rep('scrolling output\r\n',80))
    vim.wait(100)
    assert(count_placeholders()==8,'Scrolling lost the inline image text')
    print('PASS: inline placement, unique IDs, image history, real PTY scrollback')
end
local ok,err=xpcall(test,debug.traceback)
vim.fn.delete(file)
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
vim.cmd('qa!')
