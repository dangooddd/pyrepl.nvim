local M = {}

local config = require("pyrepl.config")
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
    image.idx()
end

function M.export_to_notebook()
    jupytext.export_to_notebook(0)
end

function M.convert_to_python()
    jupytext.convert_to_python(0)
end

---@param tool string
function M.install_packages(tool)
    python.install_packages(tool)
end

function M.send_visual()
    local chan = core.get_chan()
    if chan then
        -- update visual selection marks
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "n",
            false
        )
        -- schedule to ensure marks are updated
        vim.schedule(function()
            send.send_visual(0, chan)
            core.scroll_repl()
        end)
    end
end

function M.send_buffer()
    local chan = core.get_chan()
    if chan then
        send.send_buffer(0, chan)
        core.scroll_repl()
    end
end

function M.send_cell()
    local chan = core.get_chan()
    if chan then
        local idx = vim.api.nvim_win_get_cursor(0)[1]
        send.send_cell(0, chan, idx, config.get_state().cell_pattern)
        core.scroll_repl()
    end
end

function M.step_cell_forward()
    send.step_cell_forward(0)
end

function M.step_cell_backward()
    send.step_cell_backward(0)
end

---@param opts? pyrepl.ConfigOpts
---@return table
function M.setup(opts)
    config.update_state(opts)

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
        PyreplExport = M.export_to_notebook,
        PyreplConvert = M.convert_to_python,
    }

    for name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(name, callback, { force = true, nargs = 0 })
    end

    vim.api.nvim_create_user_command("PyreplInstall", function(o)
        M.install_packages(o.args)
    end, { nargs = 1, complete = python.get_tools })

    if config.get_state().jupytext_hook and vim.fn.executable("jupytext") == 1 then
        vim.api.nvim_clear_autocmds({
            event = "BufReadPost",
            group = group,
            pattern = "*.ipynb",
        })

        vim.api.nvim_create_autocmd("BufReadPost", {
            group = group,
            pattern = "*.ipynb",
            callback = vim.schedule_wrap(M.convert_to_python),
        })
    end

    return M
end

return M
