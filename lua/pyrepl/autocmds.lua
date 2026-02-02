local state = require("pyrepl.state")
local commands = require("pyrepl.commands")
local terminal = require("pyrepl.terminal")
local kernel = require("pyrepl.kernel")

local M = {}

---@param bufnr integer
local function attach_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    commands.set(bufnr)

    if vim.b[bufnr].pyrepl_attached then
        return
    end
    vim.b[bufnr].pyrepl_attached = true

    vim.api.nvim_buf_attach(bufnr, false, {
        on_detach = function()
            vim.schedule(function()
                local session = state.get_session(bufnr, false)
                if not session or session.closing then
                    return
                end
                session.closing = true
                terminal.close(session)
                kernel.shutdown_kernel(session)
                state.clear_session(bufnr)
            end)
        end,
    })
end

function M.setup()
    local group = vim.api.nvim_create_augroup("Pyrepl", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "*",
        callback = function(args)
            attach_buffer(args.buf)
        end,
    })
end

function M.attach_existing()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        attach_buffer(bufnr)
    end
end

function M.setup_vimleave()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            for bufnr, session in pairs(state.state.sessions) do
                terminal.close(session)
                kernel.shutdown_kernel(session)
                state.clear_session(bufnr)
            end
        end,
        once = true,
    })
end

return M
