local M = {}

local config = require("pyrepl.config")
local packages = { "jupyter-console", "pynvim", "cairosvg", "pillow" }
local tools = { uv = "uv pip install -p %s", pip = "%s -m pip install" }
local python_path_cache
local console_path_cache
local console_completions_cache
local console_completions_running

---Resolve Python path from the following candidates:
---config.python_path -> vim.g.python3_host_prog -> "python3"
---@return string
function M.get_python_path()
    if python_path_cache then
        return python_path_cache
    end

    local candidates = {
        config.get_state().python_path or "",
        vim.g.python3_host_prog or "",
        "python3",
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

---@class pyrepl.KernelSpec
---@field name string
---@field resource_dir string

---List available Jupyter kernels.
---@return pyrepl.KernelSpec
local function list_kernels()
    local cmd = {
        M.get_python_path(),
        "-m",
        "jupyter_client.kernelspecapp",
        "list",
        "--json",
    }

    local obj = vim.system(cmd, { text = true }):wait()
    if obj.code ~= 0 then
        error(config.get_message_prefix() .. "failed to list kernels, try `:PyreplInstall`", 0)
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

---Feed the command to install required packages to the command line.
---@param tool string
function M.install_packages(tool)
    if not tools[tool] then
        vim.notify(
            config.get_message_prefix() .. string.format("unknown tool '%s'", tool),
            vim.log.levels.ERROR
        )
        return
    end

    local ok, python_path = pcall(M.get_python_path)
    if not ok then
        vim.notify(python_path, vim.log.levels.ERROR)
        return
    end

    local packages_string = table.concat(packages, " ")
    local cmd = tools[tool]:format(python_path) .. " " .. packages_string

    vim.api.nvim_feedkeys(":!" .. cmd, "n", true)
end

---@param stdout string|nil
local function parse_console_flags(stdout)
    local seen = {}
    local completions = {}

    for line in (stdout or ""):gmatch("[^\r\n]+") do
        for flag in line:gmatch("%-%-[%w][%w%._-]*") do
            if not seen[flag] then
                seen[flag] = true
                table.insert(completions, flag)
            end
        end
    end

    table.sort(completions, function(a, b)
        return a > b
    end)

    return completions
end

---@param reload boolean|nil
function M.load_console_completions(reload)
    if reload then
        console_completions_cache = nil
    end

    if console_completions_cache then
        return
    end

    if console_completions_running then
        return
    end
    console_completions_running = true

    pcall(function()
        vim.system({
            M.get_python_path(),
            "-m",
            "jupyter",
            "console",
            "--help-all",
        }, { text = true }, function(result)
            if result.code == 0 then
                console_completions_cache = parse_console_flags(result.stdout)
            end
            console_completions_running = false
        end)
    end)
end

---Get completions for Jupyter Console CLI flags.
---@param arglead string
---@return string[]
function M.get_console_completions(arglead)
    M.load_console_completions()
    return vim.tbl_filter(function(item)
        return vim.startswith(item, arglead)
    end, console_completions_cache or {})
end

---Get completions for tools.
---@param arglead string
---@return string[]
function M.get_tool_completions(arglead)
    return vim.tbl_filter(function(item)
        return vim.startswith(item, arglead)
    end, vim.tbl_keys(tools))
end

return M
