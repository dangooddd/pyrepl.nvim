local M = {}

---@param bufnr integer
function M.set(bufnr)
    local commands = {
        PyreplOpen = function()
            require("pyrepl").open_repl(bufnr)
        end,
        PyreplHide = function()
            require("pyrepl").hide_repl(bufnr)
        end,
        PyreplClose = function()
            require("pyrepl").close_repl(bufnr)
        end,
        PyreplSendVisual = function()
            require("pyrepl").send_visual()
        end,
        PyreplSendStatement = function()
            require("pyrepl").send_statement()
        end,
        PyreplSendBuffer = function()
            require("pyrepl").send_buffer()
        end,
        PyreplOpenImages = function()
            require("pyrepl").open_images()
        end,
    }

    for name, callback in pairs(commands) do
        pcall(vim.api.nvim_buf_del_user_command, bufnr, name)
        vim.api.nvim_buf_create_user_command(bufnr, name, callback, { nargs = 0 })
    end
end

return M
