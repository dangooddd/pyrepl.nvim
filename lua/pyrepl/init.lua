local M = {}

local config = require("pyrepl.config")
local send = require("pyrepl.send")
local kernel = require("pyrepl.kernel")
local core = require("pyrepl.core")

---@type pyrepl.Config
local config_state = config.apply(nil)

local group = vim.api.nvim_create_augroup("Pyrepl", { clear = true })

---@param value pyrepl.Config
---@return pyrepl.Config
local function readonly_config(value)
    return setmetatable({}, {
        __index = value,
        __newindex = function() error("pyrepl: config is read-only") end,
        __metatable = false,
    })
end

---@return pyrepl.Config
function M.get_config()
    return readonly_config(config_state)
end

---@param buf integer|nil
function M.open_repl(buf)
    buf = buf or vim.api.nvim_get_current_buf()

    if not vim.b[buf].pyrepl_connection_file then
        kernel.prompt_kernel(buf)
    end

    if vim.b[buf].pyrepl_connection_file and vim.b[buf].pyrepl_kernel_name then
        core.open_repl_term(buf)
    end
end

---@param buf integer|nil
function M.hide_repl(buf)
    core.hide_repl(buf)
end

---@param buf integer|nil
function M.close_repl(buf)
    core.close_repl(buf)
end

---@param buf integer|nil
function M.send_visual(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not send.ready_to_send(buf) then return end
    send.send_visual(vim.b[buf].pyrepl_term_chan)
end

---@param buf integer|nil
function M.send_buffer(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not send.ready_to_send(buf) then return end
    send.send_buffer(vim.b[buf].pyrepl_term_chan)
end

---@param buf integer|nil
function M.send_block(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not send.ready_to_send(buf) then return end
    send.send_block(
        vim.b[buf].pyrepl_term_chan,
        M.get_config().block_pattern
    )
end

function M.open_images()
    require("pyrepl.image").open_images()
end

---@param buf integer
local function set_commands(buf)
    local commands = {
        PyreplOpen = function()
            M.open_repl(buf)
        end,
        PyreplHide = function()
            M.hide_repl(buf)
        end,
        PyreplClose = function()
            M.close_repl(buf)
        end,
        PyreplSendVisual = function()
            M.send_visual(buf)
        end,
        PyreplSendBuffer = function()
            M.send_buffer(buf)
        end,
        PyreplSendBlock = function()
            M.send_block(buf)
        end,
        PyreplOpenImages = function()
            M.open_images()
        end,
    }

    for name, callback in pairs(commands) do
        pcall(vim.api.nvim_buf_del_user_command, buf, name)
        vim.api.nvim_buf_create_user_command(buf, name, callback, { nargs = 0 })
    end
end

---@param opts pyrepl.ConfigOpts|nil
---@return table
function M.setup(opts)
    vim.env.PYTHONDONTWRITEBYTECODE = "1"
    config_state = config.apply(opts)
    local filetypes = config_state.filetypes

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = filetypes or "*",
        callback = function(args)
            set_commands(args.buf)
        end,
    })

    return M
end

return M
