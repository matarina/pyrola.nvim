-- Exercise the README bindings and every key Pyrola installs in its floats.
vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local passed = {}
local function check(name, condition)
    assert(condition, name)
    passed[#passed + 1] = name
end
local function key(value)
    api.nvim_feedkeys(api.nvim_replace_termcodes(value,true,false,true),'xt',false)
end
local function ready()
    assert(vim.wait(30000,function() return require('pyrola').repl_ready end,20),'REPL did not become ready')
end
local function test()
    local p=require('pyrola').setup({python_path=assert(vim.env.PYROLA_TEST_PYTHON),kernel_map={python='python3'},image={protocol='none',inline='none'}})
    vim.bo.filetype='python'
    local source=api.nvim_get_current_buf()
    local source_win=api.nvim_get_current_win()
    for lhs, method in pairs({['<CR>']='send_statement_definition',['<Space>vb']='send_buffer_to_repl',['<Space>is']='inspect',['<Space>ig']='show_globals',['<Space>ik']='interrupt_kernel',['<Space>im']='open_history_manager'}) do
        vim.keymap.set('n',lhs,p[method],{buffer=source})
    end
    vim.keymap.set('v','<Space>vs',p.send_visual_to_repl,{buffer=source})
    api.nvim_buf_set_lines(source,0,-1,false,{'first','second'})
    key('<CR>')
    check('Enter fallback without REPL',api.nvim_win_get_cursor(0)[1]==2)
    p.init(); ready()
    local chan=p.term.chanid
    vim.cmd('Pyrola init')
    check('Pyrola init reuses terminal',p.term.chanid==chan)
    api.nvim_set_current_win(source_win)
    local function fixture(lines,ft)
        api.nvim_set_current_win(source_win)
        vim.bo[source].filetype=ft or 'python'
        api.nvim_buf_set_lines(source,0,-1,false,lines)
        api.nvim_win_set_cursor(0,{1,0})
    end
    fixture({'key_statement = 41'},'lua')
    key('<CR>'); ready()
    fixture({'key_visual = 42',"print('KEY_VISUAL',key_visual)",'unused = 999'})
    key('Vj<Space>vs'); ready()
    check('Visual send exits selection',vim.fn.mode()=='n')
    fixture({'key_buffer = 43',"key_object = type('KeyFixture', (), {f'field_{i:03}': 'X'*200 for i in range(120)})()", "globals().update({f'key_var_{i:03}': i for i in range(150)})", "globals()['key_'+'L'*180] = 7"})
    key('<Space>vb'); ready()
    local result,err=require('pyrola.rpc').request('list_globals',{filetype='python',connection_file=p.connection_file_path})
    assert(not err,err)
    check('Enter sends semantic statement',result.output:find('key_statement',1,true)~=nil)
    check('leader vs sends selected lines',result.output:find('key_visual',1,true)~=nil and not result.output:find('unused',1,true))
    check('leader vb sends buffer',result.output:find('key_buffer',1,true)~=nil)
    local function nav(label)
        local win=api.nvim_get_current_win()
        local buf=api.nvim_win_get_buf(win)
        local count=api.nvim_buf_line_count(buf)
        assert(count>80,'Navigation fixture too short')
        api.nvim_win_set_cursor(win,{1,0}); key('j')
        check(label..' j',api.nvim_win_get_cursor(win)[1]==2)
        key('k'); check(label..' k',api.nvim_win_get_cursor(win)[1]==1)
        for _,spec in ipairs({{'<C-d>',1,1},{'<C-u>',60,-1},{'<C-f>',1,1},{'<C-b>',60,-1}}) do
            api.nvim_win_set_cursor(win,{spec[2],0}); key(spec[1])
            check(label..' '..spec[1],(api.nvim_win_get_cursor(win)[1]-spec[2])*spec[3]>0)
        end
        local longest,row=0,1
        for i,line in ipairs(api.nvim_buf_get_lines(buf,0,-1,false)) do
            if #line>longest then longest,row=#line,i end
        end
        api.nvim_win_set_cursor(win,{row,0}); key('$')
        check(label..' $',api.nvim_win_get_cursor(win)[2]>0)
        key('0'); check(label..' 0',api.nvim_win_get_cursor(win)[2]==0)
        key('L'); local left=vim.fn.winsaveview().leftcol
        check(label..' L',left>0)
        key('H'); check(label..' H',vim.fn.winsaveview().leftcol<left)
    end
    fixture({'key_object'})
    key('<Space>is')
    check('leader is opens inspector',api.nvim_win_get_config(0).relative~='')
    nav('Inspector')
    local win=api.nvim_get_current_win(); key('q'); check('Inspector q',not api.nvim_win_is_valid(win))
    key('<Space>is'); win=api.nvim_get_current_win(); key('<Esc>'); check('Inspector Escape',not api.nvim_win_is_valid(win))
    key('<Space>ig'); check('leader ig opens globals',api.nvim_win_get_config(0).relative~='')
    nav('Globals')
    local globals_win=api.nvim_get_current_win()
    local lines=api.nvim_buf_get_lines(0,0,-1,false)
    for i,line in ipairs(lines) do if line:match('^key_object%s') then api.nvim_win_set_cursor(0,{i,0}); break end end
    key('<CR>'); check('Globals Enter opens inspection',api.nvim_get_current_win()~=globals_win)
    key('q'); key('q'); check('Globals q',not api.nvim_win_is_valid(globals_win))
    key('<Space>ig'); win=api.nvim_get_current_win(); key('<Esc>'); check('Globals Escape',not api.nvim_win_is_valid(win))
    fixture({'import time; time.sleep(20)'})
    key('<Space>vb'); vim.wait(500); key('<Space>ik'); ready()
    check('leader ik interrupts and recovers',p.repl_ready)
    -- Simulate a TTY only for the image protocol; no real graphics escape
    -- sequences are emitted from this headless test.
    local send,uis,guess,tty=api.nvim_ui_send,api.nvim_list_uis,vim.uv.guess_handle,vim.uv.new_tty
    api.nvim_ui_send=function() end
    api.nvim_list_uis=function() return {{stdout_tty=true}} end
    vim.uv.guess_handle=function() return 'tty' end
    vim.uv.new_tty=function() return {write=function() end} end
    p.config.image.protocol='kitty'
    package.loaded['pyrola.image']=nil
    local img=require('pyrola.image')
    img.record_image('AAAA',20,20); img.record_image('BBBB',30,30)
    key('<Space>im'); check('leader im opens history',img.manager_active)
    key('h'); check('Image h',img.history_index==1)
    key('h'); check('Image oldest boundary',img.history_index==1)
    key('l'); check('Image l',img.history_index==2)
    key('l'); check('Image newest boundary',img.history_index==2)
    key('q'); check('Image q',img.current_winid==nil)
    key('<Space>im'); key('<Esc>'); check('Image Escape',img.current_winid==nil)
    api.nvim_ui_send,api.nvim_list_uis,vim.uv.guess_handle,vim.uv.new_tty=send,uis,guess,tty
    require('pyrola.rpc').request('shutdown_kernel',{connection_file=p.connection_file_path})
    p.connection_file_path=nil
    require('pyrola.rpc').stop()
    vim.fn.mkdir(vim.fn.getcwd()..'/artifacts/linux-python-plot','p')
    vim.fn.writefile(passed,vim.fn.getcwd()..'/artifacts/linux-python-plot/keymap-results.txt')
    print('PASS: '..#passed..' Pyrola editor/inspector/globals/image keyboard checks')
end
local ok,err=xpcall(test,debug.traceback)
if not ok then io.stderr:write(err..'\n'); vim.cmd('cquit 1') end
vim.cmd('qa!')
