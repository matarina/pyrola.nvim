-- Run with examples/minimal-init.lua and an activated Python venv on PATH.
local api = vim.api
local p = require('pyrola')
local python = assert(vim.env.PYROLA_TEST_PYTHON)
local project = vim.env.PYROLA_PROJECT_PYTHON or python
local function wait(check, label)
    assert(vim.wait(30000,check,20),label..' timed out')
end
local function test()
    assert(p.config.python_path==nil, 'Minimal setup must use the active venv')
    local active=vim.fn.exepath('python3')
    assert(vim.fn.fnamemodify(active,':h')==vim.fn.fnamemodify(python,':h'), 'Wrong active venv')
    vim.g.loaded_python3_provider=0
    vim.g.python3_host_prog='/does/not/exist'
    vim.bo.filetype='python'
    local source, win = api.nvim_get_current_buf(),api.nvim_get_current_win()
    local function execute(expected, marker)
        api.nvim_set_current_win(win)
        api.nvim_buf_set_lines(source,0,-1,false,{
            'import sys',"print('QUICKSTART_'+'"..marker.."',sys.executable)",
            'raise RuntimeError("must not execute unselected code")',
        })
        api.nvim_win_set_cursor(win,{1,0})
        api.nvim_feedkeys(api.nvim_replace_termcodes('Vj<Space>vs',true,false,true),'xt',false)
        wait(function()
            -- Long venv paths soft-wrap in the narrow REPL split.
            return p.repl_ready and table.concat(api.nvim_buf_get_lines(p.term.bufid,0,-1,false),''):find('QUICKSTART_'..marker..' '..expected,1,true)
        end,marker)
        assert(not table.concat(api.nvim_buf_get_lines(p.term.bufid,0,-1,false),'\n'):find('RuntimeError:',1,true))
    end
    p.init()
    wait(function() return p.status()=='ready' end,'minimal managed kernel')
    execute(active,'ACTIVE_VENV')
    local rpc=require('pyrola.rpc')
    rpc.request('shutdown_kernel',{connection_file=p.connection_file_path})
    p.connection_file_path=nil
    vim.fn.jobstop(p.term.chanid)
    wait(function() return p.status()=='stopped' end,'old console stopped')
    rpc.stop()
    api.nvim_set_current_win(win)
    local result=vim.system({project,'-m','ipykernel','install','--user','--name','pyrola_issue_project'},{text=true}):wait()
    assert(result.code==0,result.stderr)
    p.setup({python_path=python,kernel_map={python='pyrola_issue_project'}})
    p.init()
    wait(function() return p.status()=='ready' end,'separate registered project kernel')
    assert(p.active_kernel_name=='pyrola_issue_project')
    execute(project,'PROJECT_VENV')
    assert(vim.fn.exists('*InitKernel')==0)
    print('PASS: minimal config, active venv, mapped visual execution, disabled provider and explicitly registered project environment')
end
local ok,err=xpcall(test,debug.traceback)
if not ok then io.stderr:write(err..'\n');vim.cmd('cquit 1') end
vim.cmd('qa!')
