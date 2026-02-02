local M = {}

function M.normalize_path(path)
    if not path or path == "" then
        return nil
    end
    path = vim.fn.fnamemodify(path, ":p")
    path = path:gsub("/+$", "")
    return path
end

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

function M.is_valid_buf(bufnr)
    return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

function M.is_valid_win(winid)
    return winid and vim.api.nvim_win_is_valid(winid)
end

return M
