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
    cell_pattern = "^# %%%%.*$",
    python_path = "python",
    preferred_kernel = "python3",
    jupytext_hook = true,
}

local image_provider_cache
local message_prefix = "[pyrepl] "

---@type pyrepl.Config
local state = vim.deepcopy(defaults)

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

---@return pyrepl.Image
function M.get_image_provider()
    if not image_provider_cache then
        local ok, provider = pcall(require, "pyrepl.providers." .. state.image_provider)

        if ok then
            image_provider_cache = provider
        else
            image_provider_cache = require("pyrepl.providers." .. defaults.image_provider)
        end
    end

    return image_provider_cache
end

---@return string
function M.get_message_prefix()
    return message_prefix
end

---@return pyrepl.Config
function M.get_state()
    return state
end

---@param opts? pyrepl.ConfigOpts
function M.update_state(opts)
    state = vim.tbl_deep_extend("force", state, opts or {})

    local to_clip = {
        { "split_ratio", 0.1, 0.9 },
        { "image_width_ratio", 0.1, 0.9 },
        { "image_height_ratio", 0.1, 0.9 },
        { "image_max_history", 2, 100 },
    }

    for _, args in ipairs(to_clip) do
        local key, min, max = args[1], args[2], args[3]
        state[key] = clip_number(state[key], min, max, defaults[key] --[[@as number]])
    end

    -- reload image provider after config update
    image_provider_cache = nil
end

return M
