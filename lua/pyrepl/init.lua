local M = {}

local send = require("pyrepl.send")
local image = require("pyrepl.image")
local core = require("pyrepl.core")
local python = require("pyrepl.python")
local util = require("pyrepl.util")

---@type pyrepl.Config
local defaults = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    image_max_history = 10,
    image_width_ratio = 0.5,
    image_height_ratio = 0.5,
    block_pattern = "^# %%%%.*$",
    python_path = "python",
    preferred_kernel = "python3",
}

---@type pyrepl.Config
M.config = vim.deepcopy(defaults)

function M.open_repl()
    core.open_repl()
end

function M.hide_repl()
    core.hide_repl()
end

function M.close_repl()
    core.close_repl()
end

function M.open_images()
    image.open_images()
end

---@param tool string
function M.install_packages(tool)
    python.install_packages(tool)
end

function M.send_visual()
    if core.state then
        send.send_visual(core.state.chan)
        core.scroll_repl()
    end
end

function M.send_buffer()
    if core.state then
        send.send_buffer(core.state.chan)
        core.scroll_repl()
    end
end

function M.send_block()
    if core.state then
        send.send_block(core.state.chan, M.config.block_pattern)
        core.scroll_repl()
    end
end

---@param opts? pyrepl.ConfigOpts
---@return table
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", defaults, opts or {})

    local to_clip = {
        { "split_ratio",        0.1, 0.9 },
        { "image_width_ratio",  0.1, 0.9 },
        { "image_height_ratio", 0.1, 0.9 },
        { "image_max_history",  2,   100 }
    }

    for _, args in ipairs(to_clip) do
        local key, min, max = args[1], args[2], args[3]
        M.config[key] = util.clip(M.config[key], min, max, defaults[key])
    end

    local commands = {
        PyreplOpen = M.open_repl,
        PyreplHide = M.hide_repl,
        PyreplClose = M.close_repl,
        PyreplSendVisual = M.send_visual,
        PyreplSendBuffer = M.send_buffer,
        PyreplSendBlock = M.send_block,
        PyreplOpenImages = M.open_images,
    }

    for name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(name, callback, { force = true })
    end

    vim.api.nvim_create_user_command(
        "PyreplInstall",
        function(o) M.install_packages(o.args) end,
        { nargs = 1, complete = python.get_tools }
    )

    return M
end

return M
