local M = {}

---@type pyrepl.Config
M.defaults = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    image_width_ratio = 0.4,
    image_height_ratio = 0.5,
    filetypes = nil,
    block_pattern = "^# %%%%.*$",
}

---@param value any
---@param fallback number
---@return number
local function clamp_ratio(value, fallback)
    local num = tonumber(value)
    if not num then
        return fallback
    end
    if num < 0.1 then
        return 0.1
    end
    if num > 0.9 then
        return 0.9
    end
    return num
end

---@param opts pyrepl.ConfigOpts|nil
---@return pyrepl.Config
function M.apply(opts)
    local config = vim.tbl_deep_extend("force", M.defaults, opts or {})
    config.split_ratio = clamp_ratio(config.split_ratio, M.defaults.split_ratio)
    return config
end

return M
