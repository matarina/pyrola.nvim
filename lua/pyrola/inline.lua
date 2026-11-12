-- Real inline rasters: the PTY carries colored Unicode placeholders while
-- image bytes go directly to the host TUI. libvterm never has to decode PNGs.
local api = vim.api
local kitty = require('pyrola.kitty')
local M = {}
local next_id = 0x100000
local images = {}
local function delete(id)
    api.nvim_ui_send(string.format('\27_Ga=d,d=I,i=%d,q=2\27\\', id))
end

function M.render_file(path, columns, rows, width, height)
    if not api.nvim_ui_send then return nil end
    local tty = false
    for _, ui in ipairs(api.nvim_list_uis()) do tty = tty or ui.stdout_tty == true end
    if not tty then return nil end
    local file = assert(io.open(path, 'rb'))
    local data = file:read('*a')
    file:close()
    columns = math.max(1, math.min(math.floor(columns), kitty.max_cells))
    rows = math.max(1, math.min(math.floor(rows), kitty.max_cells))
    if next_id >= 0xFFFFFF then next_id = 0x100000 end
    next_id = next_id + 1
    local id = next_id
    local parts = {}
    for offset = 1, #data, 4096 do
        local control = offset == 1 and string.format(
            'a=T,U=1,f=100,t=d,q=2,i=%d,c=%d,r=%d,', id, columns, rows
        ) or 'q=2,'
        parts[#parts + 1] = '\27_G' .. control
            .. 'm=' .. (offset + 4096 > #data and '0' or '1')
            .. ';' .. data:sub(offset, offset + 4095) .. '\27\\'
    end
    local transfer = table.concat(parts)
    if vim.env.TMUX then
        for i, part in ipairs(parts) do
            parts[i] = '\27Ptmux;' .. part:gsub('\27', '\27\27') .. '\27\\'
        end
        transfer = table.concat(parts)
    end
    api.nvim_ui_send(transfer)
    images[#images + 1] = id
    -- Keep scrollback memory bounded. Older text remains, but images beyond
    -- this cache are released, just like the floating image history.
    if #images > 50 then delete(table.remove(images, 1)) end
    require('pyrola.image').record_image(data, width, height)
    local color = string.format('\27[38;2;%d;%d;%dm',
        math.floor(id / 65536) % 256, math.floor(id / 256) % 256, id % 256)
    local lines = {}
    for row = 1, rows do
        lines[row] = color .. kitty.line(row, columns) .. '\27[0m\n'
    end
    return table.concat(lines)
end

api.nvim_create_autocmd('VimLeavePre', {
    group = api.nvim_create_augroup('PyrolaInlineImages', {clear = true}),
    callback = function() for _, id in ipairs(images) do delete(id) end end,
})
return M
