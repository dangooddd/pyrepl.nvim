local M = {}

local config = require("pyrepl.config")
local autocmds = require("pyrepl.autocmds")
local state = require("pyrepl.state")
local kernel = require("pyrepl.kernel")
local terminal = require("pyrepl.terminal")
local send = require("pyrepl.send")

---@type pyrepl.Config
M.config = config.apply(nil)

---@param opts pyrepl.ConfigOpts|nil
---@return table
function M.setup(opts)
    vim.env.PYTHONDONTWRITEBYTECODE = "1"
    M.config = config.apply(opts)
    autocmds.setup()
    autocmds.attach_existing()
    autocmds.setup_vimleave()
    return M
end

---@param bufnr integer|nil
function M.open_repl(bufnr)
    local target_buf = bufnr or vim.api.nvim_get_current_buf()

    local python_host = kernel.ensure_python()
    if not python_host then
        return
    end

    local session = state.get_session(target_buf, true)
    kernel.ensure_kernel(session, function(ok)
        if not ok then
            return
        end
        terminal.open(session, python_host, M.config)
    end)
end

---@param bufnr integer|nil
function M.hide_repl(bufnr)
    local target_buf = bufnr or vim.api.nvim_get_current_buf()
    local session = state.get_session(target_buf, false)
    terminal.hide(session)
end

---@param bufnr integer|nil
function M.close_repl(bufnr)
    local target_buf = bufnr or vim.api.nvim_get_current_buf()
    local session = state.get_session(target_buf, false)
    terminal.close(session)
    kernel.shutdown_kernel(session)
    state.clear_session(target_buf)
end

function M.send_visual()
    local session = state.get_session(0, false)
    if not session then
        return
    end
    send.send_visual(session)
end

function M.send_buffer()
    local session = state.get_session(0, false)
    if not session then
        return
    end
    send.send_buffer(session)
end

function M.send_statement()
    local session = state.get_session(0, false)
    if not session then
        return
    end
    send.send_statement(session)
end

---@param session_id integer|nil
function M._on_repl_ready(session_id)
    send.on_repl_ready(session_id)
end

function M.open_images()
    require("pyrepl.image").open_images()
end

return M
