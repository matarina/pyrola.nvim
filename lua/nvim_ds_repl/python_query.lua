local ltn12 = require("ltn12")
local http = require("socket.http")
local cjson = require("cjson")
local M = {}

-- Helper function to send HTTP requests
local function send_request(path, port)
    local response_body = {}
    local url = "http://localhost:" .. port .. path

    local res, code, response_headers = http.request{
        url = url,
        sink = ltn12.sink.table(response_body)
    }

    if res == 1 and code == 200 then
        local body = table.concat(response_body)
        local ok, data = pcall(cjson.decode, body)
        if ok then
            return data
        else
            print("Error parsing JSON:", data)
            return nil
        end
    else
        print("HTTP request failed with code:", code)
        return nil
    end
end

-- Helper function to process the info string (if needed)
local function process_info_string(info_str)
    local lines = {}
    
    -- Split the info string into lines
    for line in info_str:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end
    
    -- Remove the first and last lines if they contain `{` or `}`
    if lines[1] == "{" then table.remove(lines, 1) end
    if lines[#lines] == "}" then table.remove(lines, #lines) end

    -- Convert escaped `\n` to actual newlines
    for i, line in ipairs(lines) do
        lines[i] = line:gsub("\\n", "\n")
    end

    return table.concat(lines, "\n")
end


local function display_dataframe(df_data)
    -- Decode the DataFrame JSON
    local success, data = pcall(cjson.decode, df_data)
    if not success then
        print("Error decoding DataFrame JSON:", data)
        return
    end

    if type(data) ~= 'table' or #data == 0 then
        print("Invalid or empty DataFrame.")
        return
    end

    -- Extract headers and calculate column widths
    local headers = {}
    local col_widths = {}
    for key, _ in pairs(data[1]) do
        table.insert(headers, key)
        col_widths[key] = #key
    end

    -- Calculate maximum widths for each column
    for _, row in ipairs(data) do
        for _, header in ipairs(headers) do
            local cell = tostring(row[header] or "")
            col_widths[header] = math.max(col_widths[header], #cell)
        end
    end

    -- Padding function
    local function pad(str, width)
        return str .. string.rep(" ", width - #str)
    end

    -- Build table lines
    local lines = {}

    -- Header row
    local header_line = "┆ "
    for _, header in ipairs(headers) do
        header_line = header_line .. pad(header, col_widths[header]) .. " ┆ "
    end
    table.insert(lines, header_line)

    -- Separator line
    local sep_line = "┆"
    for _, header in ipairs(headers) do
        sep_line = sep_line .. string.rep("-", col_widths[header] + 2) .. "┆"
    end
    table.insert(lines, sep_line)

    -- Data rows
    for _, row in ipairs(data) do
        local row_line = "┆ "
        for _, header in ipairs(headers) do
            local cell = tostring(row[header] or "")
            row_line = row_line .. pad(cell, col_widths[header]) .. " ┆ "
        end
        table.insert(lines, row_line)
    end

    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Calculate window dimensions
    local total_width = 1  -- Starting width (for initial pipe)
    for _, width in pairs(col_widths) do
        total_width = total_width + width + 3  -- Add column width + 3 (for " | ")
    end

    -- Calculate window size (with maximum limits)
    local max_width = math.floor(vim.o.columns * 0.9)
    local max_height = math.floor(vim.o.lines * 0.8)
    local win_width = math.min(total_width, max_width)
    local win_height = math.min(#lines, max_height)

    -- Calculate position
    local row = math.floor((vim.o.lines - win_height) / 2)
    local col = math.floor((vim.o.columns - win_width) / 2)

    -- Window options
    local win_opts = {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' DataFrame ',
        title_pos = 'center',
        zindex = 50
    }

    -- Create window
    local win = vim.api.nvim_open_win(buf, true, win_opts)

    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    -- Set window options
    vim.api.nvim_win_set_option(win, 'wrap', false)  -- Disable line wrapping
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'signcolumn', 'no')

    -- Keymaps
    local opts = { noremap = true, silent = true, buffer = buf }
    
    -- Close window
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(win, true) end, opts)
    
    vim.keymap.set('n', 'h', '10zh', opts)  -- Scroll faster
    vim.keymap.set('n', 'l', '10zl', opts)

    -- Auto-close on buffer leave
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end,
    })

    -- Handle window resize
    vim.api.nvim_create_autocmd("VimResized", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                local new_max_width = math.floor(vim.o.columns * 0.9)
                local new_max_height = math.floor(vim.o.lines * 0.8)
                local new_win_width = math.min(total_width, new_max_width)
                local new_win_height = math.min(#lines, new_max_height)
                
                vim.api.nvim_win_set_config(win, {
                    relative = 'editor',
                    width = new_win_width,
                    height = new_win_height,
                    row = math.floor((vim.o.lines - new_win_height) / 2),
                    col = math.floor((vim.o.columns - new_win_width) / 2)
                })
            end
        end,
    })

    return buf, win
