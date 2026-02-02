local state = require("pyrepl.state")
local M = {}

---@param session pyrepl.Session|nil
---@return boolean
function M.repl_ready(session)
    return session
        and session.connection_file
        and session.term_chan
        and session.term_chan ~= 0
        and session.term_buf
        and vim.api.nvim_buf_is_valid(session.term_buf)
end

local function normalize_python_message(msg)
    local lines = vim.split(msg, "\n", { plain = true, trimempty = false })
    if #lines <= 1 then
        return msg
    end

    local ok_parser, parser = pcall(vim.treesitter.get_string_parser, msg, "python")
    if not ok_parser or not parser then
        return msg
    end

    local tree = parser:parse()[1]
    if not tree then
        return msg
    end

    local root = tree:root()
    local top_nodes = {}
    for node in root:iter_children() do
        if node:named() and node:type() ~= "ERROR" then
            table.insert(top_nodes, node)
        end
    end

    local block_types = {
        async_for_statement = true,
        async_function_definition = true,
        async_with_statement = true,
        class_definition = true,
        decorated_definition = true,
        for_statement = true,
        function_definition = true,
        if_statement = true,
        match_statement = true,
        try_statement = true,
        while_statement = true,
        with_statement = true,
    }

    local function node_last_row(node)
        local _, _, end_row, end_col = node:range()
        if end_col == 0 then
            return math.max(end_row - 1, 0)
        end
        return end_row
    end

    local function is_blank_line(line)
        return line and line:match("^%s*$") ~= nil
    end

    local function has_blank_line_between(last_row0, next_start0)
        for row0 = last_row0 + 1, next_start0 - 1 do
            local line = lines[row0 + 1]
            if is_blank_line(line) then
                return true
            end
        end
        return false
    end

    local insert_after = {}
    local has_block = false
    for idx = 1, #top_nodes - 1 do
        local node = top_nodes[idx]
        if block_types[node:type()] then
            has_block = true
            local last_row0 = node_last_row(node)
            local next_start0 = select(1, top_nodes[idx + 1]:range())
            if next_start0 > last_row0 and not has_blank_line_between(last_row0, next_start0) then
                insert_after[last_row0 + 1] = true
            end
        end
    end

    local last_node = top_nodes[#top_nodes]
    if last_node and block_types[last_node:type()] then
        has_block = true
        local last_row0 = node_last_row(last_node)
        if last_row0 < #lines - 1 then
            if not has_blank_line_between(last_row0, #lines) then
                insert_after[last_row0 + 1] = true
            end
        else
            insert_after[#lines] = true
        end
    end

    if has_block and not is_blank_line(lines[#lines]) then
        insert_after[#lines] = true
    end

    if next(insert_after) == nil then
        return msg
    end

    local out = {}
    for i, line in ipairs(lines) do
        table.insert(out, line)
        if insert_after[i] then
            table.insert(out, "")
        end
    end

    return table.concat(out, "\n")
end

---@param session pyrepl.Session
---@param message string
local function raw_send_message(session, message)
    if not M.repl_ready(session) then
        return
    end

    if not message or message == "" then
        return
    end

    local prefix = vim.api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = vim.api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    local normalized = normalize_python_message(message)
    vim.api.nvim_chan_send(session.term_chan, prefix .. normalized .. suffix .. "\n")

    if session.term_win and vim.api.nvim_win_is_valid(session.term_win) then
        vim.api.nvim_win_set_cursor(
            session.term_win,
            { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(session.term_win)), 0 }
        )
    end
end

---@param session pyrepl.Session
local function flush_send_queue(session)
    if session.send_flushing then
        return
    end

    if not session.repl_ready then
        return
    end

    if #session.send_queue == 0 then
        return
    end

    local next_message = table.remove(session.send_queue, 1)
    session.send_flushing = true
    session.repl_ready = false
    raw_send_message(session, next_message)
    session.send_flushing = false
end

---@param session pyrepl.Session
---@param message string
local function send_message(session, message)
    if not message or message == "" then
        return
    end
    table.insert(session.send_queue, message)
    flush_send_queue(session)
end

---@param session_id integer|nil
function M.on_repl_ready(session_id)
    local session = nil
    if session_id then
        session = state.get_session(session_id, false)
    else
        for _, candidate in pairs(state.state.sessions) do
            if candidate.term_chan and not candidate.repl_ready then
                session = candidate
                break
            end
        end
    end

    if not session then
        return
    end

    session.repl_ready = true
    flush_send_queue(session)
end

---@param end_row integer
local function move_cursor_to_next_line(end_row)
    local comment_char = "#"
    local line_count = vim.api.nvim_buf_line_count(0)
    local row = end_row + 2

    while row <= line_count do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        local col = line:find("%S")
        if col and line:sub(col, col + (#comment_char - 1)) ~= comment_char then
            vim.api.nvim_win_set_cursor(0, { row, 0 })
            return
        end
        row = row + 1
    end
end

---@return string|nil
---@return integer|nil
---@return string|nil
local function get_visual_selection()
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")
    if not start_pos or start_pos[1] == 0 or not end_pos or end_pos[1] == 0 then
        return nil, nil, "no_mark"
    end
    local start_line, end_line = start_pos[1], end_pos[1]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n"), end_line, nil
end

local function handle_cursor_move()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local comment_char = "#"

    while row <= vim.api.nvim_buf_line_count(0) do
        local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local col = line:find("%S")
        if not col or line:sub(col, col + (#comment_char - 1)) == comment_char then
            row = row + 1
            pcall(function()
                vim.api.nvim_win_set_cursor(0, { row, 0 })
            end)
        else
            local cursor_pos = vim.api.nvim_win_get_cursor(0)
            local current_col = cursor_pos[2] + 1
            local char_under_cursor = line:sub(current_col, current_col)
            if not char_under_cursor:match("%s") then
                break
            end

            local backward_pos, forward_pos
            for i = current_col - 1, 1, -1 do
                if not line:sub(i, i):match("%s") then
                    backward_pos = i
                    break
                end
            end

            for i = current_col + 1, #line do
                if not line:sub(i, i):match("%s") then
                    forward_pos = i
                    break
                end
            end

            local backward_dist = backward_pos and (current_col - backward_pos) or math.huge
            local forward_dist = forward_pos and (forward_pos - current_col) or math.huge

            if backward_dist < forward_dist then
                vim.api.nvim_win_set_cursor(0, { row, backward_pos - 1 })
            elseif forward_dist <= backward_dist then
                vim.api.nvim_win_set_cursor(0, { row, forward_pos - 1 })
            end
            break
        end
    end
end

---@param session pyrepl.Session|nil
function M.send_visual(session)
    if not M.repl_ready(session) then
        return
    end

    local current_winid = vim.api.nvim_get_current_win()
    local msg, end_row, err = get_visual_selection()
    if not msg or msg == "" then
        if err == "no_mark" then
            vim.notify("PyREPL: Visual selection not available. Invoke from Visual mode.", vim.log.levels.WARN)
        end
        return
    end
    send_message(session, msg)
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

---@param session pyrepl.Session|nil
function M.send_buffer(session)
    if not M.repl_ready(session) then
        return
    end

    local current_winid = vim.api.nvim_get_current_win()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if not lines or #lines == 0 then
        return
    end

    local msg = table.concat(lines, "\n")
    if msg == "" then
        return
    end

    send_message(session, msg)
    vim.api.nvim_set_current_win(current_winid)
end

---@param session pyrepl.Session|nil
function M.send_statement(session)
    if not M.repl_ready(session) then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
        return
    end

    handle_cursor_move()
    local ok_parser, parser = pcall(vim.treesitter.get_parser, 0)
    if not ok_parser or not parser then
        vim.notify("PyREPL: Tree-sitter parser not available for this buffer.", vim.log.levels.WARN)
        return
    end

    local tree = parser:parse()[1]
    if not tree then
        print("No valid node found!")
        return
    end

    local root = tree:root()
    local function node_at_cursor()
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        row = row - 1
        local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ""
        local max_col = math.max(#line - 1, 0)
        if col > max_col then
            col = max_col
        end
        local node = root:named_descendant_for_range(row, col, row, col)
        if node == root then
            node = nil
        end
        if not node and #line > 0 then
            node = root:named_descendant_for_range(row, 0, row, max_col)
            if node == root then
                node = nil
            end
        end
        return node
    end

    local node = node_at_cursor()
    local current_winid = vim.api.nvim_get_current_win()

    local function find_and_return_node()
        local function immediate_child(child)
            for c in root:iter_children() do
                if c:id() == child:id() then
                    return true
                end
            end
            return false
        end

        while node and not immediate_child(node) do
            node = node:parent()
        end
        return node, current_winid
    end

    local found_node, winid = find_and_return_node()
    if not found_node then
        print("No valid node found!")
        return
    end

    local ok, msg = pcall(vim.treesitter.get_node_text, found_node, 0)
    if not ok then
        print("Error getting node text!")
        return
    end

    local end_row = select(3, found_node:range())
    if msg then
        send_message(session, msg)
    end
    vim.api.nvim_set_current_win(winid)
    move_cursor_to_next_line(end_row)
end

return M
