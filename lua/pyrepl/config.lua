local M = {}

---@type pyrepl.Config
local defaults = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    style_treesitter = true,
    image_max_history = 10,
    image_width_ratio = 0.5,
    image_height_ratio = 0.5,
    image_provider = "placeholders",
    block_pattern = "^# %%%%.*$",
    python_path = "python",
    preferred_kernel = "python3",
    jupytext_hook = true,
}

local provider_cache

---@type pyrepl.Config
M.state = vim.deepcopy(defaults)

-- should be used as prefix with error/notify messages
M.message = "[pyrepl] "

---@param num any
---@param min number
---@param max number
---@param fallback number
---@return number
local function clip_number(num, min, max, fallback)
    num = tonumber(num)
    if not num then
        return fallback
    end
    if num < min then
        return min
    end
    if num > max then
        return max
    end
    return num
end

function M.get_provider()
    if not provider_cache then
        local ok, provider = pcall(require, "pyrepl.providers." .. M.state.image_provider)

        if ok then
            provider_cache = provider
        else
            provider_cache = require("pyrepl.providers." .. defaults.image_provider)
        end
    end

    return provider_cache
end

---@param opts? pyrepl.ConfigOpts
function M.apply(opts)
    M.state = vim.tbl_deep_extend("force", M.state, opts or {})

    local to_clip = {
        { "split_ratio", 0.1, 0.9 },
        { "image_width_ratio", 0.1, 0.9 },
        { "image_height_ratio", 0.1, 0.9 },
        { "image_max_history", 2, 100 },
    }

    for _, args in ipairs(to_clip) do
        local key, min, max = args[1], args[2], args[3]
        M.state[key] = clip_number(M.state[key], min, max, defaults[key] --[[@as number]])
    end

    -- reload image provider after config update
    provider_cache = nil
end

return M
