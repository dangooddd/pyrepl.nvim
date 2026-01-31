local api = vim.api
local fn = vim.fn

local M = {}

local default_image_config = {
    cell_width = 10,
    cell_height = 20,
    max_width_ratio = 0.5,
    max_height_ratio = 0.5
}

local image_config = vim.deepcopy(default_image_config)

local function refresh_image_config()
    local ok, pyrola = pcall(require, "pyrola")
    if ok and pyrola.config and pyrola.config.image then
        image_config = vim.tbl_deep_extend("force", vim.deepcopy(default_image_config), pyrola.config.image)
    else
        image_config = vim.deepcopy(default_image_config)
    end
end

local function ensure_image_module()
    local ok, image = pcall(require, "image")
    if ok then
        return image
    end
    vim.notify("Pyrola: image.nvim not available. Install '3rd/image.nvim' to render images.", vim.log.levels.WARN)
    return nil
end

local function pixels_to_cells(pixels, is_width)
    local cell_width = tonumber(image_config.cell_width) or default_image_config.cell_width
    local cell_height = tonumber(image_config.cell_height) or default_image_config.cell_height
    if is_width then
        return math.max(1, math.ceil(pixels / cell_width))
    end
    return math.max(1, math.ceil(pixels / cell_height))
end

local function compute_window_cells(width_px, height_px)
    local max_width_ratio = tonumber(image_config.max_width_ratio) or default_image_config.max_width_ratio
    local max_height_ratio = tonumber(image_config.max_height_ratio) or default_image_config.max_height_ratio
    local max_width_cells = math.max(1, math.floor(vim.o.columns * max_width_ratio))
    local max_height_cells = math.max(1, math.floor(vim.o.lines * max_height_ratio))

    if not width_px or not height_px then
        return max_width_cells, max_height_cells
    end

    local width_cells = pixels_to_cells(width_px, true)
    local height_cells = pixels_to_cells(height_px, false)
    return math.min(width_cells, max_width_cells), math.min(height_cells, max_height_cells)
end

local function create_image_float(width_cells, height_cells, focus)
    local win_width = vim.o.columns
    local win_height = vim.o.lines

    local float_width = math.max(4, width_cells + 2)
    local float_height = math.max(4, height_cells + 2)

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

    local bufnr = api.nvim_create_buf(false, true)
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].buftype = "nofile"

    local winid = api.nvim_open_win(bufnr, focus or false, opts)

    local border_hl = "PyrolaImageBorder"
    local title_hl = "PyrolaImageTitle"
    local normal_hl = "PyrolaImageNormal"

    if not M._image_highlights_set then
        local border_target = fn.hlexists("FloatBorder") == 1 and "FloatBorder" or "WinSeparator"
        local title_target = fn.hlexists("FloatTitle") == 1 and "FloatTitle" or "Title"
        local normal_target = fn.hlexists("NormalFloat") == 1 and "NormalFloat" or "Normal"

        if fn.hlexists(border_hl) == 0 then
            api.nvim_set_hl(0, border_hl, { link = border_target })
        end
        if fn.hlexists(title_hl) == 0 then
            api.nvim_set_hl(0, title_hl, { link = title_target })
        end
        if fn.hlexists(normal_hl) == 0 then
            api.nvim_set_hl(0, normal_hl, { link = normal_target })
        end
        M._image_highlights_set = true
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

local function clear_current()
    if M.current_image then
        pcall(function()
            M.current_image:clear()
        end)
        M.current_image = nil
    end
    if M.current_winid and api.nvim_win_is_valid(M.current_winid) then
        api.nvim_win_close(M.current_winid, true)
    end
    M.current_winid = nil
    M.current_bufid = nil
    if M.manager_guicursor then
        vim.o.guicursor = M.manager_guicursor
        M.manager_guicursor = nil
    end
    M.manager_active = false
    M.manager_winid = nil
    M.manager_bufid = nil
end

local function setup_cursor_autocmd()
    local group = api.nvim_create_augroup("PyrolaImageClear", { clear = true })
    api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function()
            clear_current()
            api.nvim_del_augroup_by_name("PyrolaImageClear")
        end,
        once = true
    })
end

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
end

local function render_image(entry, focus, auto_clear)
    local image = ensure_image_module()
    if not image then
        return
    end
    refresh_image_config()

    clear_current()

    local width_cells, height_cells = compute_window_cells(entry.width, entry.height)
    local winid, bufnr = create_image_float(width_cells, height_cells, focus)

    local img = image.from_file(entry.path, {
        window = winid,
        buffer = bufnr
    })

    img:render({
        x = 1,
        y = 1,
        width = width_cells,
        height = height_cells
    })

    M.current_image = img
    M.current_winid = winid
    M.current_bufid = bufnr

    if focus then
        M.manager_winid = winid
        M.manager_bufid = bufnr
        M.manager_active = true
        set_manager_keymaps(bufnr)
        if not M.manager_guicursor then
            M.manager_guicursor = vim.o.guicursor
            vim.o.guicursor = "a:ver1-Cursor"
        end
    end

    if auto_clear then
        setup_cursor_autocmd()
    end
end

M.history = {}
M.history_index = 0
M.current_image = nil
M.current_winid = nil
M.current_bufid = nil
M.manager_active = false
M.manager_winid = nil
M.manager_bufid = nil
M.manager_guicursor = nil

local MAX_HISTORY = 50

local function push_history(entry)
    if #M.history >= MAX_HISTORY then
        table.remove(M.history, 1)
    end
    table.insert(M.history, entry)
    M.history_index = #M.history
end

local function show_history_at(index, focus, auto_clear)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if index < 1 or index > #M.history then
        return
    end
    local entry = M.history[index]
    M.history_index = index
    render_image(entry, focus, auto_clear)
end

function M.show_image_file(path, width, height)
    if type(path) ~= "string" or path == "" then
        vim.notify("Pyrola: Image path missing or invalid.", vim.log.levels.WARN)
        return
    end
    local width_num = tonumber(width)
    local height_num = tonumber(height)
    if not width_num or width_num <= 0 then
        width_num = nil
    end
    if not height_num or height_num <= 0 then
        height_num = nil
    end
    push_history({ path = path, width = width_num, height = height_num })
    show_history_at(#M.history, false, true)
end

function M.open_history_manager()
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    show_history_at(#M.history, true, false)
end

function M.show_last_image()
    show_history_at(#M.history, false, true)
end

function M.show_previous_image(focus)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if M.history_index <= 1 then
        M.history_index = 1
        vim.notify("Pyrola: Already at oldest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(M.history_index - 1, focus or M.manager_active, not (focus or M.manager_active))
end

function M.show_next_image(focus)
    if #M.history == 0 then
        vim.notify("Pyrola: No image history available.", vim.log.levels.WARN)
        return
    end
    if M.history_index >= #M.history then
        M.history_index = #M.history
        vim.notify("Pyrola: Already at newest image.", vim.log.levels.INFO)
        return
    end
    show_history_at(M.history_index + 1, focus or M.manager_active, not (focus or M.manager_active))
end

return M
