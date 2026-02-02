local M = {}

M.state = {
    sessions = {},
    python_host = nil,
    deps_ok = false,
}

function M.get_session(bufnr, create)
    if not bufnr or bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
    end

    local session = M.state.sessions[bufnr]
    if session or not create then
        return session
    end

    session = {
        bufnr = bufnr,
        kernel_name = nil,
        connection_file = nil,
        term_buf = nil,
        term_win = nil,
        term_chan = nil,
        send_queue = {},
        send_flushing = false,
        repl_ready = false,
        closing = false,
    }
    M.state.sessions[bufnr] = session

    return session
end

function M.clear_session(bufnr)
    M.state.sessions[bufnr] = nil
end

return M
