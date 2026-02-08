local M = {}

--- Normalize pasted Python so multi-block code executes correctly in a REPL.
---@param msg string
---@return string
local function normalize_python_message(msg)
    -- insert blank lines after top-level compound statements so pasted code executes as separate blocks in a repl
    local lines = vim.split(msg, "\n", { plain = true, trimempty = false })
    if #lines <= 1 then return msg end

    local ok_parser, parser = pcall(vim.treesitter.get_string_parser, msg, "python")
    if not ok_parser or not parser then return msg end

    local tree = parser:parse()[1]
    if not tree then return msg end

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

    ---@param node TSNode
    ---@return integer
    local function node_last_row(node)
        local _, _, end_row, end_col = node:range()
        if end_col == 0 then
            return math.max(end_row - 1, 0)
        end
        return end_row
    end

    ---@param line string|nil
    ---@return boolean
    local function is_blank_line(line)
        return (line and line:match("^%s*$")) ~= nil
    end

    ---@param last_row0 integer
    ---@param next_start0 integer
    ---@return boolean
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

    if next(insert_after) == nil then return msg end

    local out = {}
    for i, line in ipairs(lines) do
        table.insert(out, line)
        if insert_after[i] then
            table.insert(out, "")
        end
    end

    while #out > 0 and out[1]:match("^%s*$") do
        table.remove(out, 1)
    end

    while #out > 0 and out[#out]:match("^%s*$") do
        table.remove(out, #out)
    end

    return table.concat(out, "\n")
end

--- Send code to the REPL using bracketed paste mode.
---@param chan? integer
---@param message? string
local function raw_send_message(chan, message)
    if not chan then return end
    if not message or message == "" then return end

    local prefix = vim.api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = vim.api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    local normalized = normalize_python_message(message)
    vim.api.nvim_chan_send(chan, prefix .. normalized .. suffix .. "\n")
end


---@return string|nil
local function get_visual_selection()
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    if (start_pos[1] == 0 and start_pos[2] == 0)
        or (end_pos[1] == 0 and end_pos[2] == 0)
    then
        return nil
    end

    local start_line, end_line = start_pos[1], end_pos[1]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n")
end

---@param chan? integer
function M.send_visual(chan)
    if not chan then return end
    local msg = get_visual_selection()
    if not msg then return end
    raw_send_message(chan, msg)
end

---@param chan? integer
function M.send_buffer(chan)
    if not chan then return end
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return end
    local msg = table.concat(lines, "\n")
    raw_send_message(chan, msg)
end

---@param chan? integer
---@param block_pattern? string
function M.send_block(chan, block_pattern)
    if not chan then return end
    block_pattern = block_pattern or "^# %%%%.*$"

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines == 0 then return end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    -- block start
    local start_line = 1
    for i = cursor_line, 1, -1 do
        if lines[i]:match(block_pattern) then
            start_line = i + 1
            break
        end
    end

    -- block end
    local end_line = #lines
    for i = cursor_line + 1, #lines do
        if lines[i]:match(block_pattern) then
            end_line = i - 1
            break
        end
    end

    if start_line > end_line then return end
    local block_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    if #block_lines == 0 then return end
    raw_send_message(chan, table.concat(block_lines, "\n"))
end

return M
