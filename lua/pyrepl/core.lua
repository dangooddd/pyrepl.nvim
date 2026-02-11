local M = {}

---@type pyrepl.ReplState|nil
M.state = nil

local python = require("pyrepl.python")
local util = require("pyrepl.util")

--- Create window according to current config.
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
    if not util.is_valid_buf(buf) then return end

    local group = vim.api.nvim_create_augroup(
        "PyreplBuf",
        { clear = false }
    )

    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = buf,
        callback = function() M.close_repl() end,
        once = true,
    })
end

---@param win integer
local function setup_win_autocmd(win)
    if not util.is_valid_win(win) then return end

    local group = vim.api.nvim_create_augroup(
        "PyreplWin",
        { clear = false }
    )

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function() M.hide_repl() end,
        once = true,
    })
end

function M.scroll_repl()
    if not (M.state and util.is_valid_win(M.state.win)) then return end

    vim.api.nvim_win_call(M.state.win, function()
        vim.cmd.normal({ "G", bang = true })
    end)
end

local function open_hidden_repl()
    if not (M.state and util.is_valid_win(M.state.win)) then return end

    local win = vim.api.nvim_get_current_win()
    M.state.win = open_scratch_win()
    vim.api.nvim_win_set_buf(M.state.win, M.state.buf)
    vim.api.nvim_set_current_win(win)
    setup_win_autocmd(M.state.win)
    M.scroll_repl()
end

---@param kernel string
local function open_new_repl(kernel)
    if M.state then return end

    local python_path = python.get_python_path()
    local console_path = python.get_console_path()
    local style = require("pyrepl").config.style or "default"
    local nvim_socket = vim.v.servername

    local buf = vim.api.nvim_create_buf(false, true)
    local buf_name = string.format("pyrepl: %s", kernel)
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
        "--kernel",
        kernel,
        "--ZMQTerminalInteractiveShell.highlighting_style",
        style,
    }

    local chan = vim.fn.jobstart(cmd, {
        term = true,
        pty = true,
        env = vim.tbl_extend(
            "force",
            vim.env,
            { NVIM = nvim_socket, PYTHONDONTWRITEBYTECODE = "1" }
        ),
        on_exit = function() M.close_repl() end,
    })

    if chan == 0 or chan == -1 then
        error(util.msg .. "failed to start jupyter-console correctly", 0)
    end

    M.state = {
        buf = buf,
        win = win,
        chan = chan,
        kernel = kernel,
    }

    vim.api.nvim_set_current_win(current_win)
    M.scroll_repl()
end

--- Open hidden REPL or initialize new from prompted kernel.
function M.open_repl()
    if M.state then
        open_hidden_repl()
        return
    end

    local on_choice = function(kernel)
        open_new_repl(kernel)
    end

    python.prompt_kernel(on_choice)
end

function M.hide_repl()
    if M.state and util.is_valid_win(M.state.win) then
        pcall(vim.api.nvim_win_close, M.state.win, true)
        M.state.win = nil
    end
end

--- Close session completely.
function M.close_repl()
    if not M.state then return end

    M.hide_repl()
    pcall(vim.fn.jobstop, M.state.chan)
    pcall(vim.cmd.bdelete, { M.state.buf, bang = true })
    M.state = nil
end

return M
