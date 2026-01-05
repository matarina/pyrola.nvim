local M = {}

local api = vim.api
local fn = vim.fn
local loop = vim.loop
local is_tmux = os.getenv("TMUX")

local default_image_config = {
    cell_width = 10,
    cell_height = 20,
    max_width_ratio = 0.5,
    max_height_ratio = 0.5,
    offset_row = 0,
    offset_col = 0
}

local image_config = vim.deepcopy(default_image_config)

local function refresh_image_config()
    local ok, pyrola = pcall(require, "pyrola")
    if ok and pyrola.config and pyrola.config.image then
        image_config = vim.tbl_deep_extend("force", vim.deepcopy(default_image_config), pyrola.config.image)
    else
        image_config = vim.deepcopy(default_image_config)
    end
end
refresh_image_config()

-- Create TTY output handle
local stdout = loop.new_tty(1, false)

-- Track current image state for focus handling
M.current_winid = nil
M.current_image_data = nil
M.current_image_width = nil
M.current_image_height = nil
M.current_float_pos = nil
M.history = {}
M.history_index = 0
M.manager_winid = nil
M.manager_bufid = nil
M.manager_active = false
M.manager_guicursor = nil

local MAX_HISTORY = 50

-- Enable tmux passthrough if needed
local function enable_tmux_passthrough()
    if stdout and is_tmux then
        local enable_seq = '\027Ptmux;\027\027]52;c;1\007\027\\'
        stdout:write(enable_seq)
    end
end
enable_tmux_passthrough()

-- Helper function to chunk large data
local function get_chunked(str)
    if type(str) ~= "string" then
        return {}
    end
    local chunk_size = is_tmux and 1024 or 4096
    local chunks = {}
    for i = 1, #str, chunk_size do
        local chunk = str:sub(i, i + chunk_size - 1):gsub("%s", "")
        if #chunk > 0 then
            table.insert(chunks, chunk)
        end
    end
    return chunks
end

-- Helper function to write to terminal
local function write(data)
    if not stdout or data == "" then
        return
    end
    stdout:write(data)
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function get_tmux_offset(cursor_row, cursor_col)
    if not is_tmux then
        return 0, 0
    end
    if fn.executable("tmux") == 0 then
        return 0, 0
    end
    if not cursor_row or not cursor_col then
        return 0, 0
    end
    local pane = os.getenv("TMUX_PANE")
    local function read_tmux(format)
        local args = {"tmux", "display-message", "-p"}
        if pane and pane ~= "" then
            table.insert(args, "-t")
            table.insert(args, pane)
        end
        table.insert(args, format)
        local output = fn.systemlist(args)
        local line = output and output[1] or ""
        local left, top, cursor_x, cursor_y = line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if not left then
            return nil
        end
        return tonumber(left), tonumber(top), tonumber(cursor_x), tonumber(cursor_y)
    end

    local left, top, cursor_x, cursor_y =
        read_tmux("#{pane_left} #{pane_top} #{pane_cursor_x} #{pane_cursor_y}")
    if not left then
        left, top, cursor_x, cursor_y = read_tmux("#{pane_left} #{pane_top} #{cursor_x} #{cursor_y}")
    end
    if not left or not top or not cursor_x or not cursor_y then
        return 0, 0
    end
    local global_row = top + cursor_y + 1
    local global_col = left + cursor_x + 1
    local row_offset = global_row - cursor_row
    local col_offset = global_col - cursor_col
    return row_offset, col_offset
end

local function get_cursor_screenpos_raw()
    local winid = api.nvim_get_current_win()
    if not api.nvim_win_is_valid(winid) then
        return nil, nil
    end
    local cursor = api.nvim_win_get_cursor(winid)
    local row = cursor[1]
    local col = cursor[2] + 1
    local ok, pos = pcall(fn.screenpos, winid, row, col)
    if ok and type(pos) == "table" then
        local screen_row = tonumber(pos.row) or 0
        local screen_col = tonumber(pos.col) or 0
        if screen_row >= 1 and screen_col >= 1 then
            return screen_row, screen_col
        end
    end
    return nil, nil
end

local function tmux_wrap(cmd)
    if is_tmux then
        cmd = cmd:gsub('\027', '\027\027')
        return '\027Ptmux;' .. cmd .. '\027\\'
    end
    return cmd
end

