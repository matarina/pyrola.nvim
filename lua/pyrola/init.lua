local api, ts = vim.api, vim.treesitter
local parsers = require 'nvim-treesitter.parsers'


-- Single M declaration with all initial properties
local M = {
    config = {
        kernel_map = {
            python = "python3",
            r = "ir",
	    cpp = "xcpp14"
        },
        split_horizen = false,
        split_ratio = 0.65
    },
    term = {
        opened = 0,
        winid = 0,
        bufid = 0,
        chanid = 0
    }
}



local function open_terminal()
    M.filetype = vim.bo.filetype
    local bufid = vim.api.nvim_create_buf(false, true)
    
    if M.config.split_horizen then
        local height = math.floor(vim.o.lines * M.config.split_ratio)
        split_cmd = "botright " .. height .. "split"
    else
        local width = math.floor(vim.o.columns * M.config.split_ratio)
        split_cmd = "botright " .. width .. "vsplit"
    end
    vim.cmd(split_cmd)
    
    vim.api.nvim_win_set_buf(0, bufid)
    local winid = vim.api.nvim_get_current_win()
    
    -- Map kernel name based on filetype
    local kernelname = M.config.kernel_map[M.filetype]
    M.connection_file_path = vim.fn.InitKernel(kernelname)
    
    local function get_plugin_path()
        local runtime_paths = vim.api.nvim_list_runtime_paths()
        for _, path in ipairs(runtime_paths) do
            if path:match("pyrola$") then
                return path
            end
        end
    end

    console_path = get_plugin_path()

    if M.connection_file_path then
        local term_cmd = string.format("python " .. console_path .. "/rplugin/python3/console.py --existing %s", M.connection_file_path)
        local chanid = vim.fn.termopen(term_cmd, {
            on_exit = function()
                vim.fn.ShutdownKernel(M.filetype, M.connection_file_path)
                os.remove(M.connection_file_path)
            end,
        })

        M.term = {
            opened = 1,
            winid = winid,
            bufid = bufid,
            chanid = chanid
        }


        vim.api.nvim_create_autocmd("VimLeavePre", {
            callback = function()
                vim.fn.ShutdownKernel(M.filetype, M.connection_file_path)
                os.remove(M.connection_file_path)
            end,
            once = true
        })

    else
        vim.api.nvim_err_writeln("Failed to initialize kernel")
    end
end



local function send_message(message)
    if M.term.opened == 0 then
        open_terminal()
        vim.wait(1)
    end


    local prefix = api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    if M.filetype == "python" then
	local line_count = select(2, message:gsub("\n", "\n")) + 1
        if line_count > 1 then
            api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n\n")
	else
	    api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
        end
    else
	    api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
    end


    vim.api.nvim_win_set_cursor(M.term.winid, {vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(M.term.winid)), 0})
end

local function move_cursor_to_next_line(end_row)
    local target_line = end_row + 2
    if target_line <= vim.api.nvim_buf_line_count(0) then
        vim.api.nvim_win_set_cursor(0, {target_line, 0})
    end
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



local function create_pretty_float(content)
    -- Convert string input to table of lines
    local content_lines = vim.split(content, "\n", { plain = true })
    
    -- Calculate dimensions
    local win_width = vim.api.nvim_get_option("columns")
    local win_height = vim.api.nvim_get_option("lines")
    
    -- Calculate max content width
    local max_content_width = 0
    for _, line in ipairs(content_lines) do
        max_content_width = math.max(max_content_width, vim.fn.strdisplaywidth(line))
    end
    
    -- Calculate window dimensions (as percentage of screen)
    local width = math.min(max_content_width + 2, math.floor(win_width * 0.8))
    local height = math.min(#content_lines, math.floor(win_height * 0.8))
    
    -- Calculate starting position
    local row = math.floor((win_height - height) / 2)
    local col = math.floor((win_width - width) / 2)
    
    -- Set up window options
    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Output ",
        title_pos = "center",
    }
    
    -- Create buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    
    -- Set buffer content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content_lines)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    
    -- Create window
    local winid = vim.api.nvim_open_win(bufnr, true, opts)
    
    -- Set window highlights
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#89b4fa', bg = '#1e1e2e' })
    vim.api.nvim_set_hl(0, 'FloatTitle', { fg = '#89b4fa', bg = '#1e1e2e' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = '#1e1e2e' })
    
    -- Apply window highlights
    vim.api.nvim_win_set_option(winid, 'winhl', 'Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle')
    
    -- Set keymaps
    local keymap_opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(winid, true) end, keymap_opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(winid, true) end, keymap_opts)
    
    -- Navigation keymaps
    vim.keymap.set('n', 'j', 'gj', keymap_opts)
    vim.keymap.set('n', 'k', 'gk', keymap_opts)
    vim.keymap.set('n', '<C-d>', '<C-d>zz', keymap_opts)
    vim.keymap.set('n', '<C-u>', '<C-u>zz', keymap_opts)
    vim.keymap.set('n', '<C-f>', '<C-f>zz', keymap_opts)
    vim.keymap.set('n', '<C-b>', '<C-b>zz', keymap_opts)
    
    -- Auto-focus the window
    vim.api.nvim_set_current_win(winid)
    
    -- Return window and buffer IDs for potential further manipulation
    return winid, bufnr
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    return M
end

function M.inspect()
    node = vim.treesitter.get_node()
    local obj  = ts.get_node_text(node, 0)
    local result = vim.fn.ExecuteKernelCode(M.filetype, M.connection_file_path, obj)
    result = result:gsub("\\n", "\n")
    create_pretty_float(result)
end


function M.send_visual_to_repl()
    local current_winid = vim.api.nvim_get_current_win()
    local msg, end_row = get_visual_selection()
    send_message(msg)
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
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
         send_message(msg)
    end
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
end


return M

