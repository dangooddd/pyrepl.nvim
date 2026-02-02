local M = {}

M.defaults = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    image_max_width_ratio = 0.4,
    image_max_height_ratio = 0.5,
}

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

function M.apply(opts)
    local config = vim.tbl_deep_extend("force", M.defaults, opts or {})
    config.split_ratio = clamp_ratio(config.split_ratio, M.defaults.split_ratio)
    return config
end

return M
