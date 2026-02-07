local kernel = require("pyrepl.kernel")

local M = {}

---@type pyrepl.Session|nil
M.session = nil

---@return integer
local function open_scratch_win()
    local config = require("pyrepl").config

    if config.split_horizontal then
        local height = math.floor(vim.o.lines * config.split_ratio)
        vim.cmd("botright " .. height .. "split")
    else
        local width = math.floor(vim.o.columns * config.split_ratio)
        vim.cmd("botright " .. width .. "vsplit")
    end

    return vim.api.nvim_get_current_win()
end

---@param buf integer
local function setup_buf_autocmd(buf)
    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = buf,
        callback = function() M.close_repl() end,
        once = true,
    })
end

---@param win integer
local function setup_win_autocmd(win)
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function() M.hide_repl() end,
        once = true,
    })
end

local function open_hidden_repl()
    if not M.session then return end
    if M.session.win then return end

    local win = vim.api.nvim_get_current_win()
    M.session.win = open_scratch_win()
    vim.api.nvim_win_set_buf(M.session.win, M.session.buf)
    vim.api.nvim_set_current_win(win)
    setup_win_autocmd(M.session.win)
end

local function open_new_repl(kernel_name)
    if M.session then return end

    local connection_file = kernel.init_kernel(kernel_name)
    local python_path = kernel.get_python_path()
    local console_path = kernel.get_console_path()
    local style = require("pyrepl").config.style or "default"
    local nvim_socket = vim.v.servername

    if not connection_file then
        vim.notify(
            "Pyrepl: Failed to init kernel.",
            vim.log.levels.ERROR
        )
        return
    end

    if not python_path then
        vim.notify(
            "Pyrepl: Python executable not found.",
            vim.log.levels.ERROR
        )
        return
    end

    if not console_path then
        vim.notify(
            "Pyrepl: Console not found. Run :UpdateRemotePlugins and restart.",
            vim.log.levels.ERROR
        )
        return
    end

    local buf = vim.api.nvim_create_buf(false, true)
    local buf_name = string.format("pyrepl: %s", kernel_name)
    vim.bo[buf].bufhidden = "hide"
    vim.api.nvim_buf_set_name(buf, buf_name)
    setup_buf_autocmd(buf)

    local current_win = vim.api.nvim_get_current_win()
    local win = open_scratch_win()
    vim.api.nvim_win_set_buf(win, buf)
    setup_win_autocmd(win)

    local cmd = {
        python_path,
        console_path,
        "--existing",
        connection_file,
        "--pygments-style",
        tostring(style),
    }

    local chan = vim.fn.jobstart(cmd, {
        term = true,
        pty = true,
        env = { NVIM = nvim_socket, PYTHONDONTWRITEBYTECODE = "1" },
        on_exit = function() M.close_repl() end,
    })

    M.session = {
        buf = buf,
        win = win,
        chan = chan,
        connection_file = connection_file,
        kernel_name = kernel_name,
    }

    vim.api.nvim_set_current_win(current_win)
end

--- Open hidden REPL or initialize new session
function M.open_repl()
    if M.session then
        open_hidden_repl()
        return
    end

    local on_choice = function(kernel_name)
        open_new_repl(kernel_name)
    end

    kernel.prompt_kernel(on_choice)
end

--- Hide window with REPL terminal
function M.hide_repl()
    if M.session and M.session.win then
        pcall(vim.api.nvim_win_close, M.session.win, true)
        M.session.win = nil
    end
end

--- Close session entirely
function M.close_repl()
    if not M.session then return end

    M.hide_repl()
    local connection_file = M.session.connection_file
    pcall(vim.fn.jobstop, M.session.chan)
    pcall(vim.cmd.bdelete, { M.session.buf, bang = true })
    vim.schedule(function() kernel.shutdown_kernel(connection_file) end)
    M.session = nil
end

return M
