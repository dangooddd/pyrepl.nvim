local M = {}

local core = require("pyrepl.core")
local image = require("pyrepl.image")
local jupytext = require("pyrepl.jupytext")
local python = require("pyrepl.python")
local send = require("pyrepl.send")

local group = vim.api.nvim_create_augroup("Pyrepl", { clear = true })

function M.open_repl()
    core.open_repl()
end

function M.hide_repl()
    core.hide_repl()
end

function M.close_repl()
    core.close_repl()
end

function M.toggle_repl_focus()
    core.toggle_repl_focus()
end

function M.open_image_history()
    image.open_image_history()
end

function M.export_python()
    jupytext.export_python(0)
end

function M.convert_notebook_guarded()
    jupytext.convert_notebook_guarded(0)
end

---@param tool string
function M.install_packages(tool)
    python.install_packages(tool)
end

function M.send_visual()
    if core.state and core.state.chan then
        -- update visual selection marks
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "n",
            false
        )
        -- schedule to ensure marks are updated
        vim.schedule(function()
            send.send_visual(0, core.state.chan)
            core.scroll_repl()
        end)
    end
end

function M.send_buffer()
    if core.state and core.state.chan then
        send.send_buffer(0, core.state.chan)
        core.scroll_repl()
    end
end

function M.send_cell()
    if core.state and core.state.chan then
        local idx = vim.api.nvim_win_get_cursor(0)[1]
        send.send_cell(0, core.state.chan, idx, require("pyrepl.config").state.cell_pattern)
        core.scroll_repl()
    end
end

function M.step_cell_forward()
    local idx = vim.api.nvim_win_get_cursor(0)[1]
    local _, end_idx = send.get_cell_range(0, idx, require("pyrepl.config").state.cell_pattern)
    if end_idx then
        vim.cmd.normal({ tostring(end_idx + 1) .. "gg^", bang = true })
    end
end

function M.step_cell_backward()
    local idx = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, idx - 1, idx, false)[1]

    if line:match(require("pyrepl.config").state.cell_pattern) then
        idx = math.max(1, idx - 1)
    end

    local start_idx, _ = send.get_cell_range(0, idx, require("pyrepl.config").state.cell_pattern)

    if start_idx then
        vim.cmd.normal({ tostring(math.max(0, start_idx - 1)) .. "gg^", bang = true })
    end
end

---@param opts? pyrepl.ConfigOpts
---@return table
function M.setup(opts)
    require("pyrepl.config").apply(opts)

    local commands = {
        PyreplOpen = M.open_repl,
        PyreplHide = M.hide_repl,
        PyreplClose = M.close_repl,
        PyreplToggleFocus = M.toggle_repl_focus,
        PyreplOpenImageHistory = M.open_image_history,
        PyreplSendVisual = M.send_visual,
        PyreplSendBuffer = M.send_buffer,
        PyreplSendCell = M.send_cell,
        PyreplStepCellForward = M.step_cell_forward,
        PyreplStepCellBackward = M.step_cell_backward,
        PyreplExport = M.export_python,
        PyreplConvert = M.convert_notebook_guarded,
    }

    for name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(name, callback, { force = true, nargs = 0 })
    end

    vim.api.nvim_create_user_command("PyreplInstall", function(o)
        M.install_packages(o.args)
    end, { nargs = 1, complete = python.get_tools })

    if require("pyrepl.config").state.jupytext_hook and vim.fn.executable("jupytext") == 1 then
        vim.api.nvim_clear_autocmds({
            event = "BufReadPost",
            group = group,
            pattern = "*.ipynb",
        })

        vim.api.nvim_create_autocmd("BufReadPost", {
            group = group,
            pattern = "*.ipynb",
            callback = vim.schedule_wrap(M.convert_notebook_guarded),
        })
    end

    return M
end

return M
