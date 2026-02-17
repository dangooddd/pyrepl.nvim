local M = {}

local send = require("pyrepl.send")
local image = require("pyrepl.image")
local core = require("pyrepl.core")
local python = require("pyrepl.python")
local util = require("pyrepl.util")
local jupytext = require("pyrepl.jupytext")

local group = vim.api.nvim_create_augroup("Pyrepl", { clear = true })

---@type pyrepl.Config
local defaults = {
    split_horizontal = false,
    split_ratio = 0.5,
    style = "default",
    style_treesitter = true,
    image_max_history = 10,
    image_width_ratio = 0.5,
    image_height_ratio = 0.5,
    block_pattern = "^# %%%%.*$",
    python_path = "python",
    preferred_kernel = "python3",
    jupytext_hook = true,
}

---@type pyrepl.Config
M.config = vim.deepcopy(defaults)

function M.open_repl()
    core.open_repl()
end

function M.hide_repl()
    core.hide_repl()
end

function M.close_repl()
    core.close_repl()
end

function M.open_images()
    image.open_images()
end

function M.export_notebook()
    jupytext.export_notebook(0)
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
        send.send_visual(0, core.state.chan)
        core.scroll_repl()
    end
end

function M.send_buffer()
    if core.state and core.state.chan then
        send.send_buffer(0, core.state.chan)
        core.scroll_repl()
    end
end

function M.send_block()
    if core.state and core.state.chan then
        local idx = vim.api.nvim_win_get_cursor(0)[1]
        send.send_block(0, core.state.chan, idx, M.config.block_pattern)
        core.scroll_repl()
    end
end

function M.block_forward()
    local idx = vim.api.nvim_win_get_cursor(0)[1]
    local _, end_idx = send.get_block_range(0, idx, M.config.block_pattern)
    if end_idx <= 0 then return end
    vim.cmd.normal({ tostring(end_idx + 1) .. "gg^", bang = true })
end

function M.block_backward()
    local idx = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, idx - 1, idx, false)[1]

    if line:match(M.config.block_pattern) then
        idx = math.max(1, idx - 1)
    end

    local start_idx, _ = send.get_block_range(0, idx, M.config.block_pattern)
    vim.cmd.normal({ tostring(math.max(0, start_idx - 1)) .. "gg^", bang = true })
end

---@param opts? pyrepl.ConfigOpts
---@return table
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    local to_clip = {
        { "split_ratio",        0.1, 0.9 },
        { "image_width_ratio",  0.1, 0.9 },
        { "image_height_ratio", 0.1, 0.9 },
        { "image_max_history",  2,   100 }
    }

    for _, args in ipairs(to_clip) do
        local key, min, max = args[1], args[2], args[3]
        M.config[key] = util.clip_number(M.config[key], min, max, defaults[key] --[[@as number]])
    end

    local commands = {
        PyreplOpen = function() M.open_repl() end,
        PyreplHide = function() M.hide_repl() end,
        PyreplClose = function() M.close_repl() end,
        PyreplSendVisual = function() M.send_visual() end,
        PyreplSendBuffer = function() M.send_buffer() end,
        PyreplSendBlock = function() M.send_block() end,
        PyreplBlockForward = function() M.block_forward() end,
        PyreplBlockBackward = function() M.block_backward() end,
        PyreplOpenImages = function() M.open_images() end,
        PyreplExport = function() M.export_notebook() end,
        PyreplConvert = function() M.convert_notebook_guarded() end,
    }

    for name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(name, callback, { force = true, nargs = 0 })
    end

    vim.api.nvim_create_user_command(
        "PyreplInstall",
        function(o) M.install_packages(o.args) end,
        { nargs = 1, complete = python.get_tools }
    )

    if M.config.jupytext_hook and vim.fn.executable("jupytext") == 1 then
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
