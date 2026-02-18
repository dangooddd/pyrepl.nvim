local M = {}

local api = require("image")

---@type (Image|nil)[]
local state = {}

function M.redraw(win, buf)
    if state[buf] then
        local height = vim.api.nvim_win_get_height(win)
        local width = vim.api.nvim_win_get_width(win)
        state[buf]:render({
            height = height,
            width = width,
        })

        -- keep image centered
        local geometry = state[buf].rendered_geometry
        state[buf]:move(
            math.floor(math.max(width - geometry.width, 0) / 2),
            math.floor(math.max(height - geometry.height, 0) / 2)
        )
    end
end

function M.render(img_data, buf, win)
    if not state[buf] then
        local decoded = vim.base64.decode(img_data)
        local tmpname = vim.fn.tempname() .. ".png"
        local tmpfile = assert(io.open(tmpname, "wb"))
        tmpfile:write(decoded)
        tmpfile:close()

        state[buf] = api.from_file(tmpname, {
            window = win,
            buffer = buf,
            max_height_window_percentage = 100,
            max_width_window_percentage = 100,
            with_virtual_padding = true,
        })
    end

    M.redraw(win, buf)
end

function M.clear(buf)
    if state[buf] then
        state[buf]:clear()
        state[buf] = nil
    end
end

return M
