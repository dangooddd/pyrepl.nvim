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

return M
