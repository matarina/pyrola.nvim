vim.opt.rtp:prepend(vim.fn.getcwd())
local original_uis = vim.api.nvim_list_uis
local original_guess = vim.uv.guess_handle
local original_tty = vim.uv.new_tty
local original_send = vim.api.nvim_ui_send
local writes = {}
vim.api.nvim_ui_send = function(data) writes[#writes + 1] = data end
vim.api.nvim_list_uis = function() return {{}} end
vim.uv.guess_handle = function() return "tty" end
vim.uv.new_tty = function()
    return {write = function(_, data) writes[#writes + 1] = data end}
end
local function test()
    require('pyrola').setup({image={protocol='kitty'}})
    require('pyrola.image').show_image(string.rep('A', 9000), 100, 80)
    assert(vim.wait(1000, function() return #writes > 0 end, 10))
    local controls = {}
    for control in table.concat(writes):gmatch('\27_G([^;]*);.-\27\\') do
        controls[#controls + 1] = control
    end
    assert(#controls == 3, vim.inspect(controls))
    assert(controls[1]:find('a=T', 1, true) and controls[1]:find('m=1', 1, true))
    assert(controls[2] == 'q=2,m=1', controls[2])
    assert(controls[3] == 'q=2,m=0', controls[3])
    assert(controls[1]:find('U=1', 1, true), 'Must use a virtual placement')
    local img = require('pyrola.image')
    local win = img.current_winid
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(#lines == vim.api.nvim_win_get_height(win), 'Vertical padding/layout mismatch')
    assert(vim.fn.strdisplaywidth(lines[2]) == vim.api.nvim_win_get_width(win), 'Horizontal padding/layout mismatch')
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, {3, 1})
    vim.api.nvim_exec_autocmds('CursorMoved', {})
    vim.api.nvim_exec_autocmds('FocusLost', {})
    vim.api.nvim_exec_autocmds('FocusGained', {})
    vim.wait(200)
    assert(img.current_winid == win and vim.api.nvim_win_is_valid(win), 'Mouse/cursor activity closed the viewer')
    assert(img.current_image_data, 'Cursor activity discarded image data')
    local saved_columns, saved_lines = vim.o.columns, vim.o.lines
    local previous_geometry
    for _, size in ipairs({{40, 15}, {180, 60}, {20, 8}, {95, 31}}) do
        vim.o.columns, vim.o.lines = size[1], size[2]
        vim.api.nvim_exec_autocmds('VimResized', {})
        vim.wait(100)
        local cfg = vim.api.nvim_win_get_config(win)
        local available = vim.o.lines - math.max(1, vim.o.cmdheight)
        assert(cfg.width + 2 <= vim.o.columns and cfg.height + 2 <= available, 'Float exceeds viewport')
        local left, right = cfg.col, vim.o.columns - cfg.col - cfg.width - 2
        local top, bottom = cfg.row, available - cfg.row - cfg.height - 2
        assert(math.abs(left - right) <= 1 and math.abs(top - bottom) <= 1, 'Float lost centering')
        assert(vim.api.nvim_buf_line_count(buf) == cfg.height, 'Stale placeholder rows after resize')
        local line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
        assert(vim.fn.strdisplaywidth(line) == cfg.width, 'Stale placeholder columns after resize')
        assert(img.current_winid == win and img.current_image_data, 'Resize lost plot')
        previous_geometry = {cfg.width, cfg.height}
    end
    -- Pixel dimensions and configured character metrics must not influence
    -- Kitty layout. Changing them without a viewport change leaves it intact.
    img.current_image_width, img.current_image_height = 30000, 1
    require('pyrola').config.image.cell_width = 99
    require('pyrola').config.image.cell_height = 3
    vim.api.nvim_exec_autocmds('VimResized', {})
    vim.wait(100)
    local cfg = vim.api.nvim_win_get_config(win)
    assert(cfg.width == previous_geometry[1] and cfg.height == previous_geometry[2], 'Layout depends on pixels')
    vim.o.columns, vim.o.lines = saved_columns, saved_lines
    vim.api.nvim_win_close(win, true)
    assert(img.current_winid == nil and img.current_image_data == nil, 'Closed float left stale placement state')
    print('PASS: Kitty placeholder layout, chunk controls, cursor/focus persistence, adaptive resize, pixel independence, close cleanup')
end
local ok, err = xpcall(test, debug.traceback)
vim.api.nvim_list_uis = original_uis
vim.uv.guess_handle = original_guess
vim.uv.new_tty = original_tty
vim.api.nvim_ui_send = original_send
if not ok then
    io.stderr:write(err .. '\n')
    vim.cmd('cquit 1')
end
vim.cmd('qa!')
