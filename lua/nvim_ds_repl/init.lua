local api, ts = vim.api, vim.treesitter
local parsers = require 'nvim-treesitter.parsers'
local socket = require("socket")
local http = require("socket.http")
local r_query = require("nvim_ds_repl.r_query")
local python_query = require("nvim_ds_repl.python_query")

local M = {}
local M = {
    term = {opened = 0, winid = 0, bufid = 0, chanid = 0},
    port = (function()
        local server = assert(socket.bind("0.0.0.0", 0))
        local _, port = server:getsockname()
        server:close()
        return port
    end)()
}


local function get_plugin_path()
   return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
end

local function open_floating_window(content_lines)
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.min(#content_lines, math.floor(vim.o.lines * 0.8))
    local row, col = math.floor((vim.o.lines - height) / 2), math.floor((vim.o.columns - width) / 2)
    local bufid = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufid, 0, -1, false, content_lines)
    api.nvim_open_win(bufid, true, {
        relative = 'editor', width = width, height = height, row = row, col = col,
        style = 'minimal', border = 'rounded'
    })
end

function M.open_terminal()
    local filetype, bufid = vim.bo.filetype, vim.api.nvim_create_buf(false, true)
    vim.cmd("botright 60vsplit")
    vim.api.nvim_win_set_buf(0, bufid)
    local winid = vim.api.nvim_get_current_win()

    vim.loop.os_setenv("PORT", M.port)

    local term_cmd = ({
        r = "radian -q --no-restore --no-save --profile " .. get_plugin_path() .. "/R/server_init.R ",
        python = "ipython -i " .. get_plugin_path() .. "/python/server_init.py " .. M.port
    })[filetype]

    if term_cmd then
        local chanid = vim.fn.termopen(term_cmd)
        M.term = {opened = 1, winid = winid, bufid = bufid, chanid = chanid}
    else
        print("Filetype not supported")
    end
end


local function send_message(filetype, message)
    if M.term.opened == 0 then
        M.open_terminal()
        vim.wait(500)
    end

    local prefix = api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    if filetype == "r" then
        api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
    elseif filetype == "python" then
        local line_count = select(2, message:gsub("\n", "\n")) + 1
        if line_count > 1 then
            api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n\n")
        else
            api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
        end
    else
        print("Filetype not supported")
        return
    end

    vim.api.nvim_win_set_cursor(M.term.winid, {vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(M.term.winid)), 0})
end

local function move_cursor_to_next_line(end_row)
    local target_line = end_row + 2
    if target_line <= vim.api.nvim_buf_line_count(0) then
        vim.api.nvim_win_set_cursor(0, {target_line, 0})
    end
end

function M.send_statement_definition()
    local function find_and_return_node()
        local current_winid = api.nvim_get_current_win()
        local row = api.nvim_win_get_cursor(0)[1]

        -- Iterate through lines to find the first non-comment, non-empty line
        while row <= api.nvim_buf_line_count(0) do
            local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
            local col = line:find("%S")  -- Find the first non-whitespace character

            if col and line:sub(col, col) ~= "#" then
                api.nvim_win_set_cursor(0, {row, col - 1})
                break
            end
            row = row + 1
        end

        -- Parse the buffer with Tree-sitter
        local parser = parsers.get_parser(0)
        local root = parser:parse()[1]:root()
        local node = vim.treesitter.get_node()

        -- Helper function to check if a node is an immediate child of the root
        local function immediate_child(node)
            for child in root:iter_children() do
                if child:id() == node:id() then
                    return true
                end
            end
            return false
        end

        -- Traverse up the tree until we find an immediate child of the root
        while node and not immediate_child(node) do
            node = node:parent()
        end

        -- Return the node
        return node, current_winid
    end
    node, current_winid = find_and_return_node()

    local ok, msg = pcall(vim.treesitter.get_node_text, node, 0)

    if not ok then
        print("Error getting node text!")
        return
    end

    local end_row = select(3, node:range())
    if msg then
         send_message(vim.bo.filetype, msg)
    end
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
end

local function get_visual_selection()
    local start_pos, end_pos = vim.fn.getpos("v"), vim.fn.getcurpos()
    local start_line, end_line, start_col, end_col = start_pos[2], end_pos[2], start_pos[3], end_pos[3]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
        start_col, end_col = end_col, start_col
    end
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

    lines[1] = string.sub(lines[1], start_col, -1)
    if #lines == 1 then
        lines[#lines] = string.sub(lines[#lines], 1, end_col - start_col + 1)
    else
        lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end

    return table.concat(lines, '\n'), end_line
end

function M.send_visual_to_repl()
    local current_winid = vim.api.nvim_get_current_win()
    local msg, end_row = get_visual_selection()
    send_message(vim.bo.filetype, msg)
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

function M.query_global()
    (vim.bo.filetype == "r" and r_query or python_query).query_global(M.port)
end

function M.inspect()
    node = vim.treesitter.get_node()
    obj  = ts.get_node_text(node, 0)
    if vim.bo.filetype == "r" then
        r_query.inspect(obj, M.port)
    else
        python_query.inspect(obj, M.port)
    end
end


function M.table_view()
    node = vim.treesitter.get_node()
    obj  = ts.get_node_text(node, 0)
    if vim.bo.filetype == "r" then
        r_query.table_view(obj, M.port)
    else
        python_query.inspect(obj, M.port)
    end
end

return M


