local kernel = require("pyrepl.kernel")

local M = {}
M.console_path = nil

--- Find the console.py script in runtimepath (cached).
---@return string|nil
local function get_console_path()
    if M.console_path then return M.console_path end

    local candidates = vim.api.nvim_get_runtime_file("rplugin/python3/pyrepl/console.py", false)
    if candidates and #candidates > 0 then
        M.console_path = candidates[1]
        return M.console_path
    end

    return nil
end

---@param win integer
---@param kernel_name string
local function set_window_opts(win, kernel_name)
    if require("pyrepl").get_config().split_horizontal then
        vim.wo[win].winfixheight = true
        vim.wo[win].winfixwidth = false
    else
        vim.wo[win].winfixwidth = true
        vim.wo[win].winfixheight = false
    end

    local statusline_format = string.format("Kernel: %s  |  Line : %%l ", kernel_name)
    vim.wo[win].statusline = statusline_format
end

---@return integer
local function open_split()
    local cfg = require("pyrepl").get_config()
    if cfg.split_horizontal then
        local height = math.floor(vim.o.lines * cfg.split_ratio)
        vim.cmd("botright " .. height .. "split")
    else
        local width = math.floor(vim.o.columns * cfg.split_ratio)
        vim.cmd("botright " .. width .. "vsplit")
    end
    return vim.api.nvim_get_current_win()
end

--- Keep session state in sync with terminal lifecycle events.
---@param buf integer
---@param term_buf integer
---@param term_win integer
local function attach_autocmds(buf, term_buf, term_win)
    local group = vim.api.nvim_create_augroup(
        "PyreplTerm" .. buf,
        { clear = true }
    )

    vim.api.nvim_create_autocmd({ "BufWipeout" }, {
        group = group,
        buffer = term_buf,
        callback = function()
            M.close_repl(buf)
        end,
        once = true,
    })

    vim.api.nvim_create_autocmd({ "TermClose" }, {
        group = group,
        buffer = term_buf,
        callback = function()
            M.close_repl(buf)
        end,
        once = true,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(term_win),
        callback = function()
            M.hide_repl(buf)
        end,
        once = true,
    })
end

--- Start a Jupyter console job.
--- Opens existing terminal buffer if it exists
--- Otherwise opens new terminal
function M.open_repl_term()
    local buf = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local term_buf = vim.b[buf].pyrepl_term_buf
    local term_win = vim.b[buf].pyrepl_term_win
    local kernel_name = vim.b[buf].pyrepl_kernel_name

    -- use existing buffer
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
        if not term_win or not vim.api.nvim_win_is_valid(term_win) then
            term_win = open_split()
            vim.api.nvim_win_set_buf(term_win, term_buf)
            set_window_opts(term_win, kernel_name or "")
            attach_autocmds(buf, term_buf, term_win)
            vim.api.nvim_set_current_win(win)
        end
        return
    end

    local python_path = kernel.get_python_path()
    local console_path = get_console_path()
    local connection_file = vim.b[buf].pyrepl_connection_file
    local style = require("pyrepl").get_config().style or "default"
    local nvim_socket = vim.v.servername

    if not console_path then
        vim.notify(
            "Pyrepl: Console script not found. Run :UpdateRemotePlugins and restart Neovim.",
            vim.log.levels.ERROR
        )
        return
    end

    if not connection_file then
        vim.notify(
            "Pyrepl: Connection file not found, bug.",
            vim.log.levels.ERROR
        )
    end

    if not python_path then
        vim.notify(
            "Pyrepl: Python file not found, bug.",
            vim.log.levels.ERROR
        )
        return
    end

    -- setup new terminal
    term_win = open_split()
    term_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[term_buf].bufhidden = "hide"
    vim.api.nvim_win_set_buf(term_win, term_buf)
    set_window_opts(term_win, kernel_name or "")

    local term_cmd = {
        python_path,
        console_path,
        "--existing",
        connection_file,
        "--pygments-style",
        tostring(style),
    }

    local term_chan = vim.fn.jobstart(term_cmd, {
        term = true,
        pty = true,
        env = { NVIM = nvim_socket },
        on_exit = function()
            vim.schedule(function()
                M.close_repl(buf)
            end)
        end,
    })

    vim.b[buf].pyrepl_term_buf = term_buf
    vim.b[buf].pyrepl_term_win = term_win
    vim.b[buf].pyrepl_term_chan = term_chan
    vim.b[term_buf].pyrepl_owner = buf

    attach_autocmds(buf, term_buf, term_win)
    vim.api.nvim_set_current_win(win)
end

---@param buf integer?
function M.hide_repl(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local term_win = vim.b[buf].pyrepl_term_win

    if term_win and vim.api.nvim_win_is_valid(term_win) then
        pcall(vim.api.nvim_win_close, term_win, true)
    end

    vim.b[buf].pyrepl_term_win = nil
end

---@param buf integer?
function M.close_repl(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local term_buf = vim.b[buf].pyrepl_term_buf
    local connection_file = vim.b[buf].pyrepl_connection_file

    vim.b[buf].pyrepl_term_buf = nil
    vim.b[buf].pyrepl_term_win = nil
    vim.b[buf].pyrepl_term_chan = nil
    vim.b[buf].pyrepl_connection_file = nil
    vim.b[buf].pyrepl_kernel_name = nil

    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
        pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
    end

    kernel.shutdown_kernel(connection_file)
end

return M
