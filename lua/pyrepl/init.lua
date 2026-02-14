local M = {}

local send = require("pyrepl.send")
local image = require("pyrepl.image")
local core = require("pyrepl.core")
local python = require("pyrepl.python")
local util = require("pyrepl.util")
local jupytext = require("pyrepl.jupytext")

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
    jupytext_integration = true,
}

---@type pyrepl.Config
M.config = vim.deepcopy(defaults)

M.open_repl = core.open_repl
M.hide_repl = core.hide_repl
M.close_repl = core.close_repl
M.open_images = image.open_images
M.install_packages = python.install_packages
M.export_to_notebook = jupytext.export_to_notebook
M.open_in_notebook = jupytext.open_in_notebook

function M.send_visual()
    if core.state then
        send.send_visual(core.state.chan)
        core.scroll_repl()
    end
end

function M.send_buffer()
    if core.state then
        send.send_buffer(core.state.chan)
        core.scroll_repl()
    end
end

function M.send_block()
    if core.state then
        send.send_block(core.state.chan, M.config.block_pattern)
        core.scroll_repl()
    end
end

function M.block_forward()
    local _, end_line = util.get_block_range(M.config.block_pattern)
    if end_line <= 0 then return end
    vim.cmd.normal({ tostring(end_line + 1) .. "gg^", bang = true })
end

function M.block_backward()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]

    if line:match(M.config.block_pattern) and pos[1] > 1 then
        vim.api.nvim_win_set_cursor(0, { pos[1] - 1, pos[2] })
    end

    local start_line, _ = util.get_block_range(M.config.block_pattern)
    vim.cmd.normal({ tostring(math.max(0, start_line - 1)) .. "gg^", bang = true })
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
        ---@diagnostic disable-next-line
        M.config[key] = util.clip(M.config[key], min, max, defaults[key])
    end

    local commands = {
        PyreplOpen = M.open_repl,
        PyreplHide = M.hide_repl,
        PyreplClose = M.close_repl,
        PyreplSendVisual = M.send_visual,
        PyreplSendBuffer = M.send_buffer,
        PyreplSendBlock = M.send_block,
        PyreplBlockForward = M.block_forward,
        PyreplBlockBackward = M.block_backward,
        PyreplOpenImages = M.open_images,
    }

    for name, callback in pairs(commands) do
        vim.api.nvim_create_user_command(name, callback, { force = true })
    end

    vim.api.nvim_create_user_command(
        "PyreplInstall",
        function(o) M.install_packages(o.args) end,
        { nargs = 1, complete = python.get_tools }
    )

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "python",
        callback = function(args)
            vim.api.nvim_buf_create_user_command(
                args.buf, "PyreplExport",
                function(o) M.export_to_notebook(o.args) end,
                { nargs = "?", complete = "file" }
            )
        end
    })

    if M.config.jupytext_integration then
        jupytext.setup()
    end

    return M
end

return M
