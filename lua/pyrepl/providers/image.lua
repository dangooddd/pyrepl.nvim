local M = {}

local api = require("image")

---@class image.ImageEntry
---@field image Image
---@field tmpname string

---@type (image.ImageEntry|nil)[]
local state = {}

---@param buf integer
---@param win integer
function M.redraw(buf, win)
    if state[buf] then
        local height = vim.api.nvim_win_get_height(win)
        local width = vim.api.nvim_win_get_width(win)
        state[buf].image:render({
            height = height,
            width = width,
        })

        -- keep image centered
        local geometry = state[buf].image.rendered_geometry
        state[buf].image:move(
            math.floor(math.max(width - geometry.width, 0) / 2),
            math.floor(math.max(height - geometry.height, 0) / 2)
        )
    end
end

---@param img_data string
---@param buf integer
---@param win integer
function M.render(img_data, buf, win)
    M.clear(buf)
    local decoded = vim.base64.decode(img_data)
    local tmpname = vim.fn.tempname() .. ".png"
    local tmpfile = assert(io.open(tmpname, "wb"))
    tmpfile:write(decoded)
    tmpfile:close()

    local image = assert(api.from_file(tmpname, {
        window = win,
        buffer = buf,
        max_height_window_percentage = 100,
        max_width_window_percentage = 100,
        with_virtual_padding = true,
    }))

    state[buf] = { image = image, tmpname = tmpname }
    M.redraw(buf, win)
end

---@param buf integer
function M.clear(buf)
    if state[buf] then
        state[buf].image:clear()
        os.remove(state[buf].tmpname)
        state[buf] = nil
    end
end

return M
