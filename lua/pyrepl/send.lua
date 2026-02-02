local state = require("pyrepl.state")
local util = require("pyrepl.util")

local M = {}

function M.repl_ready(session)
    return session
        and session.connection_file
        and session.term_chan
        and session.term_chan ~= 0
        and session.term_buf
        and util.is_valid_buf(session.term_buf)
end

local function normalize_python_message(msg)
    local lines = vim.split(msg, "\n", { plain = true })
    if #lines <= 1 then
        return msg
    end

    local function ends_with_colon(line)
        local trimmed = line:gsub("%s+$", "")
        if trimmed == "" then
            return false
        end
        local comment_pos = trimmed:find("#")
        if comment_pos then
            trimmed = trimmed:sub(1, comment_pos - 1):gsub("%s+$", "")
        end
        return trimmed:sub(-1) == ":"
    end

    local function is_continuation(line)
        local trimmed = line:gsub("^%s+", "")
        return trimmed:match("^(else|elif|except|finally)%f[%w]")
    end

    local out = {}
    local in_top_block = false

    for _, line in ipairs(lines) do
        local indent = line:match("^(%s*)") or ""
        local trimmed = line:gsub("%s+$", "")
        local is_blank = trimmed == ""
        local is_top = #indent == 0
        local continuation = is_top and is_continuation(line)

        if is_top and not is_blank and in_top_block and not continuation then
            table.insert(out, "")
            in_top_block = false
        end

        table.insert(out, line)

        if is_top and ends_with_colon(line) then
            in_top_block = true
        end
    end

    if in_top_block then
        local last = out[#out] or ""
        if not last:match("^%s*$") then
            table.insert(out, "")
        end
    end

    return table.concat(out, "\n")
end

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

    if util.is_valid_win(session.term_win) then
        vim.api.nvim_win_set_cursor(
            session.term_win,
            { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(session.term_win)), 0 }
        )
    end
end

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

local function send_message(session, message)
    if not message or message == "" then
        return
    end
    table.insert(session.send_queue, message)
    flush_send_queue(session)
end

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

local function get_visual_selection()
    local start_pos, end_pos = vim.fn.getpos("v"), vim.fn.getcurpos()
    local start_line, end_line = start_pos[2], end_pos[2]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n"), end_line
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

function M.send_visual(session)
    if not M.repl_ready(session) then
        return
    end

    local current_winid = vim.api.nvim_get_current_win()
    local msg, end_row = get_visual_selection()
    send_message(session, msg)
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

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
    if util.is_valid_win(current_winid) then
        vim.api.nvim_set_current_win(current_winid)
    end
end

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
