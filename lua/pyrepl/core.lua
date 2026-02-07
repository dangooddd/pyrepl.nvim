local kernel = require("pyrepl.kernel")

local M = {}

---@type pyrepl.Session|nil
M.session = nil

---@return integer
local function open_split()
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

--- Keep session state in sync with terminal lifecycle events.
---@param buf integer
---@param win integer
local function attach_autocmds(buf, win)
    local group = vim.api.nvim_create_augroup(
        "PyreplTerm" .. buf,
        { clear = true }
    )

    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = buf,
        callback = function()
            M.close_repl()
        end,
        once = true,
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

local function open_hidden_repl()
    if not M.session then return end
    if M.session.win then return end

    local buf_name = string.format("pyrepl: %s", M.session.kernel_name)
    M.session.win = open_split()
    attach_autocmds(M.session.buf, M.session.win)
    vim.api.nvim_win_set_buf(M.session.win, M.session.buf)
    vim.api.nvim_buf_set_name(M.session.buf, buf_name)
    vim.api.nvim_set_current_win(M.session.win)
end

local function init_repl(kernel_name)
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
    vim.bo[buf].bufhidden = "hide"

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
        chan = chan,
        connection_file = connection_file,
        kernel_name = kernel_name,
    }
end

--- Open hidden REPL or initialize new session
function M.open_repl()
    if M.session then
        open_hidden_repl()
        return
    end

    local on_choice = function(kernel_name)
        init_repl(kernel_name)
        open_hidden_repl()
    end

    kernel.prompt_kernel(on_choice)
end

--- Hide window with REPL terminal
function M.hide_repl()
    if M.session and M.session.win then
        pcall(vim.api.nvim_win_close, M.session.win, true)
    end
end

--- Close session entirely
function M.close_repl()
    if not M.session then return end

    M.hide_repl()
    pcall(vim.api.nvim_buf_delete, M.session.buf, { force = true })
    vim.schedule(function() kernel.shutdown_kernel(M.session.connection_file) end)
    M.session = nil
end

return M
