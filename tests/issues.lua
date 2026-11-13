-- Regressions for #3 and #6: real kernel execution, cells and window lifetime.
vim.opt.rtp:prepend(vim.fn.getcwd())
local api = vim.api
local function wait(check, label)
    assert(vim.wait(30000, check, 20), label .. ' timed out')
end
local function test()
    local p = require('pyrola').setup({python_path=assert(vim.env.PYROLA_TEST_PYTHON),
        kernel_map={python='python3'}, image={protocol='none',inline='none'}})
    p.setup({split_horizen=true})
    assert(p.config.split_horizontal, 'Legacy split option ignored')
    p.setup({split_horizontal=false})
    vim.bo.filetype='python'
    local source, source_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    local function fixture(lines, row, ft)
        api.nvim_set_current_win(source_win)
        vim.bo.filetype=ft or 'python'
        api.nvim_buf_set_lines(source,0,-1,false,lines)
        api.nvim_win_set_cursor(0,{row or 1,0})
    end
    local function lines() return api.nvim_buf_get_lines(source,0,-1,false) end
    local function expect(value) assert(vim.deep_equal(lines(),value),vim.inspect(lines())) end
    fixture({'alpha','# %% B','beta'})
    assert(not p.move_cell_up())
    expect({'alpha','# %% B','beta'})
    assert(p.move_cell_down())
    expect({'# %% B','beta','# %%','alpha'})
    assert(api.nvim_win_get_cursor(0)[1]==4)
    assert(p.move_cell_up())
    expect({'# %%','alpha','# %% B','beta'})
    p.insert_cell_above()
    expect({'# %%','','# %%','alpha','# %% B','beta'})
    p.delete_cell()
    expect({'# %%','alpha','# %% B','beta'})
    p.insert_cell_below()
    expect({'# %%','alpha','# %%','','# %% B','beta'})
    p.delete_cell()
    p.previous_cell()
    assert(p.select_cell())
    assert(vim.fn.mode()=='V')
    vim.cmd('normal! \27')
    fixture({'# %% A','# %% empty','# %% C','value=1'},2)
    assert(require('pyrola.cells').code()=='')
    assert(not p.select_cell())
    assert(p.next_cell() and api.nvim_win_get_cursor(0)[1]==3)
    assert(not p.next_cell() and not p.move_cell_down())
    fixture({'// %% A','int x=1;','// %% B','int y=2;'},2,'cpp')
    assert(require('pyrola.cells').code()=='int x=1;')
    fixture({'# %% A','x <- 1','# %% B','y <- 2'},2,'r')
    assert(require('pyrola.cells').code()=='x <- 1')
    fixture({''})
    p.delete_cell(); expect({''})
    print('PASS: cell insertion, deletion, movement, navigation, selection, preamble and empty boundaries')

    -- A disabled provider and absent remote-plugin functions must not prevent startup.
    vim.g.loaded_python3_provider=0
    vim.g.python3_host_prog='/does/not/exist'
    assert(vim.fn.exists('*InitKernel')==0)
    fixture({'excluded_before=999','# %% A','cell_value=6*7',"print('ISSUE_'+'CELL',cell_value)",'# %% B','raise RuntimeError("unselected cell")'},3)
    p.init()
    wait(function() return p.status()=='ready' end,'kernel startup without provider')
    local chan, buf, connection = p.term.chanid, p.term.bufid, p.connection_file_path
    local function output(text)
        wait(function() return p.repl_ready and table.concat(api.nvim_buf_get_lines(buf,0,-1,false),'\n'):find(text,1,true) end,text)
    end
    api.nvim_set_current_win(source_win)
    vim.cmd('Pyrola cell')
    output('ISSUE_CELL 42')
    local globals, err=require('pyrola.rpc').request('list_globals',{filetype='python',connection_file=connection})
    assert(not err and globals.output:find('cell_value',1,true) and not globals.output:find('excluded_before',1,true),vim.inspect({globals,err}))
    p.next_cell(); p.previous_cell()
    assert(api.nvim_win_get_cursor(0)[1]==2)
    print('PASS: issue #3 startup/selected cell execution without InitKernel or a Python provider')

    vim.cmd('Pyrola toggle')
    assert(p.term.winid==0 and api.nvim_buf_is_valid(buf) and p.status()=='ready')
    fixture({"cell_value += 1; print('ISSUE_'+'HIDDEN',cell_value)"})
    p.send_buffer_to_repl(); output('ISSUE_HIDDEN 43')
    local float=api.nvim_open_win(api.nvim_create_buf(false,true),true,{relative='editor',row=1,col=1,width=10,height=2})
    vim.cmd('Pyrola toggle')
    assert(api.nvim_get_current_win()==float, 'Toggle stole inspector focus')
    api.nvim_win_close(float,true)
    api.nvim_set_current_win(source_win)
    assert(p.term.winid > 0 and api.nvim_win_is_valid(p.term.winid) and p.term.chanid==chan and p.term.bufid==buf and p.connection_file_path==connection)
    api.nvim_set_current_win(source_win)
    p.toggle_split()
    p.init() -- init must also reopen a hidden split without a new console/kernel
    assert(p.term.winid > 0 and api.nvim_win_is_valid(p.term.winid) and p.term.chanid==chan)
    api.nvim_win_close(p.term.winid,true)
    api.nvim_set_current_win(source_win)
    p.init()
    assert(p.term.winid > 0 and api.nvim_win_is_valid(p.term.winid) and p.term.chanid==chan)
    -- Hiding the REPL when it is the final ordinary window restores a source window.
    api.nvim_set_current_win(p.term.winid)
    api.nvim_win_close(source_win,true)
    p.toggle_split()
    assert(api.nvim_get_current_buf()==source and p.term.winid==0 and p.term.chanid==chan)
    p.config.split_horizontal=true
    p.toggle_split()
    assert(p.term.winid > 0 and api.nvim_win_is_valid(p.term.winid) and vim.wo[p.term.winid].winfixheight)
    print('PASS: split hide/show, execution while hidden, init reopening, last-window and horizontal layout retain kernel state')
end
local ok,err=xpcall(test,debug.traceback)
if not ok then io.stderr:write(err..'\n');vim.cmd('cquit 1') end
vim.cmd('qa!')
