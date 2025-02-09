local M = {}

-- Create TTY output handle
local stdout = vim.loop.new_tty(1, false)
if not stdout then
    error("failed to open stdout")
end

-- Enable tmux passthrough if needed
local function enable_tmux_passthrough()
    if os.getenv("TMUX") then
        local enable_seq = '\027Ptmux;\027\027]52;c;1\007\027\\'
        stdout:write(enable_seq)
    end
end
enable_tmux_passthrough()

-- Helper function to chunk large data
local function get_chunked(str)
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
    if data == "" then
        return
    end
    stdout:write(data)
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

    local float_width = width_cells + 3
    local float_height = height_cells + 3

    -- Calculate center position
    local row = math.floor((win_height - float_height) / 2)
    local col = math.floor((win_width - float_width) / 2)

    local opts = {
        relative = "editor",
        width = float_width,
        height = float_height,
        row = row - 1,
        col = col - 2,
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

    return winid, bufnr
end

-- Calculate center position
local function get_center_position(width, height)
    local term_width = vim.api.nvim_get_option("columns")
    local term_height = vim.api.nvim_get_option("lines")

    local width_cells = pixels_to_cells(width, true)
    local height_cells = pixels_to_cells(height, false)

    local x = math.floor((term_width - width_cells) / 2)
    local y = math.floor((term_height - height_cells) / 2)

    return math.max(x, 0), math.max(y, 0)
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

local function setup_cursor_autocmd()
    local group = vim.api.nvim_create_augroup("ImageClear", {clear = true})
    vim.api.nvim_create_autocmd(
        {"CursorMoved", "CursorMovedI"},
        {
            group = group,
            callback = function()
                clear_image(1)
                if M.current_winid and vim.api.nvim_win_is_valid(M.current_winid) then
                    vim.api.nvim_win_close(M.current_winid, true)
                    M.current_winid = nil
                end
                vim.api.nvim_del_augroup_by_name("ImageClear")
            end,
            once = true
        }
    )
end

-- Main function to display image
function M.show_image(base64_data, width, height)
    if not base64_data then
        error("Base64 image data is required")
    end

    width = tonumber(width or 300)
    height = tonumber(height or 300)

    if M.current_winid and vim.api.nvim_win_is_valid(M.current_winid) then
        vim.api.nvim_win_close(M.current_winid, true)
    end
    M.current_winid = create_image_float(width, height)

    local x, y = get_center_position(width, height)

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

return M

