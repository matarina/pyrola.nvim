local api = vim.api
local root = vim.fn.getcwd()
local python = assert(vim.env.PYROLA_TEST_PYTHON, "Set PYROLA_TEST_PYTHON")
api.nvim_set_current_dir(root)
vim.opt.rtp:prepend(root)
local notifications = {}
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
end
local function wait_for(predicate, label)
    assert(vim.wait(30000, predicate, 20), label .. " timed out: " .. vim.inspect(notifications))
end
local function test()
    local p = require("pyrola").setup({python_path = python, kernel_map = {python = "python3"}, image = {protocol = "none"}})
    p.setup({}) -- repeated setup must not duplicate commands/autocmds
    assert(vim.fn.exists(":Pyrola") == 2)
    assert(vim.deep_equal(vim.fn.getcompletion("Pyrola ", "cmdline"), {"init", "setup"}))
    -- No terminal escapes or libuv TTY handles when headless.
    assert(require("pyrola.image"))
    vim.cmd.colorscheme("default")
    vim.bo.filetype = "python"
    api.nvim_buf_set_lines(0, 0, -1, false, {"answer = 6 * 7", "print('PYROLA_RESULT', answer)"})
    local source = api.nvim_get_current_buf()
    local source_win = api.nvim_get_current_win()
    p.init()
    assert(p.plugin_path == root, "Plugin root resolution failed")
    assert(p.term.chanid > 0, vim.inspect(notifications))
    assert(vim.bo[p.term.bufid].buftype == "terminal")
    local channel = p.term.chanid
    local win_count = #api.nvim_list_wins()
    p.init()
    assert(p.term.chanid == channel and #api.nvim_list_wins() == win_count, "init duplicated terminal")
    api.nvim_set_current_win(source_win)
    wait_for(function() return p.status() == "ready" end, "REPL startup")
    p.send_buffer_to_repl()
    wait_for(function()
        return p.repl_ready and table.concat(api.nvim_buf_get_lines(p.term.bufid, 0, -1, false), "\n"):find("PYROLA_RESULT 42", 1, true)
    end, "code execution")
    -- Exercise semantic selection with Neovim's bundled Lua parser. This
    -- assignment is valid Python too, so it can execute in the same kernel.
    vim.bo.filetype = "lua"
    api.nvim_buf_set_lines(source, 0, -1, false, {"semantic_value = 99"})
    api.nvim_win_set_cursor(0, {1, 0})
    assert(vim.treesitter.get_parser(0):parse()[1])
    p.send_statement_definition()
    wait_for(function() return p.repl_ready end, "Tree-sitter statement execution")
    vim.bo.filetype = "python"
    local rpc = require("pyrola.rpc")
    local globals, err = rpc.request("list_globals", {filetype="python", connection_file=p.connection_file_path})
    assert(not err, err)
    assert(globals.output:find("answer", 1, true) and globals.output:find("42", 1, true) and globals.output:find("semantic_value", 1, true), globals.output)
    api.nvim_buf_set_lines(source, 0, -1, false, {"answer"})
    api.nvim_win_set_cursor(0, {1, 0})
    p.inspect() -- no Python parser: must fall back to <cword>
    assert(#api.nvim_list_wins() > win_count, "Inspector float did not open")
    vim.cmd("close")
    p.show_globals()
    assert(#api.nvim_list_wins() > win_count, "Globals float did not open")
    vim.cmd("close")
    api.nvim_buf_set_lines(source, 0, -1, false, {"import time; time.sleep(20)"})
    p.send_buffer_to_repl()
    vim.wait(500) -- let the console deliver the cell before interrupting it
    p.interrupt_kernel()
    wait_for(function() return p.repl_ready end, "interrupt recovery")
    local stopped, stop_err = rpc.request("shutdown_kernel", {connection_file=p.connection_file_path})
    assert(not stop_err and stopped.shutdown, stop_err)
    p.connection_file_path = nil
    vim.fn.jobstop(channel)
    wait_for(function() return p.status() == "stopped" end, "terminal exit state")
    rpc.stop()
    for _, note in ipairs(notifications) do
        assert(note[2] ~= vim.log.levels.ERROR, note[1])
    end
    print("PASS: terminal startup, execution, inspection, globals, repeat init, shutdown on " .. tostring(vim.version()))
end
local ok, err = xpcall(test, debug.traceback)
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
end
vim.cmd("qa!")
