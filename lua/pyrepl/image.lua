local M = {}

local placeholders = require("pyrepl.placeholders")
local util = require("pyrepl.util")

local group = vim.api.nvim_create_augroup("PyreplImage", { clear = true })

---@type pyrepl.ImageState
local state = {
    history = {},
    history_index = 0,
    buf = nil,
    win = nil,
}

--- Open float window to place image in.
--- Placed in top-right angle in vertical layout.
--- Placed in bottom-right angle in horizontal layout.
---@param buf integer
---@return integer
local function open_image_win(buf)
    local width = vim.o.columns
    local height = vim.o.lines
    local config = require("pyrepl").config

    local float_width = math.max(1, math.floor(width * config.image_width_ratio))
    local float_height = math.max(1, math.floor(height * config.image_height_ratio))

    local col = math.max(0, width - float_width)
    -- bottom right angle for split_horizontal, top right angle otherwise
    -- subtract 2 to take command line into account
    local row = math.max(0, config.split_horizontal and height - float_height - 2 or 0)

    -- effective window size (without borders)
    -- subtract 2 to take borders into account
    local opts = {
        relative = "editor",
        width = float_width - 2,
        height = float_height - 2,
        row = row,
        col = col,
        style = "minimal",
    }

    local win = vim.api.nvim_open_win(buf, false, opts)

    local border_hl = "PyreplImageBorder"
    local title_hl = "PyreplImageTitle"
    local normal_hl = "PyreplImageNormal"

    if vim.fn.hlexists(border_hl) == 0 then
        vim.api.nvim_set_hl(0, border_hl, { link = "FloatBorder" })
    end
    if vim.fn.hlexists(title_hl) == 0 then
        vim.api.nvim_set_hl(0, title_hl, { link = "FloatTitle" })
    end
    if vim.fn.hlexists(normal_hl) == 0 then
        vim.api.nvim_set_hl(0, normal_hl, { link = "NormalFloat" })
    end

    local winhl = string.format(
        "Normal:%s,FloatBorder:%s,FloatTitle:%s",
        normal_hl, border_hl, title_hl
    )
    vim.wo[win].winhl = winhl

    return win
end

local function setup_cursor_autocmds()
    vim.api.nvim_clear_autocmds({
        event = { "CursorMoved", "CursorMovedI" },
        group = group,
    })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function() M.close_image() end,
        once = true
    })
end

---@param buf integer
---@param win integer
local function setup_manager_autocmds(buf, win)
    vim.api.nvim_clear_autocmds({
        event = { "WinResized", "WinClosed" },
        group = group,
        pattern = tostring(win),
    })

    vim.api.nvim_clear_autocmds({
        event = { "BufWipeout", "BufDelete" },
        group = group,
        buffer = buf,
    })

    vim.api.nvim_create_autocmd("WinResized", {
        group = group,
        pattern = tostring(win),
        callback = function()
            vim.schedule(function() placeholders.redraw(buf, win) end)
        end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function() M.close_image() end,
        once = true
    })

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = group,
        buffer = buf,
        callback = function() M.close_image() end,
        once = true
    })
end

--- Add an image to history.
---@param img_data string
local function push_history(img_data)
    if #state.history >= require("pyrepl").config.image_max_history then
        table.remove(state.history, 1)
    end
    table.insert(state.history, img_data)
    state.history_index = #state.history
end

--- Pop image entry from history.
local function pop_history()
    if state.history_index > 0 and #state.history >= state.history_index then
        table.remove(state.history, state.history_index)
        state.history_index = math.min(#state.history, state.history_index)
    end
end

--- Sets keymap in history manager:
--- j/h - show previous image;
--- k/l - show next image;
--- dd - delete image;
--- Esc/q - exit manager.
---@param buf integer
local function set_keymaps(buf)
    local opts = { noremap = true, silent = true, nowait = true, buffer = buf }

    vim.keymap.set("n", "j", function()
        M.show_previous_image(true, false)
    end, opts)

    vim.keymap.set("n", "h", function()
        M.show_previous_image(true, false)
    end, opts)

    vim.keymap.set("n", "k", function()
        M.show_next_image(true, false)
    end, opts)

    vim.keymap.set("n", "l", function()
        M.show_next_image(true, false)
    end, opts)

    vim.keymap.set("n", "dd", function()
        pop_history()
        if #state.history == 0 then
            M.close_image()
        else
            M.open_images(state.history_index)
        end
    end, opts)

    vim.keymap.set("n", "q", function()
        M.close_image()
    end, opts)

    vim.keymap.set("n", "<Esc>", function()
        M.close_image()
    end, opts)
end

--- Render an image entry into a floating window.
---@param img_data string
---@param focus boolean
---@param auto_clear boolean
local function render_image(img_data, focus, auto_clear)
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        vim.api.nvim_buf_delete(state.buf, { force = true })
    end
    state.buf = vim.api.nvim_create_buf(false, true)

    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
        state.win = open_image_win(state.buf)
    end

    local title = string.format(
        " History %d/%d ",
        state.history_index,
        #state.history
    )
    local opts = { title = title, title_pos = "center" }
    vim.api.nvim_win_set_config(state.win, opts)

    placeholders.render(img_data, state.buf, state.win)
    setup_manager_autocmds(state.buf, state.win)
    set_keymaps(state.buf)

    if focus then
        vim.api.nvim_set_current_win(state.win)
    end

    if auto_clear then
        setup_cursor_autocmds()
    end
end

--- Show a specific image from history.
---@param index? integer last image by default
---@param focus? boolean true by default
---@param auto_clear? boolean false by default
function M.open_images(index, focus, auto_clear)
    if #state.history == 0 then
        vim.notify(
            util.msg .. "no image history available",
            vim.log.levels.WARN
        )
        return
    end

    index = index or #state.history
    if focus == nil then focus = true end
    if auto_clear == nil then auto_clear = false end

    if index < 1 or index > #state.history then
        return
    end

    local img_data = state.history[index]
    state.history_index = index
    render_image(img_data, focus, auto_clear)
end

--- Store base64 PNG data and display it.
---@param img_data string
function M.console_endpoint(img_data)
    if type(img_data) ~= "string" or img_data == "" then
        error(util.msg .. "image data missing or invalid", 0)
    end
    push_history(img_data)
    M.open_images(#state.history, false, true)
end

--- Closes image history window.
function M.close_image()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
    end

    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        placeholders.clear(state.buf)
        vim.api.nvim_buf_delete(state.buf, { force = true })
    end

    state.buf = nil
    state.win = nil
end

---@param focus? boolean default like in open_images
---@param auto_clear? boolean default like in open_images
function M.show_previous_image(focus, auto_clear)
    if state.history_index <= 1 then
        state.history_index = 1
    else
        M.open_images(state.history_index - 1, focus, auto_clear)
    end
end

---@param focus? boolean default like in open_images
---@param auto_clear? boolean default like in open_images
function M.show_next_image(focus, auto_clear)
    if state.history_index >= #state.history then
        state.history_index = #state.history
    else
        M.open_images(state.history_index + 1, focus, auto_clear)
    end
end

return M