end



local function display_info(info_str)
    -- Create a new buffer
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer content and split into lines
    local lines = vim.split(info_str, '\n')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Calculate content dimensions
    local max_width = 0
    for _, line in ipairs(lines) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end
    
    -- Calculate window dimensions with padding
    local padding = 4
    local win_width = math.min(max_width + padding, math.floor(vim.o.columns * 0.9))
    local win_height = math.min(#lines, math.floor(vim.o.lines * 0.8))
    
    -- Ensure minimum dimensions
    win_width = math.max(win_width, 40)
    win_height = math.max(win_height, 3)
    
    local win_opts = {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = math.floor((vim.o.lines - win_height) / 2),
        col = math.floor((vim.o.columns - win_width) / 2),
        style = 'minimal',
        border = 'rounded',
        title = ' Info ',
        title_pos = 'center',
        zindex = 50
    }
    
    -- Create floating window
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'text')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    
    -- Set window options
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'winblend', 0)
    
    -- Add keymaps for the floating window
    local opts = { noremap = true, silent = true, buffer = buf }
    
    -- Close window with q, <Esc>, or <C-c>
    vim.keymap.set('n', 'q', function()
        vim.api.nvim_win_close(win, true)
    end, opts)
    vim.keymap.set('n', '<Esc>', function()
        vim.api.nvim_win_close(win, true)
    end, opts)
    vim.keymap.set('n', '<C-c>', function()
        vim.api.nvim_win_close(win, true)
    end, opts)
    
    -- Scrolling
    vim.keymap.set('n', '<C-d>', '<C-d>zz', opts)
    vim.keymap.set('n', '<C-u>', '<C-u>zz', opts)
    vim.keymap.set('n', '<C-f>', '<C-f>zz', opts)
    vim.keymap.set('n', '<C-b>', '<C-b>zz', opts)
    vim.keymap.set('n', 'j', 'gj', opts)
    vim.keymap.set('n', 'k', 'gk', opts)
    
    -- Set autocmd to close on buffer leave
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end,
    })
    
    -- Handle window resize
    vim.api.nvim_create_autocmd("VimResized", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                -- Recalculate dimensions
                local new_win_width = math.min(max_width + padding, math.floor(vim.o.columns * 0.9))
                local new_win_height = math.min(#lines, math.floor(vim.o.lines * 0.8))
                
                -- Ensure minimum dimensions
                new_win_width = math.max(new_win_width, 40)
                new_win_height = math.max(new_win_height, 3)
                
                -- Update window configuration
                vim.api.nvim_win_set_config(win, {
                    relative = 'editor',
                    width = new_win_width,
                    height = new_win_height,
                    row = math.floor((vim.o.lines - new_win_height) / 2),
                    col = math.floor((vim.o.columns - new_win_width) / 2)
                })
            end
        end,
    })
    
    return buf, win
end


-- Main handler to process received data based on type
local function HandleReceivedData(info_field)
    local success, response = pcall(cjson.decode, info_field)
    if not success then
        print("Error decoding 'info' field:", response)
        return
    end

    if type(response) ~= 'table' then
        print("Invalid response format in 'info' field.")
        return
    end

    -- Check the type field
    local data_type = response.type
    local data = response.data

    if data_type == 'dataframe' then
        display_dataframe(data)
    elseif data_type == 'info' then
        display_info(data)
    else
        print("Unknown data type:", data_type)
    end
end

-- Updated M.inspect function to handle different data types
function M.inspect(var_name, port)
    local path = "/inspect_var?name=" .. var_name
    local var_info = send_request(path, port)
    if var_info and var_info.info then
        HandleReceivedData(var_info.info)
    else
        print("Failed to query variable:", var_name)
    end
end

-- Updated M.query_global function (optional: display as plain text)
function M.query_global(port)
    local global_vars = send_request("/query_global", port)
    if global_vars and global_vars.globals then
        -- Assuming global_vars.globals is a string from 'whos' magic
        local cleaned_info = process_info_string(global_vars.globals)
        
        -- Open a new buffer and set its content
        vim.api.nvim_command('vnew')
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {cleaned_info})

        -- Optional: Set buffer options for better readability
        vim.api.nvim_buf_set_option(buf, 'modifiable', false)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'text') -- Plain text
    else
        print("Failed to query global variables.")
    end
end

return M
