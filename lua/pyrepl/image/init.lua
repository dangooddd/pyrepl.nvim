local M = {}

local IMAGE_PADDING = 0

---@class pyrepl.ImageState
---@field history pyrepl.ImageEntry[]
---@field history_index integer
---@field current_buf integer|nil
---@field current_winid integer|nil
---@field manager_active boolean

---@type pyrepl.ImageState
local state = {
    history = {},
    history_index = 0,
    current_buf = nil,
    current_winid = nil,
    manager_active = false,
}

---@return integer
---@return integer
local function compute_window_cells()
    local cfg = require("pyrepl").get_config()
    local max_width_ratio = tonumber(cfg.image_width_ratio) or 0.4
    local max_height_ratio = tonumber(cfg.image_height_ratio) or 0.5
    local max_width_cells = math.max(1, math.floor(vim.o.columns * max_width_ratio))
    local max_height_cells = math.max(1, math.floor(vim.o.lines * max_height_ratio))
    return max_width_cells, max_height_cells
end

---@param width_cells integer
---@param height_cells integer
---@param focus boolean
---@param bufnr integer|nil
---@return integer
---@return integer
local function create_image_float(width_cells, height_cells, focus, bufnr)
    local win_width = vim.o.columns
    local win_height = vim.o.lines

    local float_width = width_cells + (IMAGE_PADDING * 2)
    local float_height = height_cells + (IMAGE_PADDING * 2)

    local row = math.max(0, math.floor((win_height - float_height) / 2))
    local col = math.max(0, math.floor((win_width - float_width) / 2))

    local opts = {
        relative = "editor",
        width = float_width,
        height = float_height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Image View ",
        title_pos = "center"
    }

    local own_buf = false
    if not bufnr then
        bufnr = vim.api.nvim_create_buf(false, true)
        own_buf = true
    end

    if own_buf then
        vim.bo[bufnr].modifiable = false
        vim.bo[bufnr].buftype = "nofile"
    end

    local winid = vim.api.nvim_open_win(bufnr, focus or false, opts)

    local border_hl = "PyREPLImageBorder"
    local title_hl = "PyREPLImageTitle"
    local normal_hl = "PyREPLImageNormal"

    local border_target = vim.fn.hlexists("FloatBorder") == 1 and "FloatBorder" or "WinSeparator"
    local title_target = vim.fn.hlexists("FloatTitle") == 1 and "FloatTitle" or "Title"
    local normal_target = vim.fn.hlexists("NormalFloat") == 1 and "NormalFloat" or "Normal"

    if vim.fn.hlexists(border_hl) == 0 then
        vim.api.nvim_set_hl(0, border_hl, { link = border_target })
    end
    if vim.fn.hlexists(title_hl) == 0 then
        vim.api.nvim_set_hl(0, title_hl, { link = title_target })
    end
    if vim.fn.hlexists(normal_hl) == 0 then
        vim.api.nvim_set_hl(0, normal_hl, { link = normal_target })
    end

    local winhl = string.format("Normal:%s,FloatBorder:%s,FloatTitle:%s", normal_hl, border_hl, title_hl)
    if focus then
        winhl = winhl .. string.format(
            ",Cursor:%s,lCursor:%s,CursorLine:%s,CursorLineNr:%s",
            normal_hl,
            normal_hl,
            normal_hl,
            normal_hl
        )
    end
    vim.wo[winid].winhl = winhl

    return winid, bufnr
end

---@return nil
local function clear_current()
    if state.current_winid and vim.api.nvim_win_is_valid(state.current_winid) then
        vim.api.nvim_win_close(state.current_winid, true)
    end
    if state.current_buf then
        local placeholders = require("pyrepl.image.placeholders")
        pcall(function()
            placeholders.wipe(state.current_buf)
        end)
    end
    pcall(vim.api.nvim_del_augroup_by_name, "PyreplImageResize")
    state.current_buf = nil
    state.current_winid = nil
    state.manager_active = false
end

---@return nil
local function setup_cursor_autocmd()
    local group = vim.api.nvim_create_augroup("PyreplImageClear", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function()
            clear_current()
            vim.api.nvim_del_augroup_by_name("PyreplImageClear")
        end,
        once = true
    })
end

---@param bufnr integer
---@param winid integer
---@return nil
local function setup_manager_autocmd(bufnr, winid)
    local group = vim.api.nvim_create_augroup("PyreplImageManagerClose", { clear = false })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = bufnr,
        callback = function()
            clear_current()
        end,
        once = true
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(winid),
        callback = function()
            clear_current()
        end,
        once = true
    })
end

---@param buf integer
---@param winid integer
---@return nil
local function setup_resize_autocmd(buf, winid)
    local group = vim.api.nvim_create_augroup("PyreplImageResize", { clear = true })
    vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
        group = group,
        callback = function()
            vim.schedule(function()
                require("pyrepl.image.placeholders").redraw(buf, winid)
            end)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "TabEnter" }, {
        group = group,
        callback = function()
            vim.schedule(function()
                require("pyrepl.image.placeholders").redraw(buf, winid)
            end)
        end,
    })
