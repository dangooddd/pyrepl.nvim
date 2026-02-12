local M = {}

M.msg = "(pyrepl) "

-- We need to pass python tuples in jupyter console overrides CLI arguments
local pygments_hl_map = {
    ["('Text',)"]                       = { "Normal" },
    ["('Whitespace',)"]                 = { "Normal" },
    ["('Error',)"]                      = { "@error", "Error" },

    ["('Comment',)"]                    = { "@comment", "Comment" },
    ["('Comment','Preproc')"]           = { "@keyword.directive", "PreProc" },
    ["('Comment','PreprocFile')"]       = { "@keyword.import", "Include" },
    ["('Comment','Special')"]           = { "@comment.documentation", "SpecialComment" },

    ["('Keyword',)"]                    = { "@keyword", "Keyword" },
    ["('Keyword','Constant')"]          = { "@constant", "Constant" },
    ["('Keyword','Namespace')"]         = { "@keyword.import", "Include" },
    ["('Keyword','Type')"]              = { "@type", "Type" },

    ["('Operator',)"]                   = { "@operator", "Operator" },
    ["('Operator','Word')"]             = { "@keyword.operator", "Operator" },
    ["('Punctuation',)"]                = { "@punctuation", "Delimiter" },

    ["('Name',)"]                       = { "Normal" },
    ["('Name','Attribute')"]            = { "@property", "Identifier" },
    ["('Name','Builtin')"]              = { "@variable.builtin", "Special" },
    ["('Name','Builtin','Pseudo')"]     = { "@variable.builtin", "Special" },
    ["('Name','Class')"]                = { "@type", "Type" },
    ["('Name','Constant')"]             = { "@constant", "Constant" },
    ["('Name','Decorator')"]            = { "@attribute", "PreProc" },
    ["('Name','Exception')"]            = { "@type", "Type" },
    ["('Name','Function')"]             = { "@function", "Function" },
    ["('Name','Label')"]                = { "@label", "Label" },
    ["('Name','Namespace')"]            = { "@module", "Include" },
    ["('Name','Tag')"]                  = { "@tag", "Tag" },
    ["('Name','Variable')"]             = { "@variable", "Identifier" },
    ["('Name','Variable','Magic')"]     = { "@variable.builtin", "Special" },

    ["('Literal','String')"]            = { "@string", "String" },
    ["('Literal','String','Char')"]     = { "@character", "Character" },
    ["('Literal','String','Doc')"]      = { "@string.documentation", "String" },
    ["('Literal','String','Escape')"]   = { "@string.escape", "SpecialChar" },
    ["('Literal','String','Interpol')"] = { "@string.special", "SpecialChar" },
    ["('Literal','String','Regex')"]    = { "@string.regex", "String" },

    ["('Literal','Number')"]            = { "@number", "Number" },
    ["('Literal','Number','Float')"]    = { "@number.float", "Float" },

    ["('Generic','Deleted')"]           = { "@diff.minus", "DiffDelete" },
    ["('Generic','Inserted')"]          = { "@diff.plus", "DiffAdd" },
    ["('Generic','Error')"]             = { "@error", "Error" },
    ["('Generic','Output')"]            = { "@comment", "Comment" },

    ["('Prompt',)"]                     = { "@comment", "Comment" },
    ["('PromptNum',)"]                  = { "@number", "Number" },
    ["('OutPrompt',)"]                  = { "@comment", "Comment" },
    ["('OutPromptNum',)"]               = { "@number", "Number" },
}

---@param hl_name string
---@return string|nil
local function style_from_hl(hl_name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
        name = hl_name,
        link = false,
    })

    if not ok then return end
    if type(hl.fg) ~= "number" then return end

    return string.format("'#%06x'", hl.fg)
end

---@return string|nil
function M.build_pygments_theme()
    local theme = {}

    for pygments, hls in pairs(pygments_hl_map) do
        for _, hl in ipairs(hls) do
            local color = style_from_hl(hl)
            if color then
                theme[#theme + 1] = string.format("%s: %s", pygments, color)
                break
            end
        end
    end

    if #theme == 0 then return nil end
    return "{" .. table.concat(theme, ", ") .. "}"
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
    if #lines == 0 then return -1, -1 end

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

    if start_line > end_line then return -1, -1 end
    return start_line, end_line
end

return M
