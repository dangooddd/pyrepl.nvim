local M = {}

---@type pyrepl.ReplState|nil
local state = nil

local config = require("pyrepl.config")
local python = require("pyrepl.python")
local theme = require("pyrepl.theme")

local group = vim.api.nvim_create_augroup("PyreplCore", { clear = true })

---Create window according to current config.
---@param buf integer
---@return integer
local function open_scratch_win(buf)
    local split_horizontal = config.get_state().split_horizontal
    local split_ratio = config.get_state().split_ratio

    local win_config = {
        win = -1,
        style = "minimal",
    }

    if split_horizontal then
        win_config.height = math.floor(vim.o.lines * split_ratio)
        win_config.split = "bottom"
    else
        win_config.width = math.floor(vim.o.columns * split_ratio)
        win_config.split = "right"
    end

    return vim.api.nvim_open_win(buf, false, win_config)
end

local function setup_buf_autocmds()
    if not (state and state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
        return
    end

    vim.api.nvim_clear_autocmds({
        event = { "BufWipeout", "TermClose" },
        group = group,
        buffer = state.buf,
    })

    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = state.buf,
        callback = function()
            M.close_repl()
        end,
        once = true,
    })
end

local function setup_win_autocmds()
    if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then
        return
    end

    vim.api.nvim_clear_autocmds({
        event = "WinClosed",
        group = group,
        pattern = tostring(state.win),
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(state.win),
        callback = function()
            if state then
                state.win = nil
            end
        end,
        once = true,
    })
end

---Scrolls REPL window to the end, so latest cell in focus.
function M.scroll_repl()
    if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_call(state.win, function()
            vim.cmd.normal({ "G", bang = true })
        end)
    end
end

---Open window, if session is active but win = nil.
local function open_hidden_repl()
    if not state or (state.win and vim.api.nvim_win_is_valid(state.win)) then
        return
    end

    state.win = open_scratch_win(state.buf)
    setup_win_autocmds()
    M.scroll_repl()
end

---Main session initialization function.
---Opens REPL process and window.
---@param kernel string
local function open_new_repl(kernel)
    if state then
        return
    end

    local python_path = python.get_python_path()
    local console_path = python.get_console_path()
    local nvim_socket = vim.v.servername
    local style = config.get_state().style
    local style_treesitter = config.get_state().style_treesitter

    local buf = vim.api.nvim_create_buf(false, true)
    local win = open_scratch_win(buf)
    vim.bo[buf].bufhidden = "hide"

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

    if style_treesitter then
        local overrides = theme.build_pygments_theme()
        if overrides then
            cmd[#cmd + 1] = "--ZMQTerminalInteractiveShell.highlighting_style_overrides"
            cmd[#cmd + 1] = overrides
        end
    end

    local chan = 0
    vim.api.nvim_buf_call(buf, function()
        chan = vim.fn.jobstart(cmd, {
            term = true,
            pty = true,
            env = vim.tbl_extend(
                "force",
                vim.env,
                { NVIM = nvim_socket, PYDEVD_DISABLE_FILE_VALIDATION = 1 }
            ),
            on_exit = function()
                vim.defer_fn(M.close_repl, 200)
            end,
        })
    end)

    if chan == 0 or chan == -1 then
        error(config.get_message_prefix() .. "failed to start REPL, try `:PyreplInstall`", 0)
    end

    state = {
        buf = buf,
        win = win,
        chan = chan,
        kernel = kernel,
        closing = false,
    }

    setup_buf_autocmds()
    setup_win_autocmds()
    vim.api.nvim_buf_set_name(buf, string.format("kernel: %s", kernel))
    M.scroll_repl()
end

---Toggle REPL terminal focus; opens terminal in insert mode.
function M.toggle_repl_focus()
    open_hidden_repl()

    if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then
        return
    end

    if vim.api.nvim_get_current_win() == state.win then
        vim.cmd.stopinsert()
        vim.cmd.wincmd("p")
    else
        vim.api.nvim_set_current_win(state.win)
        vim.cmd.startinsert()
    end
end

---Open hidden REPL or initialize new from prompted kernel.
function M.open_repl()
    if state then
        open_hidden_repl()
    else
        python.prompt_kernel(function(kernel)
            open_new_repl(kernel)
        end)
    end
end

---Close REPL window.
function M.hide_repl()
    if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        pcall(function()
            vim.api.nvim_win_close(state.win, true)
            state.win = nil
        end)
    end
end

---Close session completely:
---1) Close window;
---2) Terminate console process;
---3) Delete terminal buffer;
---4) Move state to nil.
function M.close_repl()
    if not state or state.closing then
        return
    end

    state.closing = true
    M.hide_repl()
    vim.fn.jobstop(state.chan)
    pcall(vim.cmd.bdelete, { state.buf, bang = true })

    state = nil
end

---@return integer|nil
function M.get_chan()
    if state then
        return state.chan
    end
end

return M
