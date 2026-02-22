---@type pyrepl.ImageProvider<Image>
local M = {}

local api = require("image")

local cache = {}

---@param img_base64 string
---@return string|nil
local function get_file_from_base64(img_base64)
    local img_sha256 = vim.fn.sha256(img_base64)

    -- create temp file from base64 string
    if not cache[img_sha256] then
        local decoded = vim.base64.decode(img_base64)
        local tmpname = vim.fn.tempname() .. ".png"
        local tmpfile = io.open(tmpname, "wb")

        if not tmpfile then
            return
        end

        tmpfile:write(decoded)
        tmpfile:close()

        cache[img_sha256] = tmpname
    end

    return cache[img_sha256]
end

---@param img_base64 string
---@param buf integer
---@param win integer
---@return Image|nil
function M.create(img_base64, buf, win)
    if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
        return
    end

    local tmpname = get_file_from_base64(img_base64)
    if not tmpname then
        return
    end

    local img = api.from_file(tmpname, {
        window = win,
        buffer = buf,
        max_height_window_percentage = 100,
        max_width_window_percentage = 100,
        with_virtual_padding = true,
    })

    if not img then
        return
    end

    local height = vim.api.nvim_win_get_height(win)
    local width = vim.api.nvim_win_get_width(win)

    img:render({
        height = height,
        width = width,
    })

    img:move(
        math.floor(math.max(width - img.rendered_geometry.width, 0) / 2),
        math.floor(math.max(height - img.rendered_geometry.height, 0) / 2)
    )

    return img
end

---@param img Image|nil
function M.delete(img)
    if img then
        img:clear()
    end
end

return M
