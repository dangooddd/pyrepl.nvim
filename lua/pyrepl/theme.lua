local M = {}

-- jupyter console theme overrides CLI argument works with python tuples
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

---@param hl_name string
---@return string|nil
local function style_from_hl(hl_name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
        name = hl_name,
        link = false,
    })

    if not ok then
        return
    end

    if type(hl.fg) ~= "number" then
        return
    end

    return string.format("'#%06x'", hl.fg)
end

---@return string|nil
function M.build_pygments_theme()
    local theme = {}

    for pygments, hls in pairs(pygments_hl_map) do
        -- obtain style from candidates
        for _, hl in ipairs(hls) do
            local color = style_from_hl(hl)
            if color then
                theme[#theme + 1] = string.format("%s: %s", pygments, color)
                break
            end
        end
    end

    if #theme == 0 then
        return nil
    end

    -- return python dictionary with color overrides
    return "{" .. table.concat(theme, ", ") .. "}"
end

return M
