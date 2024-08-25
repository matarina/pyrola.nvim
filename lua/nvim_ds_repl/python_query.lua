local ltn12 = require("ltn12")
local http = require("socket.http") 
local cjson = require("cjson")
local M = {}

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

function M.query_global(port)
    local global_vars = send_request("/query_global", port)
    if global_vars then
        local info = vim.inspect(global_vars)
        local cleaned_info = process_info_string(info)
        
        vim.lsp.util.open_floating_preview({cleaned_info}, "markdown", { border = "rounded" })
    else
        print("Failed to query global variables.")
    end
end


function M.inspect(var_name, port)
    local path = "/inspect_var?name=" .. var_name
    local var_info = send_request(path, port)
        if var_info then
        local info = vim.inspect(var_info)
        local cleaned_info = process_info_string(info)
        
        vim.lsp.util.open_floating_preview({cleaned_info}, "markdown", { border = "rounded" })
    else
        print("Failed to query global variables.")
    end

end

return M
