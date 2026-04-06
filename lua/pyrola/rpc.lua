--- Pyrola RPC module.
--- Manages a persistent Python server process and provides synchronous
--- JSON-over-stdin/stdout communication.

local fn = vim.fn

local M = {}

local _job_id = nil
local _next_id = 0
local _pending = {} -- id -> {result=..., err=..., done=bool}
local _stdout_buf = "" -- partial line buffer
local _stderr_buf = ""
local _last_error = nil

local function handle_stdout_line(line)
    if not line or line == "" then
        return
    end
    local ok, resp = pcall(vim.json.decode, line)
    if ok and resp and resp.id ~= nil then
        local cb = _pending[resp.id]
        if cb then
            cb.result = resp.result
            cb.err = resp.error
            cb.done = true
        end
    end
end

--- Start the Python server process.
---@param python_executable string  path to python3
---@param plugin_path string  path to pyrola.nvim root
---@return boolean success
function M.start(python_executable, plugin_path)
    if _job_id and _job_id > 0 then
        return true
    end

    _last_error = nil
    _stderr_buf = ""
    local server_script = plugin_path .. "/rplugin/python3/server.py"
    _job_id = fn.jobstart({ python_executable, server_script }, {
        cwd = plugin_path .. "/rplugin/python3",
        on_stdout = function(_, data, _)
            if not data then
                return
            end
            for i, chunk in ipairs(data) do
                local is_last = i == #data
                if is_last and chunk ~= "" then
                    _stdout_buf = _stdout_buf .. chunk
                else
                    local line = _stdout_buf .. chunk
                    _stdout_buf = ""
                    handle_stdout_line(line)
                end
            end
        end,
        on_stderr = function(_, data, _)
            if not data then
                return
            end
            for _, chunk in ipairs(data) do
                if chunk and chunk ~= "" then
                    _stderr_buf = _stderr_buf .. chunk .. "\n"
                end
            end
        end,
        on_exit = function(_, code, _)
            if code ~= 0 then
                local msg = _stderr_buf:gsub("%s+$", "")
                if msg == "" then
                    msg = string.format("server exited with code %d", code)
                end
                _last_error = msg
            end
            _job_id = nil
            _stdout_buf = ""
            _pending = {}
        end,
    })

    if not _job_id or _job_id <= 0 then
        _job_id = nil
        return false
    end
    return true
end

--- Send a request and wait synchronously for the response.
---@param method string  RPC method name
---@param params table   method parameters
---@param timeout_ms? number  timeout in milliseconds (default 10000)
---@return any result, string|nil err
function M.request(method, params, timeout_ms)
    timeout_ms = timeout_ms or 10000

    if not _job_id or _job_id <= 0 then
        return nil, _last_error or "server not running"
    end

    _next_id = _next_id + 1
    local id = _next_id

    local entry = { result = nil, err = nil, done = false }
    _pending[id] = entry

    local request = vim.json.encode({ id = id, method = method, params = params or {} })
    fn.chansend(_job_id, request .. "\n")

    -- Block until response arrives or timeout
    local ok = vim.wait(timeout_ms, function()
        return entry.done
    end, 10)

    _pending[id] = nil

    if not ok then
        if not _job_id or _job_id <= 0 then
            return nil, _last_error or "server exited before replying"
        end
        return nil, "request timed out"
    end

    if entry.err then
        return nil, entry.err
    end

    return entry.result, nil
end

--- Stop the server process.
function M.stop()
    if _job_id and _job_id > 0 then
        fn.jobstop(_job_id)
        _job_id = nil
    end
    _stdout_buf = ""
    _stderr_buf = ""
    _pending = {}
end

--- Check if the server is running.
---@return boolean
function M.is_running()
    return _job_id ~= nil and _job_id > 0
end

return M
