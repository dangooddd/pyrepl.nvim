local M = {}

local console_path = nil

local function get_console_path()
    if console_path then
        return console_path
    end

    local candidates = vim.api.nvim_get_runtime_file("rplugin/python3/pyrepl/console.py", false)
    if candidates and #candidates > 0 then
        console_path = candidates[1]
        return console_path
    end

    return nil
end

local function set_window_opts(winid, cfg, kernelname)
    if cfg.split_horizontal then
        vim.wo[winid].winfixheight = true
        vim.wo[winid].winfixwidth = false
    else
        vim.wo[winid].winfixwidth = true
        vim.wo[winid].winfixheight = false
    end

    local statusline_format = string.format("Kernel: %s  |  Line : %%l ", kernelname)
    vim.wo[winid].statusline = statusline_format
end

local function open_split(cfg)
    if cfg.split_horizontal then
        local height = math.floor(vim.o.lines * cfg.split_ratio)
        vim.cmd("botright " .. height .. "split")
    else
        local width = math.floor(vim.o.columns * cfg.split_ratio)
        vim.cmd("botright " .. width .. "vsplit")
    end

    return vim.api.nvim_get_current_win()
end

---@param session pyrepl.Session|nil
---@param term_buf integer|nil
---@param clear_buf boolean
function M.clear_term(session, term_buf, clear_buf)
    if not session then
        return
    end

    if term_buf and session.term_buf and session.term_buf ~= term_buf then
        return
    end

    if clear_buf then
        session.term_buf = nil
        session.term_chan = nil
    end

    session.term_win = nil
end

local function attach_term_autocmds(session, bufid, winid)
    local group = vim.api.nvim_create_augroup("PyreplTerm" .. bufid, { clear = true })

    vim.api.nvim_create_autocmd({ "BufWipeout", "TermClose" }, {
        group = group,
        buffer = bufid,
        callback = function()
            M.clear_term(session, bufid, true)
        end,
        once = true,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(winid),
        callback = function()
            M.clear_term(session, bufid, false)
        end,
        once = true,
    })
end

local function open_existing(session, cfg)
    local origin_win = vim.api.nvim_get_current_win()
    local winid = open_split(cfg)
    vim.api.nvim_win_set_buf(winid, session.term_buf)
    session.term_win = winid
    set_window_opts(winid, cfg, session.kernel_name or "")
    attach_term_autocmds(session, session.term_buf, winid)

    vim.api.nvim_set_current_win(origin_win)
end

---@param session pyrepl.Session|nil
---@param python_executable string
function M.open(session, python_executable)
    if not session or not session.connection_file then
        return
    end

    local cfg = require("pyrepl").get_config()

    if session.term_buf and vim.api.nvim_buf_is_valid(session.term_buf) then
        if not session.term_win or not vim.api.nvim_win_is_valid(session.term_win) then
            open_existing(session, cfg)
        end
        return
    end

    local origin_win = vim.api.nvim_get_current_win()
    local bufid = vim.api.nvim_create_buf(false, true)
    vim.bo[bufid].bufhidden = "hide"

    local winid = open_split(cfg)
    vim.api.nvim_win_set_buf(winid, bufid)
    set_window_opts(winid, cfg, session.kernel_name or "")

    local console = get_console_path()
    if not console then
        vim.notify(
            "PyREPL: Console script not found. Run :UpdateRemotePlugins and restart Neovim.",
            vim.log.levels.ERROR
        )
        return
    end

    local style = cfg.style or "default"
    local nvim_socket = vim.v.servername
    local term_cmd = {
        python_executable,
        console,
        "--existing",
        session.connection_file,
        "--pygments-style",
        tostring(style),
    }

    local chanid = vim.fn.jobstart(term_cmd, {
        term = true,
        pty = true,
        env = {
            NVIM_LISTEN_ADDRESS = nvim_socket,
        },
        on_exit = function()
            vim.schedule(function()
                M.clear_term(session, bufid, true)
            end)
        end,
    })

    session.term_buf = bufid
    session.term_win = winid
    session.term_chan = chanid
    vim.b[bufid].pyrepl_owner = session.bufnr

    attach_term_autocmds(session, bufid, winid)

    vim.api.nvim_set_current_win(origin_win)
end

---@param session pyrepl.Session|nil
function M.hide(session)
    if not session or not session.term_win or not vim.api.nvim_win_is_valid(session.term_win) then
        return
    end

    vim.api.nvim_win_close(session.term_win, true)
    session.term_win = nil
end

---@param session pyrepl.Session|nil
function M.close(session)
    if not session or not session.term_buf then
        return
    end

    local term_buf = session.term_buf
    M.clear_term(session, term_buf, true)

    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
        pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
    end
end

return M
