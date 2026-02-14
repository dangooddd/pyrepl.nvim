local M = {}

local util = require("pyrepl.util")

local group = vim.api.nvim_create_augroup("PyreplJupytext", { clear = true })
local template = [[
{
  "cells": [
    {
      "cell_type": "code",
      "execution_count": null,
      "metadata": {},
      "outputs": [],
      "source": []
    }
  ],
  "metadata": {
    "language_info": { "name": "python" }
  },
  "nbformat": 4,
  "nbformat_minor": 5
}
]]

---@param text string
---@param name string
---@param notebook boolean
local function convert(text, name, notebook)
    if name == "" then
        error("notebook name empty", 0)
    end

    if vim.fn.executable("jupytext") ~= 1 then
        error("jupytext executable not found", 0)
    end

    name = vim.fn.fnamemodify(name, ":r")
    local cmd
    local output_name

    if notebook then
        output_name = name .. ".ipynb"
        cmd = { "jupytext", "--update", "--output", output_name, "-" }
    else
        output_name = name .. ".py"
        cmd = { "jupytext", "--output", output_name, "-" }
    end

    local obj = vim.system(cmd, { text = true, stdin = text }):wait()

    if obj.code ~= 0 then
        error(obj.stderr, 0)
    end

    return output_name
end

---@param buf? integer
function M.open_in_notebook(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not util.is_valid_buf(buf) then return end

    local name = vim.api.nvim_buf_get_name(buf)
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    if #text == 0 then text = template end

    local ok, out = pcall(convert, text, name, false)
    if not ok then
        vim.notify(
            util.msg .. "failed to run jupytext: " .. out,
            vim.log.levels.ERROR
        )
        return
    end

    vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(out, ":.")))
end

---@param name? string
---@param buf? integer
function M.export_to_notebook(name, buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not util.is_valid_buf(buf) then return end
    if not vim.bo[buf].buftype == "python" then return end

    name = (name and name ~= "") and name or vim.api.nvim_buf_get_name(buf)
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

    vim.schedule(function()
        local ok, out = pcall(convert, text, name, true)
        if not ok then
            vim.notify(
                util.msg .. "failed to sync: " .. out,
                vim.log.levels.ERROR
            )
        else
            print(util.msg .. string.format('script exported to "%s"', out))
        end
    end)
end

function M.setup()
    -- skip setup when jupytext not installed
    if vim.fn.executable("jupytext") ~= 1 then return end

    -- prompt user to open notebook in python buffer when opening *.ipynb files
    vim.api.nvim_create_autocmd("BufReadPost", {
        group = group,
        pattern = "*.ipynb",
        callback = vim.schedule_wrap(function(args)
            local name = vim.api.nvim_buf_get_name(args.buf)
            name = vim.fn.fnamemodify(name, ":r") .. ".py"

            local stat = vim.uv.fs_stat(name)
            local choices = { "yes", "no" }

            if stat and stat.type == "file" then
                choices[#choices + 1] = "open existing file"
            end

            vim.ui.select(choices, {
                prompt = string.format('Convert notebook to "%s"?', name)
            }, function(choice)
                if choice == "yes" then
                    M.open_in_notebook(args.buf)
                elseif choice == "open existing file" then
                    vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(name, ":.")))
                end
            end)
        end)
    })
end

return M
