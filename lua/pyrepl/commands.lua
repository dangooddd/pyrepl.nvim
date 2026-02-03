local M = {}

---@param bufnr integer
function M.set(bufnr)
    local commands = {
        PyREPLOpen = function()
            require("pyrepl").open_repl(bufnr)
        end,
        PyREPLHide = function()
            require("pyrepl").hide_repl(bufnr)
        end,
        PyREPLClose = function()
            require("pyrepl").close_repl(bufnr)
        end,
        PyREPLSendVisual = function()
            require("pyrepl").send_visual()
        end,
        PyREPLSendStatement = function()
            require("pyrepl").send_statement()
        end,
        PyREPLSendBuffer = function()
            require("pyrepl").send_buffer()
        end,
        PyREPLOpenImages = function()
            require("pyrepl").open_images()
        end,
    }

    for name, callback in pairs(commands) do
        pcall(vim.api.nvim_buf_del_user_command, bufnr, name)
        vim.api.nvim_buf_create_user_command(bufnr, name, callback, { nargs = 0 })
    end
end

return M
