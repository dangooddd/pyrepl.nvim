local M = {}

-- Jupyter Console theme-overrides CLI argument uses Python tuples.
local pygments_hl_map = {
    ["('Text',)"] = { "Normal" },
    ["('Whitespace',)"] = { "Normal" },
    ["('Error',)"] = { "@error", "Error" },

    ["('Comment',)"] = { "@comment", "Comment" },
    ["('Comment','Preproc')"] = { "@keyword.directive", "PreProc" },
    ["('Comment','PreprocFile')"] = { "@keyword.import", "Include" },
    ["('Comment','Special')"] = { "@comment.documentation", "SpecialComment" },

    ["('Keyword',)"] = { "@keyword", "Keyword" },
    ["('Keyword','Constant')"] = { "@constant", "Constant" },
    ["('Keyword','Namespace')"] = { "@keyword.import", "Include" },
    ["('Keyword','Type')"] = { "@type", "Type" },

    ["('Operator',)"] = { "@operator", "Operator" },
    ["('Operator','Word')"] = { "@keyword.operator", "Operator" },
    ["('Punctuation',)"] = { "@punctuation", "Delimiter" },

    ["('Name',)"] = { "Normal" },
    ["('Name','Attribute')"] = { "@property", "Identifier" },
    ["('Name','Builtin')"] = { "@variable.builtin", "Special" },
    ["('Name','Builtin','Pseudo')"] = { "@variable.builtin", "Special" },
    ["('Name','Class')"] = { "@type", "Type" },
    ["('Name','Constant')"] = { "@constant", "Constant" },
    ["('Name','Decorator')"] = { "@attribute", "PreProc" },
    ["('Name','Exception')"] = { "@type", "Type" },
    ["('Name','Function')"] = { "@function", "Function" },
    ["('Name','Label')"] = { "@label", "Label" },
    ["('Name','Namespace')"] = { "@module", "Include" },
    ["('Name','Tag')"] = { "@tag", "Tag" },
    ["('Name','Variable')"] = { "@variable", "Identifier" },
    ["('Name','Variable','Magic')"] = { "@variable.builtin", "Special" },

    ["('Literal','String')"] = { "@string", "String" },
    ["('Literal','String','Char')"] = { "@character", "Character" },
    ["('Literal','String','Doc')"] = { "@string.documentation", "String" },
    ["('Literal','String','Escape')"] = { "@string.escape", "SpecialChar" },
    ["('Literal','String','Interpol')"] = { "@string.special", "SpecialChar" },
    ["('Literal','String','Regex')"] = { "@string.regex", "String" },

    ["('Literal','Number')"] = { "@number", "Number" },
    ["('Literal','Number','Float')"] = { "@number.float", "Float" },

    ["('Generic','Deleted')"] = { "@diff.minus", "DiffDelete" },
    ["('Generic','Inserted')"] = { "@diff.plus", "DiffAdd" },
    ["('Generic','Error')"] = { "@error", "Error" },
    ["('Generic','Output')"] = { "@comment", "Comment" },

    ["('Prompt',)"] = { "@comment", "Comment" },
    ["('PromptNum',)"] = { "@number", "Number" },
    ["('OutPrompt',)"] = { "@comment", "Comment" },
    ["('OutPromptNum',)"] = { "@number", "Number" },
}

local prompt_toolkit_hl_map = {
    ["readline-like-completions"] = "Pmenu",
    ["matching-bracket.other"] = "MatchParen",
    ["matching-bracket.cursor"] = "Cursor",

    ["completion-menu"] = "Pmenu",
    ["completion-menu.completion"] = "Pmenu",
    ["completion-menu.completion.current"] = "PmenuSel",
    ["completion-menu.meta.completion"] = "PmenuExtra",
    ["completion-menu.meta.completion.current"] = "PmenuExtraSel",
    ["completion-menu.multi-column-meta"] = "PmenuExtra",

    ["completion-toolbar"] = "Pmenu",
    ["completion-toolbar.completion.current"] = "PmenuSel",
}

---@param hl string
---@return string|nil
local function pygments_style_from_hl(hl)
    local parts = {}
    local style = vim.api.nvim_get_hl(0, {
        name = hl,
        link = false,
    })

    if style.fg then
        parts[#parts + 1] = string.format("fg:#%06x", style.fg)
    end

    if style.bg then
        parts[#parts + 1] = string.format("bg:#%06x", style.bg)
    end

    if #parts > 0 then
        return table.concat(parts, " ")
    end
end

---@return string|nil
function M.build_pygments_theme()
    local theme = {}

    for pygments_hls, hls in pairs(pygments_hl_map) do
        -- obtain style from candidates
        for _, hl in ipairs(hls) do
            local style = pygments_style_from_hl(hl)
            if style then
                theme[#theme + 1] = string.format("%s: '%s'", pygments_hls, style)
                break
            end
        end
    end

    if #theme == 0 then
        return nil
    end

    -- return a Python dictionary with color overrides.
    return "{" .. table.concat(theme, ", ") .. "}"
end

function M.build_prompt_toolkit_theme()
    local theme = {}

    for prompt_toolkit_hl, hl in pairs(prompt_toolkit_hl_map) do
        local style = pygments_style_from_hl(hl)
        if style then
            theme[prompt_toolkit_hl] = style
        end
    end

    if vim.tbl_isempty(theme) then
        return nil
    end

    return vim.json.encode(theme)
end

return M
