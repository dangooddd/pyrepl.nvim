local M = {}

---@type pyrepl.ReplState|nil
local state = nil

local config = require("pyrepl.config")
local python = require("pyrepl.python")
local theme = require("pyrepl.theme")

local group = vim.api.nvim_create_augroup("PyreplCore", { clear = true })
local ns = vim.api.nvim_create_namespace("PyreplCore")

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
        win_config.split = "below"
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
        event = { "BufWipeout", "BufDelete" },
        group = group,
        buffer = state.buf,
    })

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
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

---Open window, if session is active but win is invalid or nil.
local function open_hidden_repl()
    if state and not (state.win and vim.api.nvim_win_is_valid(state.win)) then
        state.win = open_scratch_win(state.buf)
        setup_win_autocmds()
    end
end

---Main session initialization function.
---Opens REPL process and window.
---@param args table
local function open_new_repl(args)
    if state then
        return
    end

    local python_path = python.get_python_path()
    local console_path = python.get_console_path()
    local style = config.get_state().style
    local style_integration = config.get_state().style_integration

    local buf = vim.api.nvim_create_buf(false, true)
    local win = open_scratch_win(buf)
    vim.bo[buf].bufhidden = "hide"

    local cmd = vim.list_extend({
        python_path,
        console_path,
        "--ZMQTerminalInteractiveShell.highlighting_style",
        style,
        "--ZMQTerminalInteractiveShell.true_color",
        vim.o.termguicolors and "True" or "False",
    }, args)

    if style_integration then
        local pygments_overrides = theme.build_pygments_theme()
        local prompt_toolkit_overrides = theme.build_prompt_toolkit_theme()

        if pygments_overrides then
            vim.list_extend(cmd, {
                "--ZMQTerminalInteractiveShell.highlighting_style_overrides",
                pygments_overrides,
            })
        end

        if prompt_toolkit_overrides then
            vim.list_extend(cmd, {
                "--prompt-toolkit-overrides",
                prompt_toolkit_overrides,
            })
        end
    end

    -- start job from created scratch buffer
    local chan = 0
    vim.api.nvim_buf_call(buf, function()
        chan = vim.fn.jobstart(cmd, {
            term = true,
            pty = true,
            env = { PYDEVD_DISABLE_FILE_VALIDATION = 1 },
            on_exit = function()
                vim.on_key(function()
                    vim.on_key(nil, ns)
                    M.close_repl()
                end, ns)
            end,
        })
    end)

    if chan == 0 or chan == -1 then
        error(config.get_message_prefix() .. "failed to start REPL, try `:PyreplInstall`", 0)
    end

    -- set REPL state
    state = {
        buf = buf,
        win = win,
        chan = chan,
        args = args,
        closing = false,
    }

    setup_buf_autocmds()
    setup_win_autocmds()
end

---Scroll the REPL window to the end so the latest cell is in focus.
function M.scroll_repl()
    if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_call(state.win, function()
            vim.cmd.normal({ "G", bang = true })
        end)
    end
end

---Toggle REPL terminal focus.
function M.toggle_repl_focus()
    open_hidden_repl()

    if not (state and state.win and vim.api.nvim_win_is_valid(state.win)) then
        return
    end

    if vim.api.nvim_get_current_win() == state.win then
        vim.cmd.stopinsert() -- start terminal mode
        vim.cmd.wincmd("p")
    else
        vim.api.nvim_set_current_win(state.win)
        vim.cmd.startinsert()
    end
end

---Open the hidden REPL or initialize a new one after prompting for a kernel.
---@param args table|nil
function M.open_repl(args)
    if state then
        open_hidden_repl()
    elseif args then
        open_new_repl(args)
    else
        python.prompt_kernel(function(kernel)
            open_new_repl({ "--kernel", kernel })
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

    -- prevent possible recursion
    state.closing = true
    M.hide_repl()
    vim.fn.jobstop(state.chan)
    pcall(vim.cmd.bdelete, { state.buf, bang = true })

    state = nil
end

---Toggle REPL window.
function M.toggle_repl()
    if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        M.hide_repl()
    else
        M.open_repl()
    end
end

---Get terminal job chan if REPL active, return nil otherwise.
---@return integer|nil
function M.get_chan()
    if state then
        return state.chan
    end
end

return M
