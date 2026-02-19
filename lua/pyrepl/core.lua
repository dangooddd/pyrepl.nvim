local M = {}

---@type pyrepl.ReplState|nil
M.state = nil

local python = require("pyrepl.python")
local theme = require("pyrepl.theme")

local message = require("pyrepl.config").message
local group = vim.api.nvim_create_augroup("PyreplCore", { clear = true })

---Create window according to current config.
---@return integer
local function open_scratch_win()
    local config = require("pyrepl.config").state

    if config.split_horizontal then
        local height = math.floor(vim.o.lines * config.split_ratio)
        vim.cmd("botright " .. height .. "split")
    else
        local width = math.floor(vim.o.columns * config.split_ratio)
        vim.cmd("botright " .. width .. "vsplit")
    end

    vim.api.nvim_win_set_config(0, { style = "minimal" })
    return vim.api.nvim_get_current_win()
end

---@param buf integer
local function setup_buf_autocmds(buf)
    vim.api.nvim_clear_autocmds({
        event = { "BufWipeout", "TermClose" },
        group = group,
        buffer = buf,
    })

    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = buf,
        callback = function()
            M.close_repl()
        end,
        once = true,
    })
end

---@param win integer
local function setup_win_autocmds(win)
    vim.api.nvim_clear_autocmds({
        event = "WinClosed",
        group = group,
        pattern = tostring(win),
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function()
            M.hide_repl()
        end,
        once = true,
    })
end

---Scrolls REPL window to the end, so latest cell in focus.
function M.scroll_repl()
    if M.state and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
        vim.api.nvim_win_call(M.state.win, function()
            vim.cmd.normal({ "G", bang = true })
        end)
    end
end

---Open window, if session is active but win = nil.
local function open_hidden_repl()
    if not M.state or (M.state.win and vim.api.nvim_win_is_valid(M.state.win)) then
        return
    end

    local win = vim.api.nvim_get_current_win()
    M.state.win = open_scratch_win()
    vim.api.nvim_win_set_buf(M.state.win, M.state.buf)
    vim.api.nvim_set_current_win(win)
    setup_win_autocmds(M.state.win)
    M.scroll_repl()
end

---Main session initialization function.
---Opens REPL process and window.
---@param kernel string
local function open_new_repl(kernel)
    if M.state then
        return
    end

    local config = require("pyrepl.config").state
    local python_path = python.get_python_path()
    local console_path = python.get_console_path()
    local style = config.style or "default"
    local nvim_socket = vim.v.servername

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "hide"
    setup_buf_autocmds(buf)

    local current_win = vim.api.nvim_get_current_win()
    local win = open_scratch_win()
    vim.api.nvim_win_set_buf(win, buf)
    setup_win_autocmds(win)

    local cmd = {
        python_path,
        console_path,
        "--kernel",
        kernel,
        "--ZMQTerminalInteractiveShell.highlighting_style",
        style,
        "--ZMQTerminalInteractiveShell.true_color",
        vim.o.termguicolors and "True" or "False",
    }

    if config.style_treesitter then
        local overrides = theme.build_pygments_theme()
        if overrides then
            cmd[#cmd + 1] = "--ZMQTerminalInteractiveShell.highlighting_style_overrides"
            cmd[#cmd + 1] = overrides
        end
    end

    local chan = vim.fn.jobstart(cmd, {
        term = true,
        pty = true,
        env = vim.tbl_extend(
            "force",
            vim.env,
            { NVIM = nvim_socket, PYDEVD_DISABLE_FILE_VALIDATION = 1 }
        ),
        on_exit = function()
            M.close_repl()
        end,
    })

    if chan == 0 or chan == -1 then
        error(message .. "failed to start jupyter-console correctly", 0)
    end

    M.state = {
        buf = buf,
        win = win,
        chan = chan,
        kernel = kernel,
    }

    vim.api.nvim_buf_set_name(buf, string.format("kernel: %s", kernel))
    vim.api.nvim_set_current_win(current_win)
    M.scroll_repl()
end

---Toggle REPL terminal focus; opens terminal in insert mode.
function M.toggle_repl_focus()
    open_hidden_repl()

    if not (M.state and M.state.win and vim.api.nvim_win_is_valid(M.state.win)) then
        return
    end

    if vim.api.nvim_get_current_win() == M.state.win then
        vim.cmd.stopinsert()
        vim.cmd.wincmd("p")
    else
        vim.api.nvim_set_current_win(M.state.win)
        vim.cmd.startinsert()
    end
end

---Open hidden REPL or initialize new from prompted kernel.
function M.open_repl()
    if M.state then
        open_hidden_repl()
    else
        python.prompt_kernel(function(kernel)
            open_new_repl(kernel)
        end)
    end
end

---Close REPL window.
function M.hide_repl()
    if M.state and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
        pcall(vim.api.nvim_win_close, M.state.win, true)
        M.state.win = nil
    end
end

---Close session completely:
---1) Close window;
---2) Terminate console process;
---3) Delete terminal buffer;
---4) Move state to nil.
function M.close_repl()
    if M.state then
        M.hide_repl()
        pcall(vim.fn.jobstop, M.state.chan)
        pcall(vim.cmd.bdelete, { M.state.buf, bang = true })
        M.state = nil
    end
end

return M
