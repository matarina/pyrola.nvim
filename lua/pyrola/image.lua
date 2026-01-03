local M = {}

local api = vim.api
local loop = vim.loop
local is_tmux = os.getenv("TMUX")

local default_image_config = {
    tmux_focus_events = true,
    tmux_pane_poll = false,
    tmux_pane_poll_interval = 500,
    cell_width = 10,
    cell_height = 20
}

local image_config = vim.deepcopy(default_image_config)
local tmux_poll_timer = nil
local tmux_pane_active = nil
local tmux_focus_events_enable = nil
local start_tmux_pane_poll = nil

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
    local chunks = {}
    for i = 1, #str, 4096 do
        local chunk = str:sub(i, i + 4096 - 1):gsub("%s", "")
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

local function send_image_chunks(control_str, chunks, x, y)
    if #chunks == 0 then
        return
    end
    write("\x1b[s")
    write(string.format("\x1b[%d;%dH", y, x))

    for i = 1, #chunks do
        local chunk_control = control_str .. ",m=" .. (i < #chunks and "1" or "0")
        local cmd = string.format("\x1b_G%s;%s\x1b\\", chunk_control, chunks[i])
        write(tmux_wrap(cmd))
        loop.sleep(1)
    end

    write("\x1b[u")
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
    local win_width = api.nvim_get_option("columns")
    local win_height = api.nvim_get_option("lines")

    -- Convert image pixels to terminal cells
    local width_cells = pixels_to_cells(image_width, true)
    local height_cells = pixels_to_cells(image_height, false)

    -- Add padding for border (1 cell each side) + small margin
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
    api.nvim_buf_set_option(bufnr, "modifiable", false)
    api.nvim_buf_set_option(bufnr, "buftype", "nofile")

    local winid = api.nvim_open_win(bufnr, focus or false, opts)

    -- Set window highlights
    if not M._float_highlights_set then
        api.nvim_set_hl(0, "FloatBorder", {fg = "#89b4fa", bg = "#1e1e2e"})
        api.nvim_set_hl(0, "FloatTitle", {fg = "#89b4fa", bg = "#1e1e2e"})
        api.nvim_set_hl(0, "NormalFloat", {bg = "#ffffff"})
        M._float_highlights_set = true
    end

    local winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
    if focus then
        winhl = winhl .. ",Cursor:NormalFloat,lCursor:NormalFloat,CursorLine:NormalFloat,CursorLineNr:NormalFloat"
    end
    api.nvim_win_set_option(winid, "winhl", winhl)

    -- Return window info including position for image placement
    return winid, bufnr, row, col, float_width, float_height
end

-- Calculate image position centered within float window
-- float_row/col are 0-indexed from editor top-left
-- Add 1 for border, then center image within content area
local function get_image_position(float_row, float_col, float_width, float_height, image_width, image_height)
    local width_cells = pixels_to_cells(image_width, true)
    local height_cells = pixels_to_cells(image_height, false)

    -- Content area is inside border (subtract 2 for borders)
    local content_width = float_width - 2
    local content_height = float_height - 2

    -- Center image within content area
    local x_offset = math.floor((content_width - width_cells) / 2)
    local y_offset = math.floor((content_height - height_cells) / 2)

    -- Position: float position + border (1) + title row (1) + centering offset
    local x = float_col + 5 + x_offset
    local y = float_row + 5 + y_offset

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

local function display_image(base64_data, width, height, record_history, focus, auto_clear)
    refresh_image_config()
    tmux_focus_events_enable()
    start_tmux_pane_poll()
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
    M.current_float_pos = {row = float_row, col = float_col, width = float_width, height = float_height}

    -- Calculate position centered within the float window
    local x, y = get_image_position(float_row, float_col, float_width, float_height, width, height)

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
    send_image_chunks(control_str, chunks, x, y)
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
    local x, y = get_image_position(pos.row, pos.col, pos.width, pos.height, M.current_image_width, M.current_image_height)

    local control = {
        a = "T", f = 100, t = "d", q = 2, i = 1, C = 1,
        w = M.current_image_width, h = M.current_image_height
    }

    local control_str = build_control_string(control)
    local chunks = get_chunked(M.current_image_data)
    send_image_chunks(control_str, chunks, x, y)
end

-- Setup global autocmds for VimLeave (run once at module load)
tmux_focus_events_enable = function()
    if not is_tmux or not image_config.tmux_focus_events then
        return
    end
    if vim.fn.executable("tmux") == 0 then
        return
    end
    vim.fn.system({"tmux", "set-option", "-g", "focus-events", "on"})
end

local function tmux_pane_is_active()
    if not is_tmux or vim.fn.executable("tmux") == 0 then
        return true
    end
    local pane_id = os.getenv("TMUX_PANE")
    if not pane_id or pane_id == "" then
        return true
    end
    local ok, output = pcall(vim.fn.system, {"tmux", "display-message", "-p", "-t", pane_id, "#{pane_active}"})
    if not ok then
        return true
    end
    output = tostring(output or ""):gsub("%s+", "")
    return output == "1"
end

local function stop_tmux_pane_poll()
    if tmux_poll_timer then
        tmux_poll_timer:stop()
        tmux_poll_timer:close()
        tmux_poll_timer = nil
    end
    tmux_pane_active = nil
end

start_tmux_pane_poll = function()
    if not is_tmux or not image_config.tmux_pane_poll or tmux_poll_timer then
        return
    end
    local interval = tonumber(image_config.tmux_pane_poll_interval) or default_image_config.tmux_pane_poll_interval
    tmux_poll_timer = loop.new_timer()
    tmux_poll_timer:start(
        0,
        interval,
        vim.schedule_wrap(function()
            local active = tmux_pane_is_active()
            if tmux_pane_active == nil then
                tmux_pane_active = active
                return
            end
            if tmux_pane_active ~= active then
                tmux_pane_active = active
                if active then
                    if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
                        redraw_image()
                    end
                else
                    clear_image(1)
                end
            end
        end)
    )
end

local function setup_global_autocmds()
    refresh_image_config()
    tmux_focus_events_enable()
    start_tmux_pane_poll()
    local group = api.nvim_create_augroup("ImageGlobal", {clear = true})

    -- Clear image when quitting Neovim
    api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            stop_tmux_pane_poll()
            clear_image(1)
        end
    })

    -- Handle tmux window switching - clear on focus lost
    api.nvim_create_autocmd("FocusLost", {
        group = group,
        callback = function()
            clear_image(1)
        end
    })

    -- Restore image on focus gained
    api.nvim_create_autocmd("FocusGained", {
        group = group,
        callback = function()
            if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
                vim.defer_fn(function()
                    redraw_image()
                end, 50)
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
