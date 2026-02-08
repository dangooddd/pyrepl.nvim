local M = {}

---@type pyrepl.Session|nil
M.session = nil
local python_path_cache = nil
local console_path_cache = nil

---@return string|nil
local function get_python_path()
    if python_path_cache then return python_path_cache end

    local python = vim.fn.expand(vim.g.python3_host_prog)

    if vim.fn.executable(python) == 0 then
        vim.notify(
            "Pyrepl: vim.g.python3_host_prog should be correct executable.",
            vim.log.levels.ERROR
        )
        return nil
    end

    python_path_cache = python
    return python_path_cache
end

--- Find the console.py script in runtimepath (cached).
---@return string|nil
local function get_console_path()
    if console_path_cache then return console_path_cache end

    local candidates = vim.api.nvim_get_runtime_file(
        "rplugin/python3/pyrepl/console.py",
        false
    )

    if candidates and #candidates > 0 then
        console_path_cache = candidates[1]
        return console_path_cache
    end

    vim.notify(
        "Pyrepl: Console not found. Run :UpdateRemotePlugins and restart.",
        vim.log.levels.ERROR
    )

    return nil
end

---@param callback fun(name: string)
local function prompt_kernel(callback)
    local kernels = vim.fn.PyreplListKernels()

    vim.ui.select(
        kernels,
        {
            prompt = "Pyrepl: Select Jupyter kernel",
            format_item = function(item)
                return string.format("%s (%s)", item.name, item.resource_dir)
            end,
        },
        function(choice)
            if choice then
                callback(choice.name)
            end
        end
    )
end

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

local function open_new_repl(kernel)
    if M.session then return end

    local python_path = get_python_path()
    local console_path = get_console_path()
    local style = require("pyrepl").config.style or "default"
    local nvim_socket = vim.v.servername

    if not python_path then return end
    if not console_path then return end

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
        kernel = kernel,
    }

    vim.api.nvim_set_current_win(current_win)
end

--- Open hidden REPL or initialize new session
function M.open_repl()
    if M.session then
        open_hidden_repl()
        return
    end

    local on_choice = function(kernel)
        open_new_repl(kernel)
    end

    prompt_kernel(on_choice)
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
    pcall(vim.fn.jobstop, M.session.chan)
    pcall(vim.cmd.bdelete, { M.session.buf, bang = true })
    M.session = nil
end

return M
