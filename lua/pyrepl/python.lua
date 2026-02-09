local M = {}

local python_path_cache = nil
local console_path_cache = nil

local packages = { "jupyter-console", "pynvim" }
local tools = {
    uv = "uv pip install -p %s",
    pip = "%s -m pip install",
}

---@return string|nil
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
        end
    end

    if not python_path_cache then
        vim.notify(
            "Pyrepl: can't find correct python executable, see docs.",
            vim.log.levels.ERROR
        )
    end

    return python_path_cache
end

---@return string|nil
function M.get_console_path()
    if console_path_cache then return console_path_cache end

    local candidates = vim.api.nvim_get_runtime_file("src/pyrepl", false)
    if candidates and #candidates > 0 then
        console_path_cache = candidates[1]
        return console_path_cache
    end

    vim.notify(
        "Pyrepl: Pyrepl main script not found.",
        vim.log.levels.ERROR
    )
end

--- List of available kernels
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
            "Pyrepl: Failed to get kernelspec. Is required packages installed?",
            vim.log.levels.ERROR
        )
        return {}
    end

    local ok, specs = pcall(vim.json.decode, obj.stdout)
    if not ok then
        vim.notify(
            "Pyrepl: Failed to decode kernelspec json.",
            vim.log.levels.ERROR
        )
        return {}
    end

    local kernels = {}

    for name, spec in pairs(specs["kernelspecs"]) do
        local index = #kernels + 1
        if name == require("pyrepl").config.preferred_kernel then index = 1 end
        kernels[index] = { name = name, resource_dir = spec.resource_dir }
    end

    return kernels
end

--- Prompts user to choose from available kernels.
---@param callback fun(name: string)
function M.prompt_kernel(callback)
    local kernels = list_kernels()
    if #kernels == 0 then return end

    vim.ui.select(
        kernels,
        {
            prompt = "Pyrepl: Select Jupyter kernel",
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
            string.format("Pyrepl: Unknown tool to install: %s.", tool),
            vim.log.levels.ERROR
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
function M.get_tools()
    local tool_list = {}

    for tool, _ in pairs(tools) do
        tool_list[#tool_list + 1] = tool
    end

    return tool_list
end

return M
