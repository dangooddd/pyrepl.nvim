local M = {}

local config = require("pyrepl.config")
local packages = { "jupyter-console", "pynvim", "cairosvg", "pillow" }
local tools = {
    uv = "uv pip install -p %s",
    pip = "%s -m pip install",
}
local python_path_cache
local console_path_cache

---Resolve python path from candidates:
---1) config.python_path;
---2) vim.g.python3_host_prog;
---3) "python".
---@return string
function M.get_python_path()
    if python_path_cache then
        return python_path_cache
    end

    local candidates = {
        config.get_state().python_path,
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

    error(config.get_message_prefix() .. "python executable not found, configure `python_path`", 0)
end

---@return string
function M.get_console_path()
    if console_path_cache then
        return console_path_cache
    end

    local candidates = vim.api.nvim_get_runtime_file("src/pyrepl/console.py", false)
    if candidates and #candidates > 0 then
        console_path_cache = candidates[1]
        return console_path_cache
    end

    error(config.get_message_prefix() .. "console script not found, potential bug", 0)
end

---List of available jupyter kernels.
---@return pyrepl.KernelSpec
local function list_kernels()
    local cmd = {
        M.get_python_path(),
        "-m",
        "jupyter",
        "kernelspec",
        "list",
        "--json",
    }

    local obj = vim.system(cmd, { text = true }):wait()
    if obj.code ~= 0 then
        error(config.get_message_prefix() .. "failed to list kernels, see `:PyreplInstall`", 0)
    end

    local ok, specs = pcall(vim.json.decode, obj.stdout)
    if not ok then
        error(config.get_message_prefix() .. "failed to decode kernelspecs json", 0)
    end

    local kernels = {}

    for name, spec in pairs(specs["kernelspecs"]) do
        local index = #kernels + 1
        local item = { name = name, resource_dir = spec.resource_dir }
        if name == config.get_state().preferred_kernel then
            index = 1
        end
        table.insert(kernels, index, item)
    end

    return kernels
end

---Prompt user to choose kernel and call callback with that choice.
---@param callback fun(kernel: string)
function M.prompt_kernel(callback)
    local ok, kernels = pcall(list_kernels)

    if not ok then
        vim.notify(kernels --[[@as string]], vim.log.levels.ERROR)
        return
    end

    vim.ui.select(kernels, {
        prompt = "Select Jupyter kernel",
        format_item = function(item)
            return string.format("%s (%s)", item.name, item.resource_dir)
        end,
    }, function(choice)
        if choice then
            callback(choice.name)
        end
    end)
end

---Feed command to install required packages in command line.
---@param tool string
function M.install_packages(tool)
    if not tools[tool] then
        vim.notify(config.get_message_prefix() .. "unknown tool " .. tool, vim.log.levels.ERROR)
        return
    end

    local python_path = M.get_python_path()
    local packages_string = table.concat(packages, " ")
    local cmd = tools[tool]:format(python_path) .. " " .. packages_string

    vim.api.nvim_feedkeys(":!" .. cmd, "n", true)
end

---Get available tool list (completion function for install_packages).
---@return string[]
function M.get_tools()
    return vim.tbl_keys(tools)
end

return M
