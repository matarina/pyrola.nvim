local api = vim.api
local M = {}

local function marker()
    return vim.bo.filetype == 'cpp' and '// %%' or '# %%'
end

local function editable()
    return vim.bo.buftype == '' and vim.bo.modifiable
end

local function scan()
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    local pattern = vim.bo.filetype == 'cpp' and '^%s*//%s*%%%%' or '^%s*#%s*%%%%'
    local cells = {}
    for row, line in ipairs(lines) do
        if line:match(pattern) then
            if #cells == 0 and row > 1 then
                cells[1] = {first=1, code=1, last=row-1}
            elseif #cells > 0 then
                cells[#cells].last = row-1
            end
            cells[#cells+1] = {first=row, code=row+1, last=#lines}
        end
    end
    if #cells == 0 then cells[1] = {first=1, code=1, last=#lines} end
    local row = api.nvim_win_get_cursor(0)[1]
    local index = 1
    for i, cell in ipairs(cells) do
        if row >= cell.first then index = i end
    end
    return cells, index
end

function M.current()
    local cells, index = scan()
    return cells[index]
end

function M.code()
    local cell = M.current()
    if cell.code > cell.last then return '' end
    return table.concat(api.nvim_buf_get_lines(0, cell.code-1, cell.last, false), '\n')
end

local function navigate(offset)
    if vim.bo.buftype ~= '' then return false end
    local cells, index = scan()
    local cell = cells[index+offset]
    if not cell then return false end
    api.nvim_win_set_cursor(0, {cell.first, 0})
    return true
end

function M.next() return navigate(1) end
function M.previous() return navigate(-1) end

-- Make the implicit preamble explicit before structural edits, so moving or
-- inserting a cell cannot accidentally merge it with its neighbour.
local function marked()
    local cells, index = scan()
    if cells[1].first == cells[1].code then
        local row = api.nvim_win_get_cursor(0)[1]
        api.nvim_buf_set_lines(0, 0, 0, false, {marker()})
        api.nvim_win_set_cursor(0, {row+1, 0})
        cells, index = scan()
    end
    return cells, index
end

local function insert(below)
    if not editable() then return false end
    local cells, index = marked()
    local cell = cells[index]
    local start = below and cell.last or cell.first-1
    api.nvim_buf_set_lines(0, start, start, false, {marker(), ''})
    api.nvim_win_set_cursor(0, {start+2, 0})
    return true
end

function M.insert_above() return insert(false) end
function M.insert_below() return insert(true) end

function M.delete()
    if not editable() then return false end
    local cell = M.current()
    api.nvim_buf_set_lines(0, cell.first-1, cell.last, false, {})
    api.nvim_win_set_cursor(0, {math.min(cell.first, api.nvim_buf_line_count(0)), 0})
    return true
end

local function move(offset)
    if not editable() then return false end
    local original, index = scan()
    if not original[index+offset] then return false end
    local cells
    cells, index = marked()
    local cell, neighbour = cells[index], cells[index+offset]
    local row, col = unpack(api.nvim_win_get_cursor(0))
    local current = api.nvim_buf_get_lines(0, cell.first-1, cell.last, false)
    local other = api.nvim_buf_get_lines(0, neighbour.first-1, neighbour.last, false)
    local lines = {}
    local first, second = offset < 0 and current or other, offset < 0 and other or current
    vim.list_extend(lines, first)
    vim.list_extend(lines, second)
    local start = math.min(cell.first, neighbour.first)
    api.nvim_buf_set_lines(0, start-1, math.max(cell.last, neighbour.last), false, lines)
    local target = offset < 0 and neighbour.first or neighbour.first+#other-#current
    api.nvim_win_set_cursor(0, {target+row-cell.first, col})
    return true
end

function M.move_up() return move(-1) end
function M.move_down() return move(1) end

function M.select()
    if vim.bo.buftype ~= '' then return false end
    local cell = M.current()
    if cell.code > cell.last then return false end
    api.nvim_win_set_cursor(0, {cell.code, 0})
    vim.cmd('normal! V')
    api.nvim_win_set_cursor(0, {cell.last, 0})
    return true
end

return M
