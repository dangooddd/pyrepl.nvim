local M = {}

---@param path string|nil
---@return string|nil
function M.normalize_path(path)
    if not path or path == "" then
        return nil
    end
    path = vim.fn.fnamemodify(path, ":p")
    path = path:gsub("/+$", "")
    return path
end

---@param path string|nil
---@param prefix string|nil
---@return boolean
function M.has_path_prefix(path, prefix)
    if not path or not prefix then
        return false
    end

    if path == prefix then
        return true
    end

    local sep = "/"
    if prefix:sub(-1) ~= sep then
        prefix = prefix .. sep
    end

    return path:sub(1, #prefix) == prefix
end

---@return string|nil
function M.get_active_venv()
    local venv = vim.env.VIRTUAL_ENV
    if venv and venv ~= "" then
        return venv
    end

    local conda = vim.env.CONDA_PREFIX
    if conda and conda ~= "" then
        return conda
    end

    return nil
end

return M
