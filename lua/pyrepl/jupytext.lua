local M = {}

local config = require("pyrepl.config")
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

---@param path string
local function edit_relative(path)
    local relative = vim.fn.fnamemodify(path, ":.")
    vim.cmd.edit(vim.fn.fnameescape(relative))
end

---@param buf integer
local function get_buf_text(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return table.concat(lines, "\n")
end

---@param buf integer
---@param ext string
local function bufname_with_ext(buf, ext)
    local name = vim.api.nvim_buf_get_name(buf)
    return vim.fn.fnamemodify(name, ":r") .. "." .. ext
end

---@param text string
---@param name string
---@param notebook boolean
local function convert_text(text, name, notebook)
    if name == "" then
        error("notebook name empty", 0)
    end

    if vim.fn.executable("jupytext") ~= 1 then
        error("jupytext executable not found", 0)
    end

    local cmd
    if notebook then
        cmd = { "jupytext", "--update", "--output", name, "--to", "ipynb", "-" }
    else
        cmd = { "jupytext", "--output", name, "--to", "py:percent", "-" }
    end

    local obj = vim.system(cmd, { text = true, stdin = text }):wait()
    if obj.code ~= 0 then
        error(obj.stderr, 0)
    end
end

---@param buf integer
function M.convert_to_python(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local name = bufname_with_ext(buf, "py")
    local stat = vim.uv.fs_stat(name)
    local choices = { "yes", "no" }

    if stat and stat.type == "file" then
        choices[#choices + 1] = "open existing file"
    end

    vim.ui.select(choices, {
        prompt = string.format('Convert notebook to "%s"?', name),
    }, function(choice)
        if choice == "yes" then
            local text = get_buf_text(buf)
            if #text == 0 then
                text = template
            end

            local ok, error = pcall(convert_text, text, name, false)
            if not ok then
                vim.notify(
                    config.get_message_prefix() .. "failed to run jupytext: " .. error,
                    vim.log.levels.ERROR
                )
            else
                edit_relative(name)
            end
        elseif choice == "open existing file" then
            edit_relative(name)
        end
    end)
end

---@param buf integer
function M.export_to_notebook(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local name = bufname_with_ext(buf, "ipynb")
    local text = get_buf_text(buf)

    vim.schedule(function()
        local ok, error = pcall(convert_text, text, name, true)
        if not ok then
            vim.notify(
                config.get_message_prefix() .. "failed to sync: " .. error,
                vim.log.levels.ERROR
            )
        else
            print(config.get_message_prefix() .. string.format('script exported to "%s"', name))
        end
    end)
end

return M
