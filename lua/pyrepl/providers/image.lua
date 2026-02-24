---@class pyrepl.ImageNvim: pyrepl.Image
---@field image Image|nil
---@field tmpfile string
local M = {}
M.__index = M

local api = require("image")

---@param img_base64 string
---@return pyrepl.ImageNvim|nil
function M.create(img_base64)
    local decoded = vim.base64.decode(img_base64)
    local tmpname = vim.fn.tempname() .. ".png"
    local tmpfile = io.open(tmpname, "wb")

    if not tmpfile then
        return
    end

    tmpfile:write(decoded)
    tmpfile:close()

    ---@type pyrepl.ImageNvim
    local self = setmetatable({}, M)

    local image = api.from_file(tmpname, {
        max_height_window_percentage = 100,
        max_width_window_percentage = 100,
    })

    if image then
        self.image = image
        self.tmpfile = tmpname
        return self
    end
end

---@param buf integer
---@param win integer
function M:render(buf, win)
    if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) and self.image) then
        return
    end

    local height = vim.api.nvim_win_get_height(win)
    local width = vim.api.nvim_win_get_width(win)

    self.image.buffer = buf
    self.image.window = win

    self.image:render({
        height = height,
        width = width,
    })

    self.image:move(
        math.floor(math.max(width - self.image.rendered_geometry.width, 0) / 2),
        math.floor(math.max(height - self.image.rendered_geometry.height, 0) / 2)
    )
end

function M:clear()
    if self.image then
        self.image:clear()
    end
end

function M:delete()
    if self.image then
        self:clear()
        os.remove(self.tmpfile)
        self.image = nil
    end
end

return M
