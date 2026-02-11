local M = {}

M.msg = "(pyrepl) "

---@param buf any
function M.is_valid_buf(buf)
    return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

---@param win any
function M.is_valid_win(win)
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

---@param num any
---@param min number
---@param max number
---@param fallback number
---@return number
function M.clip(num, min, max, fallback)
    num = tonumber(num)
    if not num then return fallback end
    if num < min then return min end
    if num > max then return max end
    return num
end

---@return integer
---@return integer
function M.get_visual_range()
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    if (start_pos[1] == 0 and start_pos[2] == 0)
        or (end_pos[1] == 0 and end_pos[2] == 0)
    then
        return 0, 0
    end

    local start_line, end_line = start_pos[1], end_pos[1]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    return start_line, end_line
end

---@param block_pattern string
---@return integer
---@return integer
function M.get_block_range(block_pattern)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return 0, 0 end

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

    if start_line > end_line then return 0, 0 end
    return start_line, end_line
end

return M
