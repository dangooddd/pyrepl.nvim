local M = {}

function M.set(bufnr)
    pcall(vim.api.nvim_buf_del_user_command, bufnr, "PyREPLOpen")
    pcall(vim.api.nvim_buf_del_user_command, bufnr, "PyREPLHide")
    pcall(vim.api.nvim_buf_del_user_command, bufnr, "PyREPLClose")

    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLOpen", function()
        require("pyrepl").open_repl(bufnr)
    end, { nargs = 0 })
    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLHide", function()
        require("pyrepl").hide_repl(bufnr)
    end, { nargs = 0 })
    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLClose", function()
        require("pyrepl").close_repl(bufnr)
    end, { nargs = 0 })
end

return M
