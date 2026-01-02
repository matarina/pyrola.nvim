local M = {}

-- Create TTY output handle
local stdout = vim.loop.new_tty(1, false)
if not stdout then
    stdout = nil
end

-- Track current image state for focus handling
M.current_winid = nil
M.current_image_data = nil
M.current_image_width = nil
M.current_image_height = nil
M.current_float_pos = nil

-- Enable tmux passthrough if needed
local function enable_tmux_passthrough()
    if stdout and os.getenv("TMUX") then
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
    if os.getenv("TMUX") then
        cmd = cmd:gsub('\027', '\027\027')
        return '\027Ptmux;' .. cmd .. '\027\\'
    end
    return cmd
end

local function pixels_to_cells(pixels, is_width)
    local cell_width = 10
    local cell_height = 20

    if is_width then
        return math.ceil(pixels / cell_width)
    else
        return math.ceil(pixels / cell_height)
    end
end

local function create_image_float(image_width, image_height)
    local win_width = vim.api.nvim_get_option("columns")
    local win_height = vim.api.nvim_get_option("lines")

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

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")

    local winid = vim.api.nvim_open_win(bufnr, false, opts)

    -- Set window highlights
    vim.api.nvim_set_hl(0, "FloatBorder", {fg = "#89b4fa", bg = "#1e1e2e"})
    vim.api.nvim_set_hl(0, "FloatTitle", {fg = "#89b4fa", bg = "#1e1e2e"})
    vim.api.nvim_set_hl(0, "NormalFloat", {bg = "#ffffff"})

    vim.api.nvim_win_set_option(winid, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle")

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

    local control_str = ""
    for k, v in pairs(control) do
        control_str = control_str .. k .. "=" .. v .. ","
    end
    control_str = control_str:sub(1, -2)

    local cmd = string.format("\x1b_G%s\x1b\\", control_str)
    write(tmux_wrap(cmd))
end

-- Clear all images and close float window
local function cleanup_image()
    clear_image(1)
    if M.current_winid and vim.api.nvim_win_is_valid(M.current_winid) then
        vim.api.nvim_win_close(M.current_winid, true)
    end
    M.current_winid = nil
    M.current_image_data = nil
    M.current_image_width = nil
    M.current_image_height = nil
    M.current_float_pos = nil
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

    local control_str = ""
    for k, v in pairs(control) do
        control_str = control_str .. k .. "=" .. v .. ","
    end
    control_str = control_str:sub(1, -2)

    local chunks = get_chunked(M.current_image_data)

    write("\x1b[s")
    write(string.format("\x1b[%d;%dH", y, x))

    for i = 1, #chunks do
        local chunk_control = control_str
        chunk_control = chunk_control .. ",m=" .. (i < #chunks and "1" or "0")
        local cmd = string.format("\x1b_G%s;%s\x1b\\", chunk_control, chunks[i])
        write(tmux_wrap(cmd))
        control_str = "m=" .. (i == #chunks - 1 and "0" or "1")
        vim.loop.sleep(1)
    end

    write("\x1b[u")
end

-- Setup global autocmds for VimLeave (run once at module load)
local function setup_global_autocmds()
    local group = vim.api.nvim_create_augroup("ImageGlobal", {clear = true})

    -- Clear image when quitting Neovim
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            clear_image(1)
        end
    })

    -- Handle tmux window switching - clear on focus lost
    vim.api.nvim_create_autocmd("FocusLost", {
        group = group,
        callback = function()
            clear_image(1)
        end
    })

    -- Restore image on focus gained
    vim.api.nvim_create_autocmd("FocusGained", {
        group = group,
        callback = function()
            if M.current_winid and vim.api.nvim_win_is_valid(M.current_winid) then
                vim.defer_fn(function()
                    redraw_image()
                end, 50)
            end
        end
    })
end
setup_global_autocmds()

local function setup_cursor_autocmd()
    local group = vim.api.nvim_create_augroup("ImageClear", {clear = true})
    vim.api.nvim_create_autocmd(
        {"CursorMoved", "CursorMovedI"},
        {
            group = group,
            callback = function()
                cleanup_image()
                vim.api.nvim_del_augroup_by_name("ImageClear")
            end,
            once = true
        }
    )
end

-- Main function to display image
function M.show_image(base64_data, width, height)
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

    if M.current_winid and vim.api.nvim_win_is_valid(M.current_winid) then
        vim.api.nvim_win_close(M.current_winid, true)
    end

    local winid, _, float_row, float_col, float_width, float_height = create_image_float(width, height)
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

    local control_str = ""
    for k, v in pairs(control) do
        control_str = control_str .. k .. "=" .. v .. ","
    end
    control_str = control_str:sub(1, -2)

    local chunks = get_chunked(base64_data)

    write("\x1b[s")
    write(string.format("\x1b[%d;%dH", y, x))

    for i = 1, #chunks do
        local chunk_control = control_str
        if i < #chunks then
            chunk_control = chunk_control .. ",m=1"
        else
            chunk_control = chunk_control .. ",m=0"
        end

        local cmd = string.format("\x1b_G%s;%s\x1b\\", chunk_control, chunks[i])
        write(tmux_wrap(cmd))

        control_str = "m=" .. (i == #chunks - 1 and "0" or "1")
        vim.loop.sleep(1)
    end

    write("\x1b[u")
    setup_cursor_autocmd()
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
    M.show_image(content, width, height)
end

return M
