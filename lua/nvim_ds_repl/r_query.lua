local api = vim.api
local http = require("socket.http")
local cjson = require("cjson")
local M = {}

local function create_float_window(content_lines)
    -- Create a new empty buffer
    local buf = api.nvim_create_buf(false, true)

    -- Set the content of the buffer
    api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)

    -- Determine the width and height of the floating window based on content
    local width = 0
    for _, line in ipairs(content_lines) do
        if #line > width then
            width = #line
        end
    end
    local height = #content_lines

    -- Calculate the position of the floating window
    local win_width = api.nvim_get_option("columns")
    local win_height = api.nvim_get_option("lines")
    local row = math.floor((win_height - height) / 2)
    local col = math.floor((win_width - width) / 2)

    -- Set up window options
    local opts = {
        style = "minimal",
        relative = "editor",
        width = width + 2,  -- Add some padding
        height = height + 2, -- Add some padding
        row = row,
        col = col,
        border = "rounded",  -- Set a border style
    }

    -- Create the floating window
    local win = api.nvim_open_win(buf, true, opts)

    -- Set window options (optional)
    api.nvim_win_set_option(win, "wrap", true)
    api.nvim_win_set_option(win, "cursorline", false)
end



local function make_request(request, port)
    local url = "http://127.0.0.1:" .. port
    local request_body = cjson.encode(request)
    local response_body = {}
    
    local _, status_code, headers = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }
    
    local response_json, pos, err = cjson.decode(table.concat(response_body))
    
    return response_json
end

function M.query_global(port)
    local response_json = make_request({ type = "query_global" }, port)

    local content_lines = {"Global Environment Variables:"}
    if response_json and response_json.status == "success" then
        for _, info in ipairs(response_json.global_env) do
            table.insert(content_lines, "Name: " .. info.name)
            table.insert(content_lines, "Type: " .. info.type)
            table.insert(content_lines, "Class: " .. info.class)
            table.insert(content_lines, "Length: " .. tostring(info.length))
            table.insert(content_lines, "Detail: " )
            if type(info.structure) == "table" then
                for _, line in ipairs(info.structure) do
                    table.insert(content_lines, line)
                end
            elseif type(info.structure) == "string" then
                table.insert(content_lines, info.structure)
            end
            table.insert(content_lines, "==============================")
        end
        vim.lsp.util.open_floating_preview(content_lines, "markdown", { border = "rounded" })
    else
        print("Error in R server response: " .. (response_json and response_json.message or "Unknown error"))
    end
end



function M.inspect(obj_name, port)
    local response_json = make_request({ type = "inspect", obj = obj_name }, port)
    if response_json and response_json.status == "success" then
        local content_lines = {
            "Type: " .. response_json.object.type,
            "Class: " .. response_json.object.class,
            "Length: " .. tostring(response_json.object.length),
            "Content:"
        }

        if type(response_json.object.content) == "table" then
            for _, line in ipairs(response_json.object.content) do
                table.insert(content_lines, line)
            end
        else
            table.insert(content_lines, tostring(response_json.object.content))
        end

        vim.lsp.util.open_floating_preview(content_lines, "markdown", { border = "rounded" })
    else
        print("Error in R server response: " .. (response_json and response_json.message or "Unknown error"))
    end
end

return M
