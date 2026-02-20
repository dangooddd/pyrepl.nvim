---@class pyrepl.ImageNvimObject
---@field obj Image
---@field tmpname string

---@type pyrepl.ImageProvider<pyrepl.ImageNvimObject>
local M = {}

local api = require("image")

---@param img_base64 string
---@param buf integer
---@param win integer
---@return pyrepl.ImageNvimObject|nil
function M.create(img_base64, buf, win)
    if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
        return
    end

    local decoded = vim.base64.decode(img_base64)
    local tmpname = vim.fn.tempname() .. ".png"
    local tmpfile = io.open(tmpname, "wb")

    if not tmpfile then
        return
    end

    tmpfile:write(decoded)
    tmpfile:close()

    local obj = api.from_file(tmpname, {
        window = win,
        buffer = buf,
        max_height_window_percentage = 100,
        max_width_window_percentage = 100,
        with_virtual_padding = true,
    })

    if not obj then
        return
    end

    local height = vim.api.nvim_win_get_height(win)
    local width = vim.api.nvim_win_get_width(win)

    obj:render({
        height = height,
        width = width,
    })

    obj:move(
        math.floor(math.max(width - obj.rendered_geometry.width, 0) / 2),
        math.floor(math.max(height - obj.rendered_geometry.height, 0) / 2)
    )

    return {
        obj = obj,
        tmpname = tmpname,
    }
end

---@param image pyrepl.ImageNvimObject|nil
function M.delete(image)
    if image then
        image.obj:clear()
        os.remove(image.tmpname)
    end
end

return M
