local M = {}

local config = require("pyrepl.config")

local compound_top_level_nodes = {
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

---Normalize pasted Python so multi-block code executes correctly.
---@param msg string
---@return string
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
    if #top_nodes == 0 then
        return msg
    end

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

    ---@param last_row integer
    ---@param next_start integer
    ---@return boolean
    local function has_blank_line_between(last_row, next_start)
        for row = last_row + 1, next_start - 1 do
            local line = lines[row + 1]
            if is_blank_line(line) then
                return true
            end
        end
        return false
    end

    local insert_after = {}
    local has_compound = false
    for idx, node in ipairs(top_nodes) do
        if compound_top_level_nodes[node:type()] then
            has_compound = true

            local last_row = node_last_row(node)
            local next_node = top_nodes[idx + 1]
            local next_start = next_node and select(1, next_node:range()) or #lines

            if next_start > last_row and not has_blank_line_between(last_row, next_start) then
                insert_after[last_row + 1] = true
            end
        end
    end

    if has_compound and not is_blank_line(lines[#lines]) then
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

---Send code to the REPL using bracketed paste.
---@param chan integer
---@param message string
local function raw_send_message(chan, message)
    if message == "" then
        return
    end
    local prefix = vim.api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = vim.api.nvim_replace_termcodes("<esc>[201~", true, false, true)
    local normalized = normalize_python_message(message)
    vim.api.nvim_chan_send(chan, prefix .. normalized .. suffix .. "\n")
end

---@param buf integer
---@return integer|nil
---@return integer|nil
local function get_visual_range(buf)
    local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
    local end_pos = vim.api.nvim_buf_get_mark(buf, ">")

    if (start_pos[1] == 0 and start_pos[2] == 0) or (end_pos[1] == 0 and end_pos[2] == 0) then
        return nil, nil
    end

    local start_idx, end_idx = start_pos[1], end_pos[1]
    if start_idx > end_idx then
        start_idx, end_idx = end_idx, start_idx
    end

    return start_idx, end_idx
end

---@param buf integer
---@param idx integer
---@param cell_pattern string
---@return integer|nil
---@return integer|nil
local function get_cell_range(buf, idx, cell_pattern)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines == 0 then
        return nil, nil
    end

    -- block start
    local start_idx = 1
    for i = idx, 1, -1 do
        if lines[i]:match(cell_pattern) then
            start_idx = i + 1
            break
        end
    end

    -- block end
    local end_idx = #lines
    for i = idx + 1, #lines do
        if lines[i]:match(cell_pattern) then
            end_idx = i - 1
            break
        end
    end

    if start_idx > end_idx then
        return nil, nil
    end
    return start_idx, end_idx
end

---@param buf integer
---@param chan integer
function M.send_buffer(buf, chan)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local msg = table.concat(lines, "\n")
    raw_send_message(chan, msg)
end

---@param buf integer
---@param chan integer
function M.send_visual(buf, chan)
    local start_idx, end_idx = get_visual_range(buf)

    if start_idx and end_idx then
        local lines = vim.api.nvim_buf_get_lines(buf, start_idx - 1, end_idx, false)
        local msg = table.concat(lines, "\n")
        raw_send_message(chan, msg)
    end
end

---@param buf integer
---@param chan integer
---@param idx integer
---@param cell_pattern string
function M.send_cell(buf, chan, idx, cell_pattern)
    local start_idx, end_idx = get_cell_range(buf, idx, cell_pattern)

    if start_idx and end_idx then
        local lines = vim.api.nvim_buf_get_lines(buf, start_idx - 1, end_idx, false)
        local msg = table.concat(lines, "\n")
        raw_send_message(chan, msg)
    end
end

---@param win integer
function M.step_cell_forward(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local _, end_idx = get_cell_range(buf, idx, config.get_state().cell_pattern)

    if end_idx then
        vim.api.nvim_win_call(win, function()
            vim.cmd.normal({ tostring(end_idx + 1) .. "gg^", bang = true })
        end)
    end
end

---@param win integer
function M.step_cell_backward(win)
    local buf = vim.api.nvim_win_get_buf(win)
    local idx = vim.api.nvim_win_get_cursor(win)[1]
    local line = vim.api.nvim_buf_get_lines(buf, idx - 1, idx, false)[1]
    local cell_pattern = require("pyrepl.config").get_state().cell_pattern

    if line:match(cell_pattern) then
        idx = math.max(1, idx - 1)
    end

    local start_idx, _ = get_cell_range(buf, idx, cell_pattern)

    if start_idx then
        vim.api.nvim_win_call(win, function()
            vim.cmd.normal({ tostring(math.max(0, start_idx - 1)) .. "gg^", bang = true })
        end)
    end
end

return M
