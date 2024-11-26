-- r_query.lua

-- Require necessary modules
local http = require("socket.http")
local cjson = require("cjson") -- Use standard cjson for better performance
local ltn12 = require("ltn12")
local M = {}

-- Helper function to send HTTP POST requests to the R server
local function make_request(request, port)
    local url = "http://127.0.0.1:" .. port
    local ok, request_body = pcall(cjson.encode, request)
    if not ok then
        print("Failed to encode request to JSON:", request_body)
        return nil
    end

    local response_table = {}
    local res, code, headers, status = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_table)
    }

    if not res then
        print("HTTP request failed:", status or "Unknown error")
        return nil
    end

    if code ~= 200 then
        print("HTTP request returned status:", code, status)
        return nil
    end

    local response_body = table.concat(response_table)
    if not response_body or response_body == "" then
        print("Empty response from server")
        return nil
    end

    local success, response_json = pcall(cjson.decode, response_body)
    if not success then
        print("Error decoding JSON response:", response_json)
        return nil
    end

    return response_json
end


local function display_content(content_lines, syntax, borderline)
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#FFFFFF', bg = '#000000' })
    local bufnr, winid = vim.lsp.util.open_floating_preview(content_lines, syntax or "plaintext", {
        border = borderline or "rounded",
        focusable = true,
        wrap = false,
        zindex = 100,
        sidescrolloff = 0,
        virtualedit = "onemore"
    })

    local api = vim.api

    -- Check if the window was successfully created
    if winid and api.nvim_win_is_valid(winid) then
        -- Set the floating window as the current window to auto-focus
        api.nvim_set_current_win(winid)
    else
        -- Handle the case where the window was not created
        vim.notify("Failed to create floating window", vim.log.levels.ERROR)
        return
    end

    -- Set keymaps for the buffer to handle closing and navigation
    local opts = { noremap = true, silent = true, buffer = bufnr }

    vim.api.nvim_win_set_option(winid, 'winhl', 'Normal:Normal,FloatBorder:FloatBorder,FloatTitle:FloatTitle')

    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(winid, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(winid, true) end, opts)

    -- Optional: Add navigation keymaps (example: scrolling)
    vim.keymap.set('n', 'h', '10h', opts)
    vim.keymap.set('n', 'l', '10l', opts)
end

-- Function to split string by delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

-- Read CSV file
local function read_csv(filename)
    local headers = {}
    local data = {}
    local line_count = 0

    for line in io.lines(filename) do
        if line_count == 0 then
            headers = split(line, ",")
            for _, header in ipairs(headers) do
                data[header] = {}
            end
        else
            local values = split(line, ",")
            for i, value in ipairs(values) do
                local num = tonumber(value)
                table.insert(data[headers[i]], num or value)
            end
        end
        line_count = line_count + 1
    end

    return headers, data
end

-- Calculate column widths
local function get_column_widths(headers, data)
    local widths = {}
    for _, header in ipairs(headers) do
        widths[header] = #header
        for _, value in ipairs(data[header]) do
            local str_len = #tostring(value)
            if str_len > widths[header] then
                widths[header] = str_len
            end
        end
    end
    return widths
end

-- Padding function
local function pad(str, width)
    return str .. string.rep(" ", width - #tostring(str))
end

-- Function to display CSV as a formatted table in a floating window
local function display_csv_as_table(filename)
    -- Read CSV
    local headers, data = read_csv(filename)
    local col_widths = get_column_widths(headers, data)
    local num_rows = #data[headers[1]]

    -- Prepare lines for the table
    local lines = {}

    -- -- Top border
    -- local top_border = "╭"
    -- for i, header in ipairs(headers) do
    --     top_border = top_border .. string.rep("─", col_widths[header] + 2)
    --     top_border = top_border .. (i < #headers and "┬" or "╮")
    -- end
    -- table.insert(lines, top_border)
    --
    -- Header row
    local header_line = "┆"
    for i, header in ipairs(headers) do
        header_line = header_line .. " " .. pad(header, col_widths[header]) .. " ┆"
    end
    table.insert(lines, header_line)

    -- Separator
    local separator = "├"
    for i, header in ipairs(headers) do
        separator = separator .. string.rep("-", col_widths[header] + 2)
        separator = separator .. (i < #headers and "┼" or "┤")
    end
    table.insert(lines, separator)

    -- Data rows
    for row = 1, num_rows do
        local line = "┆"
        for i, header in ipairs(headers) do
            line = line .. " " .. pad(tostring(data[header][row]), col_widths[header]) .. " ┆"
        end
        table.insert(lines, line)
    end

    -- Bottom border
    -- local bottom_border = "╰"
    -- for i, header in ipairs(headers) do
    --     bottom_border = bottom_border .. string.rep("─", col_widths[header] + 2)
    --     bottom_border = bottom_border .. (i < #headers and "┴" or "╯")
    -- end
    -- table.insert(lines, bottom_border)

    -- Display the table in a floating window
    display_content(lines, "markdown", "rounded")
    vim.defer_fn(function()
        local success, err = os.remove(filename)
        if not success then
            vim.notify("Failed to remove temporary CSV file: " .. (err or "unknown error"), vim.log.levels.WARN)
        end
    end, 100)
end

-- Main handler to process received data based on type
local function HandleReceivedData(response)
    if not response then
        print("No response received from the server.")
        return
    end

    if response.status ~= "success" then
        print("Error from server:", response.message)
        return
    end

    local data_type = response.type
    local data = response.data

    if data_type == "csv_path" then
        display_csv_as_table(data)
    elseif data_type == "info" then
        local content = {}
        for line in data:gmatch("([^\n]+)") do
            table.insert(content, line)
        end
        display_content(content, "plaintext")
    else
        print("Unknown data type received:", data_type)
    end
end

-- Function to inspect a specific R object by name
function M.inspect(obj_name, port)
    local request = { type = "inspect", obj = obj_name }
    local response = make_request(request, port)
    if response then
        HandleReceivedData(response)
    else
        print("Failed to inspect object:", obj_name)
    end
end


-- Function to inspect a specific R dataframe object by name
function M.table_view(obj_name, port)
    local request = { type = "table_view", obj = obj_name }
    local response = make_request(request, port)
    if response then
        HandleReceivedData(response)
    else
        print("Failed to inspect object:", obj_name)
    end
end

-- Function to query and display all global environment variables
function M.query_global(port)
    local request = { type = "query_global" }
    local response = make_request(request, port)

    if response and response.status == "success" and response.global_env then
        local content = { "**Global Environment Variables:**" }
        for _, var in ipairs(response.global_env) do
            table.insert(content, string.format("**Name:** %s", var.name))
            table.insert(content, string.format("**Type:** %s", var.type))
            table.insert(content, string.format("**Class:** %s", var.class))
            table.insert(content, string.format("**Length:** %s", tostring(var.length)))
            table.insert(content, "**Detail:**")
            for _, line in ipairs(var.structure) do
                table.insert(content, "    " .. line)
            end
            table.insert(content, "------------------------------")
        end
        display_content(content, "markdown")
    else
        print("Error in R server response:", response and response.message or "Unknown error")
    end
end

return M

