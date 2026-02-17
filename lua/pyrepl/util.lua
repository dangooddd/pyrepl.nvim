local M = {}

M.msg = "[pyrepl] "

---@param num any
---@param min number
---@param max number
---@param fallback number
---@return number
function M.clip_number(num, min, max, fallback)
    num = tonumber(num)
    if not num then return fallback end
    if num < min then return min end
    if num > max then return max end
    return num
end

---@param path string
function M.edit_relative(path)
    local relative = vim.fn.fnamemodify(path, ":.")
    vim.cmd.edit(vim.fn.fnameescape(relative))
end

---@param buf integer
function M.get_buf_text(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return table.concat(lines, "\n")
end

return M
