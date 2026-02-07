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
local function validate_ratio(value, fallback)
    local num = tonumber(value)
    if not num then return fallback end
    if num < 0.1 then return 0.1 end
    if num > 0.9 then return 0.9 end
    return num
end

---@param opts pyrepl.ConfigOpts|nil
---@return pyrepl.Config
function M.apply(opts)
    local config = vim.tbl_deep_extend("force", M.defaults, opts or {})

    local ratios = {
        "split_ratio",
        "image_width_ratio",
        "image_height_ratio"
    }

    for _, key in ipairs(ratios) do
        config[key] = validate_ratio(config[key], M.default[key])
    end

    return config
end

return M
