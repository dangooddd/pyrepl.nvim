local M = {}

local config = require("pyrepl.config")
local send = require("pyrepl.send")
local image = require("pyrepl.image")
local core = require("pyrepl.core")

---@type pyrepl.Config
M.config = config.apply(nil)

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

function M.send_visual()
    if core.session then send.send_visual(session.chan) end
end

function M.send_buffer()
    if core.session then send.send_buffer(session.chan) end
end

function M.send_block()
    if core.session then send.send_block(session.chan) end
end

---@param opts pyrepl.ConfigOpts|nil
---@return table
function M.setup(opts)
    M.config = config.apply(opts)

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
        vim.api.nvim_create_user_commmand(name, callback)
    end

    return M
end

return M