local function build_control_string(control)
    local parts = {}
    for key, value in pairs(control) do
        parts[#parts + 1] = string.format("%s=%s", key, value)
    end
    return table.concat(parts, ",")
end

local function get_window_screenpos(winid)
    local ok, pos = pcall(fn.screenpos, winid, 1, 1)
    if ok and type(pos) == "table" then
        local row = tonumber(pos.row) or 0
        local col = tonumber(pos.col) or 0
        if row >= 1 and col >= 1 then
            return row, col
        end
    end

    local ok_win, winpos = pcall(fn.win_screenpos, winid)
    if not ok_win or type(winpos) ~= "table" then
        return nil, nil
    end
    local row = tonumber(winpos[1]) or 0
    local col = tonumber(winpos[2]) or 0
    if row < 1 or col < 1 then
        return nil, nil
    end
    return row, col
end

local function send_image_chunks(control_str, chunks, x, y, restore_row, restore_col)
    if #chunks == 0 then
        return
    end
    if is_tmux then
        for i = 1, #chunks do
            local chunk_control = control_str .. ",m=" .. (i < #chunks and "1" or "0")
            local parts = {
                string.format("\x1b[%d;%dH", y, x),
                string.format("\x1b_G%s;%s\x1b\\", chunk_control, chunks[i])
            }
            if i == #chunks and restore_row and restore_col then
                parts[#parts + 1] = string.format("\x1b[%d;%dH", restore_row, restore_col)
            end
            write(tmux_wrap(table.concat(parts)))
        end
        return
    end

    write(string.format("\x1b[%d;%dH", y, x))
    for i = 1, #chunks do
        local chunk_control = control_str .. ",m=" .. (i < #chunks and "1" or "0")
        local cmd = string.format("\x1b_G%s;%s\x1b\\", chunk_control, chunks[i])
        write(cmd)
    end
    if restore_row and restore_col then
        write(string.format("\x1b[%d;%dH", restore_row, restore_col))
    end
end

local function pixels_to_cells(pixels, is_width)
    local cell_width = tonumber(image_config.cell_width) or default_image_config.cell_width
    local cell_height = tonumber(image_config.cell_height) or default_image_config.cell_height
    if is_width then
        return math.ceil(pixels / cell_width)
    end
    return math.ceil(pixels / cell_height)
end

local function create_image_float(image_width, image_height, focus)
    local win_width = vim.o.columns
    local win_height = vim.o.lines

    -- Convert image pixels to terminal cells
    local width_cells = pixels_to_cells(image_width, true)
    local height_cells = pixels_to_cells(image_height, false)

    -- Add small padding inside the content area for centering
    local float_width = width_cells + 2
    local float_height = height_cells + 2

    -- Calculate center position
    local row = math.floor((win_height - float_height) / 2)
    local col = math.floor((win_width - float_width) / 2)

    local opts = {
        relative = "editor",
        width = float_width,
        height = float_height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Image View ",
        title_pos = "center"
    }

    local bufnr = api.nvim_create_buf(false, true)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].buftype = "nofile"

    local winid = api.nvim_open_win(bufnr, focus or false, opts)

    -- Set window highlights
    local border_hl = "PyrolaImageBorder"
    local title_hl = "PyrolaImageTitle"
    local normal_hl = "PyrolaImageNormal"

    if not M._image_highlights_set then
        local border_target = fn.hlexists("FloatBorder") == 1 and "FloatBorder" or "WinSeparator"
        local title_target = fn.hlexists("FloatTitle") == 1 and "FloatTitle" or "Title"
        local normal_target = fn.hlexists("NormalFloat") == 1 and "NormalFloat" or "Normal"

        if fn.hlexists(border_hl) == 0 then
            api.nvim_set_hl(0, border_hl, {link = border_target})
        end
        if fn.hlexists(title_hl) == 0 then
            api.nvim_set_hl(0, title_hl, {link = title_target})
        end
        if fn.hlexists(normal_hl) == 0 then
            api.nvim_set_hl(0, normal_hl, {link = normal_target})
        end
        M._image_highlights_set = true
    end

    local winhl = string.format("Normal:%s,FloatBorder:%s,FloatTitle:%s", normal_hl, border_hl, title_hl)
    if focus then
        winhl = winhl .. string.format(
            ",Cursor:%s,lCursor:%s,CursorLine:%s,CursorLineNr:%s",
            normal_hl,
            normal_hl,
            normal_hl,
            normal_hl
        )
    end
    vim.wo[winid].winhl = winhl

    -- Return window info including position for image placement
    return winid, bufnr, row, col, float_width, float_height
end

-- Calculate image position centered within float window
-- float_row/col are 0-indexed from editor top-left
-- Add 1 for border, then center image within content area
local function get_image_position(base_row, base_col, float_width, float_height, image_width, image_height)
    local width_cells = pixels_to_cells(image_width, true)
    local height_cells = pixels_to_cells(image_height, false)

    -- Content area is the floating window itself (border is outside)
    local content_width = float_width
    local content_height = float_height

    -- Center image within content area
    local x_offset = math.max(0, math.floor((content_width - width_cells) / 2))
    local y_offset = math.max(0, math.floor((content_height - height_cells) / 2))

    -- Position: top-left window in screen coords + centering offset
    local x = base_col + x_offset
    local y = base_row + y_offset

    return math.max(x, 1), math.max(y, 1)
end

-- Helper function to clear images
local function clear_image(image_id)
    local control = {
        a = "d", -- Delete action
        d = "i", -- Delete by image ID
        i = image_id, -- Image ID to delete
        q = 2 -- Quiet mode
    }

    local control_str = build_control_string(control)

    local cmd = string.format("\x1b_G%s\x1b\\", control_str)
    write(tmux_wrap(cmd))
end

-- Clear all images and close float window
local function cleanup_image()
    clear_image(1)
    if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
        api.nvim_win_close(M.current_winid, true)
    end
    M.current_winid = nil
    M.current_image_data = nil
    M.current_image_width = nil
    M.current_image_height = nil
    M.current_float_pos = nil
    M.manager_winid = nil
    M.manager_bufid = nil
    M.manager_active = false
    if M.manager_guicursor then
        vim.o.guicursor = M.manager_guicursor
        M.manager_guicursor = nil
    end
end

local function push_history(entry)
    if #M.history >= MAX_HISTORY then
        table.remove(M.history, 1)
    end
    table.insert(M.history, entry)
    M.history_index = #M.history
end

local function setup_cursor_autocmd()
    local group = api.nvim_create_augroup("ImageClear", {clear = true})
    api.nvim_create_autocmd(
        {"CursorMoved", "CursorMovedI"},
        {
            group = group,
            callback = function()
                cleanup_image()
                api.nvim_del_augroup_by_name("ImageClear")
            end,
            once = true
        }
    )
end

local function set_manager_keymaps(bufnr)
    local opts = {noremap = true, silent = true, nowait = true, buffer = bufnr}
    vim.keymap.set("n", "h", function()
        M.show_previous_image(true)
    end, opts)
    vim.keymap.set("n", "l", function()
        M.show_next_image(true)
    end, opts)
    vim.keymap.set("n", "q", function()
        cleanup_image()
    end, opts)
end

local function draw_image(base64_data, width, height, winid, float_row, float_col, float_width, float_height)
    if not api.nvim_win_is_valid(winid) then
        return
    end
    local cursor_row, cursor_col = get_cursor_screenpos_raw()
    local row_offset, col_offset = get_tmux_offset(cursor_row, cursor_col)
    local row_adjust = tonumber(image_config.offset_row) or 0
    local col_adjust = tonumber(image_config.offset_col) or 0
    local base_row, base_col = get_window_screenpos(winid)
    if not base_row then
        base_row = float_row + 1
        base_col = float_col + 1
    end
    base_row = base_row + row_offset + row_adjust
    base_col = base_col + col_offset + col_adjust
    local x, y = get_image_position(base_row, base_col, float_width, float_height, width, height)

    local control = {
        a = "T", -- Transmit and display
        f = 100, -- PNG format
        t = "d", -- Direct transmission
        q = 2, -- Quiet mode
        i = 1, -- Image ID
        C = 1, -- Don't move cursor
        w = width, -- Image width
        h = height -- Image height
    }

    local control_str = build_control_string(control)
    local chunks = get_chunked(base64_data)
    local restore_row, restore_col = nil, nil
    if cursor_row and cursor_col then
        restore_row = cursor_row + row_offset
        restore_col = cursor_col + col_offset
    end
    send_image_chunks(control_str, chunks, x, y, restore_row, restore_col)
end

local function display_image(base64_data, width, height, record_history, focus, auto_clear)
    refresh_image_config()
    if not stdout then
        vim.notify("Pyrola: Image display disabled (no TTY available).", vim.log.levels.WARN)
        return
    end
    if type(base64_data) ~= "string" or base64_data == "" then
        vim.notify("Pyrola: Image data missing or invalid.", vim.log.levels.WARN)
        return
    end

    width = tonumber(width or 300)
    height = tonumber(height or 300)

    if record_history then
        push_history({data = base64_data, width = width, height = height})
    end

    if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
        api.nvim_win_close(M.current_winid, true)
    end

    local winid, bufnr, float_row, float_col, float_width, float_height =
        create_image_float(width, height, focus)
    M.current_winid = winid

    -- Store image state for focus restore
    M.current_image_data = base64_data
    M.current_image_width = width
    M.current_image_height = height
    M.current_float_pos = {winid = winid, row = float_row, col = float_col, width = float_width, height = float_height}

    vim.defer_fn(function()
        if M.current_winid ~= winid then
            return
        end
        draw_image(base64_data, width, height, winid, float_row, float_col, float_width, float_height)
    end, 20)
    if focus then
        M.manager_winid = winid
        M.manager_bufid = bufnr
        M.manager_active = true
        set_manager_keymaps(bufnr)
        if not M.manager_guicursor then
            M.manager_guicursor = vim.o.guicursor
            vim.o.guicursor = "a:ver1-Cursor"
        end
    else
        M.manager_winid = nil
        M.manager_bufid = nil
        M.manager_active = false
    end
    if auto_clear then
        setup_cursor_autocmd()
    end
end

-- Redraw image at stored position (for focus restore)
local function redraw_image()
    if not M.current_image_data or not M.current_float_pos then
        return
    end

    local pos = M.current_float_pos
    local winid = pos.winid
    if not winid or not api.nvim_win_is_valid(winid) then
        return
    end
    vim.defer_fn(function()
        if not api.nvim_win_is_valid(winid) then
            return
        end
        draw_image(
            M.current_image_data,
            M.current_image_width,
            M.current_image_height,
            winid,
            pos.row,
            pos.col,
            pos.width,
            pos.height
        )
    end, 20)
end

-- Setup global autocmds for VimLeave (run once at module load)
local function setup_global_autocmds()
    refresh_image_config()
    local group = api.nvim_create_augroup("ImageGlobal", {clear = true})

    -- Clear image when quitting Neovim
    api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            clear_image(1)
        end
    })

    -- Handle window switching - clear on focus lost
    api.nvim_create_autocmd("FocusLost", {
        group = group,
        callback = function()
            M.image_needs_redraw = true
            clear_image(1)
        end
    })

    local function maybe_redraw_image()
        if not M.image_needs_redraw then
            return
        end
        if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
            vim.defer_fn(function()
                redraw_image()
                M.image_needs_redraw = false
            end, 50)
        end
    end

    -- Restore image on focus gained or user interaction
    api.nvim_create_autocmd({"FocusGained", "WinEnter", "BufEnter", "CursorMoved", "CursorMovedI", "VimResume"}, {
        group = group,
        callback = function()
            maybe_redraw_image()
        end
    })

    api.nvim_create_autocmd({"WinEnter", "BufEnter", "VimResume"}, {
        group = group,
        callback = function()
            if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
                vim.defer_fn(function()
                    redraw_image()
                end, 120)
            end
        end
    })
end
setup_global_autocmds()

-- Main function to display image
function M.show_image(base64_data, width, height)
    display_image(base64_data, width, height, true, false, true)
end

function M.show_image_file(path, width, height)
    if type(path) ~= "string" or path == "" then
        vim.notify("Pyrola: Image path missing or invalid.", vim.log.levels.WARN)
        return
    end
    local content = read_file(path)
    if not content or content == "" then
        vim.notify("Pyrola: Image file empty or unreadable.", vim.log.levels.WARN)
        return
    end
    display_image(content, width, height, true, false, true)
end

local function show_history_at(index, focus)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if index < 1 or index > #M.history then
        return
    end
    local entry = M.history[index]
    M.history_index = index
    display_image(entry.data, entry.width, entry.height, false, focus, not focus)
end

function M.open_history_manager()
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    show_history_at(#M.history, true)
end

function M.show_last_image()
    show_history_at(#M.history, false)
end

function M.show_previous_image(focus)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if M.history_index <= 1 then
        M.history_index = 1
        vim.notify("Pyrola: Already at oldest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(M.history_index - 1, focus or M.manager_active)
end

function M.show_next_image(focus)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if M.history_index >= #M.history then
        M.history_index = #M.history
        vim.notify("Pyrola: Already at newest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(M.history_index + 1, focus or M.manager_active)
end

return M
