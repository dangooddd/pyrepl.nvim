local M = {}

function M.set(bufnr)
    if vim.b[bufnr].pyrepl_command_set then
        return
    end
    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLOpen", function()
        require("pyrepl").open_repl(bufnr)
    end, { nargs = 0 })
    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLHide", function()
        require("pyrepl").hide_repl(bufnr)
    end, { nargs = 0 })
    vim.api.nvim_buf_create_user_command(bufnr, "PyREPLClose", function()
        require("pyrepl").close_repl(bufnr)
    end, { nargs = 0 })
    vim.b[bufnr].pyrepl_command_set = true
end

return M