end

---@param bufnr integer
---@return nil
local function set_manager_keymaps(bufnr)
    local opts = { noremap = true, silent = true, nowait = true, buffer = bufnr }
    vim.keymap.set("n", "h", function()
        M.show_previous_image(true)
    end, opts)
    vim.keymap.set("n", "l", function()
        M.show_next_image(true)
    end, opts)
    vim.keymap.set("n", "q", function()
        clear_current()
    end, opts)
    vim.keymap.set("n", "<Esc>", function()
        clear_current()
    end, opts)
end

---@param entry pyrepl.ImageEntry
---@param focus boolean
---@param auto_clear boolean
---@return nil
local function render_image(entry, focus, auto_clear)
    local placeholders = require("pyrepl.image.placeholders")

    clear_current()

    local ok, buf = pcall(placeholders.create_buffer, entry.data)
    if not ok or not buf then
        vim.notify("PyREPL: Failed to load image.", vim.log.levels.WARN)
        return
    end

    local width_cells, height_cells = compute_window_cells()
    local winid, bufnr = create_image_float(width_cells, height_cells, focus, buf)
    placeholders.attach(buf, winid)
    state.current_buf = buf
    state.current_winid = winid
    setup_resize_autocmd(buf, winid)

    if focus then
        state.manager_active = true
        set_manager_keymaps(bufnr)
        setup_manager_autocmd(bufnr, winid)
    end

    if auto_clear then
        setup_cursor_autocmd()
    end
end

local MAX_HISTORY = 50

---@param entry pyrepl.ImageEntry
---@return nil
local function push_history(entry)
    if #state.history >= MAX_HISTORY then
        table.remove(state.history, 1)
    end
    table.insert(state.history, entry)
    state.history_index = #state.history
end

---@param index integer
---@param focus boolean
---@param auto_clear boolean
---@return nil
local function show_history_at(index, focus, auto_clear)
    if #state.history == 0 then
        vim.notify("PyREPL: No image history available.", vim.log.levels.WARN)
        return
    end
    if index < 1 or index > #state.history then
        return
    end
    local entry = state.history[index]
    state.history_index = index
    render_image(entry, focus, auto_clear)
end

---@param path string
---@return nil
function M.show_image_file(path)
    local normalized = path
    if type(normalized) ~= "string" or normalized == "" then
        vim.notify("PyREPL: Image path missing or invalid.", vim.log.levels.WARN)
        return
    end

    local abs = vim.fn.fnamemodify(normalized, ":p")
    if vim.fn.filereadable(abs) ~= 1 then
        vim.notify("PyREPL: Image file not readable.", vim.log.levels.WARN)
        return
    end

    local fd = (vim.uv or vim.loop).fs_open(abs, "r", 438)
    if not fd then
        vim.notify("PyREPL: Failed to read image file.", vim.log.levels.WARN)
        return
    end
    local stat = (vim.uv or vim.loop).fs_fstat(fd)
    local data = stat and (vim.uv or vim.loop).fs_read(fd, stat.size, 0) or nil
    (vim.uv or vim.loop).fs_close(fd)

    if not data or data == "" then
        vim.notify("PyREPL: Failed to read image file.", vim.log.levels.WARN)
        return
    end

    local encoded = vim.base64.encode(data)
    M.show_image_data(encoded)
end

---@param data string
---@return nil
function M.show_image_data(data)
    if type(data) ~= "string" or data == "" then
        vim.notify("PyREPL: Image data missing or invalid.", vim.log.levels.WARN)
        return
    end
    push_history({ data = data })
    show_history_at(#state.history, false, true)
end

---@return nil
function M.open_images()
    if #state.history == 0 then
        vim.notify("PyREPL: No image history available.", vim.log.levels.WARN)
        return
    end
    show_history_at(#state.history, true, false)
end

---@return nil
function M.show_last_image()
    show_history_at(#state.history, false, true)
end

---@param focus boolean|nil
---@return nil
function M.show_previous_image(focus)
    if #state.history == 0 then
        vim.notify("PyREPL: No image history available.", vim.log.levels.WARN)
        return
    end
    if state.history_index <= 1 then
        state.history_index = 1
        vim.notify("PyREPL: Already at oldest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(
        state.history_index - 1,
        focus or state.manager_active,
        not (focus or state.manager_active)
    )
end

---@param focus boolean|nil
---@return nil
function M.show_next_image(focus)
    if #state.history == 0 then
        vim.notify("PyREPL: No image history available.", vim.log.levels.WARN)
        return
    end
    if state.history_index >= #state.history then
        state.history_index = #state.history
        vim.notify("PyREPL: Already at newest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(
        state.history_index + 1,
        focus or state.manager_active,
        not (focus or state.manager_active)
    )
end

return M
