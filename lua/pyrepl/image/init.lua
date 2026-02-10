local M = {}

---@type pyrepl.ImageState
local state = {
    history = {},
    history_index = 0,
    buf = nil,
    win = nil,
}

local provider = require("pyrepl.image.placeholders")

---@param buf integer|nil
---@return integer
local function open_image_win(buf)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        buf = vim.api.nvim_create_buf(false, true)
    end

    local width = vim.o.columns
    local height = vim.o.lines

    local config = require("pyrepl").config
    local float_width = math.max(1, math.floor(width * config.image_width_ratio))
    local float_height = math.max(1, math.floor(height * config.image_height_ratio))

    -- subtract 2 to take command line into account
    local col = math.max(0, width - float_width)
    local row = math.max(0, height - float_height - 2)

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

    local winhl = string.format("Normal:%s,FloatBorder:%s,FloatTitle:%s", normal_hl, border_hl, title_hl)
    vim.wo[win].winhl = winhl

    return win
end

local function setup_cursor_autocmd()
    local group = vim.api.nvim_create_augroup(
        "PyreplImageCursor",
        { clear = true }
    )

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function() M.close_image() end,
        once = true
    })
end

---@param buf integer
---@param win integer
local function setup_manager_autocmd(buf, win)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
    if not (win and vim.api.nvim_win_is_valid(win)) then return end

    local group = vim.api.nvim_create_augroup(
        "PyreplImageClose",
        { clear = false }
    )

    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = group,
        buffer = buf,
        callback = function() M.close_image() end,
        once = true
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function() M.close_image() end,
        once = true
    })
end

--- Redraw image placeholders on editor resize/focus changes.
---@param buf integer
---@param win integer
local function setup_resize_autocmd(buf, win)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
    if not (win and vim.api.nvim_win_is_valid(win)) then return end

    local group = vim.api.nvim_create_augroup(
        "PyreplImageResize",
        { clear = true }
    )

    vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
        group = group,
        callback = function()
            vim.schedule(function() provider.redraw(buf, win) end)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "TabEnter" }, {
        group = group,
        callback = function()
            vim.schedule(function() provider.redraw(buf, win) end)
        end
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
    table.remove(state.history, state.history_index)
    state.history_index = math.min(#state.history, state.history_index + 1)
end

---@param buf integer
local function set_keymaps(buf)
    local opts = { noremap = true, silent = true, nowait = true, buffer = buf }

    vim.keymap.set("n", "j", function() end, opts)
    vim.keymap.set("n", "l", function() end, opts)

    vim.keymap.set("n", "h", function()
        M.show_previous_image(true, false)
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

    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
        state.win = open_image_win(state.buf)
    end

    local title = string.format(
        " History %d/%d ",
        state.history_index,
        #state.history
    )
    local opts = { title = title, title_pos = "center" }
    vim.api.nvim_win_set_config(state.win, opts)

    provider.render(img_data, state.buf, state.win)
    setup_resize_autocmd(state.buf, state.win)
    setup_manager_autocmd(state.buf, state.win)
    set_keymaps(state.buf)

    if focus then
        vim.api.nvim_set_current_win(state.win)
    end

    if auto_clear then
        setup_cursor_autocmd()
    end
end

--- Show a specific image from history.
---@param index integer
---@param focus? boolean true by default
---@param auto_clear? boolean false by default
function M.open_images(index, focus, auto_clear)
    if #state.history == 0 then
        vim.notify("Pyrepl: No image history available.", vim.log.levels.WARN)
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
function M.endpoint(img_data)
    if type(img_data) ~= "string" or img_data == "" then
        vim.notify("Pyrepl: Image data missing or invalid.", vim.log.levels.WARN)
        return
    end
    push_history(img_data)
    M.open_images(#state.history, false, true)
end

function M.close_image()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
    end

    if state.buf then
        provider.clear(buf)
        vim.api.nvim_buf_delete(state.buf, { force = true })
    end

    state.buf = nil
    state.win = nil
end

---@param focus boolean|nil
function M.show_previous_image(focus, auto_clear)
    focus = focus or false
    auto_clear = auto_clear or false

    if state.history_index <= 1 then
        state.history_index = 1
        return
    end
    M.open_images(state.history_index - 1, focus, auto_clear)
end

---@param focus boolean
function M.show_next_image(focus, auto_clear)
    focus = focus or false
    auto_clear = auto_clear or false

    if state.history_index >= #state.history then
        state.history_index = #state.history
        return
    end
    M.open_images(state.history_index + 1, focus, auto_clear)
end

return M
