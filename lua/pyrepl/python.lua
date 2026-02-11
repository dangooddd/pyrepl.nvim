local M = {}

local util = require("pyrepl.util")

local python_path_cache = nil
local console_path_cache = nil

local packages = { "jupyter-console", "pynvim", "cairosvg", "pillow" }
local tools = {
    uv = "uv pip install -p %s",
    pip = "%s -m pip install",
}

---@return string
function M.get_python_path()
    if python_path_cache then return python_path_cache end

    local candidates = {
        require("pyrepl").config.python_path,
        vim.g.python3_host_prog,
        "python",
    }

    for _, candidate in ipairs(candidates) do
        candidate = vim.fn.expand(candidate)
        if vim.fn.executable(candidate) == 1 then
            python_path_cache = vim.fn.exepath(candidate)
            return python_path_cache
        end
    end

    error(util.msg .. "can't find correct python executable, see docs", 0)
end

---@return string
function M.get_console_path()
    if console_path_cache then return console_path_cache end

    local candidates = vim.api.nvim_get_runtime_file("src/pyrepl/console.py", false)
    if candidates and #candidates > 0 then
        console_path_cache = candidates[1]
        return console_path_cache
    end

    error(util.msg .. "console script not found", 0)
end

--- List of available kernels
---@return { name: string, resource_dir: string }[]
local function list_kernels()
    local python_path = M.get_python_path()
    if not python_path then return {} end

    local cmd = {
        python_path,
        "-m",
        "jupyter",
        "kernelspec",
        "list",
        "--json"
    }

    local obj = vim.system(cmd, { text = true }):wait()
    if obj.code ~= 0 then
        vim.notify(
            util.msg .. "install required packages first",
            vim.log.levels.WARN
        )
        return {}
    end

    local ok, specs = pcall(vim.json.decode, obj.stdout)
    if not ok then
        error(util.msg .. "failed to decode kernelspecs json", 0)
    end

    local kernels = {}

    for name, spec in pairs(specs["kernelspecs"]) do
        local index = #kernels + 1
        local item = { name = name, resource_dir = spec.resource_dir }
        if name == require("pyrepl").config.preferred_kernel then index = 1 end
        table.insert(kernels, index, item)
    end

    return kernels
end

---@param callback fun(kernel: string)
function M.prompt_kernel(callback)
    local kernels = list_kernels()
    if #kernels == 0 then return end

    vim.ui.select(
        kernels,
        {
            prompt = "Select Jupyter kernel",
            format_item = function(item)
                return string.format("%s (%s)", item.name, item.resource_dir)
            end,
        },
        function(choice)
            if choice then
                callback(choice.name)
            end
        end
    )
end

--- Feed command to install required packages in command line.
---@param tool string
function M.install_packages(tool)
    if not tools[tool] then
        vim.notify(
            util.msg .. "unknown tool to install packages",
            vim.log.levels.WARN
        )
        return
    end

    local python_path = M.get_python_path()
    if not python_path then return end

    local packages_string = table.concat(packages, " ")
    local cmd = tools[tool]:format(python_path) .. " " .. packages_string

    vim.api.nvim_feedkeys(":!" .. cmd, "n", true)
end

--- Get available tool list (completion function for install_packages).
---@return string[]
function M.get_tools()
    local tool_list = {}

    for tool, _ in pairs(tools) do
        tool_list[#tool_list + 1] = tool
    end

    return tool_list
end

return M
