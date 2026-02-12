local M = {}

M.msg = "(pyrepl) "

local pygments_hl_map = {
    { pygments = "('Keyword',)",                  hl = "@keyword" },
    { pygments = "('Keyword','Namespace')",       hl = "@keyword.import" },
    { pygments = "('Keyword','Type')",            hl = "@type" },

    { pygments = "('Name',)",                     hl = "Normal" },
    { pygments = "('Name','Namespace')",          hl = "@type" },
    { pygments = "('Name','Builtin')",            hl = "@function" },
    { pygments = "('Name','Attribute')",          hl = "@variable" },
    { pygments = "('Name','Function')",           hl = "@function" },
    { pygments = "('Name','Class')",              hl = "@type" },
    { pygments = "('Name','Exception')",          hl = "@type" },
    { pygments = "('Name','Decorator')",          hl = "@function" },
    { pygments = "('Name','Constant')",           hl = "@constant" },
    { pygments = "('Name','Variable')",           hl = "@variable" },
    { pygments = "('Name','Variable','Magic')",   hl = "@variable" },

    { pygments = "('Literal','String')",          hl = "@string" },
    { pygments = "('Literal','String','Doc')",    hl = "@string" },
    { pygments = "('Literal','String','Escape')", hl = "@string" },
    { pygments = "('Literal','Number')",          hl = "@number" },

    { pygments = "('Comment',)",                  hl = "@comment" },
    { pygments = "('Operator',)",                 hl = "@operator" },
    { pygments = "('Punctuation',)",              hl = "@punctuation" },

    { pygments = "('Prompt',)",                   hl = "Special" },
    { pygments = "('PromptNum',)",                hl = "Number" },
    { pygments = "('OutPrompt',)",                hl = "Special" },
    { pygments = "('OutPromptNum',)",             hl = "Number" },
    { pygments = "('RemotePrompt',)",             hl = "Comment" },
}

---@param value string
---@return string
local function python_quote(value)
    local escaped = value:gsub("\\", "\\\\"):gsub("'", "\\'")
    return "'" .. escaped .. "'"
end

---@param hl_name string
---@return string|nil
local function style_from_hl(hl_name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
        name = hl_name,
        link = false,
    })
    if not ok or type(hl) ~= "table" or next(hl) == nil then
        return nil
    end

    if type(hl.fg) ~= "number" then return nil end
    return string.format("#%06x", hl.fg)
end

---@param buf any
function M.is_valid_buf(buf)
    return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

---@param win any
function M.is_valid_win(win)
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

---@param num any
---@param min number
---@param max number
---@param fallback number
---@return number
function M.clip(num, min, max, fallback)
    num = tonumber(num)
    if not num then return fallback end
    if num < min then return min end
    if num > max then return max end
    return num
end

---@return integer
---@return integer
function M.get_visual_range()
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    if (start_pos[1] == 0 and start_pos[2] == 0)
        or (end_pos[1] == 0 and end_pos[2] == 0)
    then
        return 0, 0
    end

    local start_line, end_line = start_pos[1], end_pos[1]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    return start_line, end_line
end

---@param block_pattern string
---@return integer
---@return integer
function M.get_block_range(block_pattern)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #lines == 0 then return 0, 0 end

    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

    -- block start
    local start_line = 1
    for i = cursor_line, 1, -1 do
        if lines[i]:match(block_pattern) then
            start_line = i + 1
            break
        end
    end

    -- block end
    local end_line = #lines
    for i = cursor_line + 1, #lines do
        if lines[i]:match(block_pattern) then
            end_line = i - 1
            break
        end
    end

    if start_line > end_line then return 0, 0 end
    return start_line, end_line
end

---@param hl_group string
---@param pygments string
---@return string|nil
function M.pygments_field_from_hl(hl_group, pygments)
    local style = style_from_hl(hl_group)
    if not style then return nil end

    return string.format("%s: %s", pygments, python_quote(style))
end

---@param style_treesitter boolean
---@return string|nil
function M.build_pygments_overrides_literal(style_treesitter)
    if not style_treesitter then return nil end

    local fields = {}

    for _, item in ipairs(pygments_hl_map) do
        local field = M.pygments_field_from_hl(item.hl, item.pygments)
        if field then fields[#fields + 1] = field end
    end

    if #fields == 0 then return nil end
    return "{" .. table.concat(fields, ", ") .. "}"
end

return M
