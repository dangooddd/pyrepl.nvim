local state = require("pyrepl.state")
local util = require("pyrepl.util")

local M = {}

---@return string|nil
local function validate_python_host()
    local host_prog = vim.g.python3_host_prog
    if host_prog == nil or host_prog == "" then
        host_prog = "python"
    elseif type(host_prog) ~= "string" then
        vim.notify("PyREPL: vim.g.python3_host_prog is not a string", vim.log.levels.ERROR)
        return nil
    end

    local python_path = vim.fn.expand(host_prog)
    if vim.fn.executable(python_path) == 0 then
        vim.notify(string.format("PyREPL: python3 executable not found (%s)", python_path), vim.log.levels.ERROR)
        return nil
    end

    return python_path
end

--- Check required Python packages in the host interpreter.
---@param python_host string
---@return boolean
local function check_dependencies(python_host)
    local check_cmd = {
        python_host,
        "-c",
        "import pynvim, jupyter_client, jupyter_console",
    }
    local result = vim.system(check_cmd, { text = true }):wait()
    if result and result.code == 0 then
        return true
    end

    vim.notify(
        "PyREPL: Missing Python packages (jupyter-console), check the docs for instructions",
        vim.log.levels.ERROR
    )
    return false
end

---@return string|nil
function M.ensure_python()
    if state.state.python_host then
        return state.state.python_host
    end

    local python_host = validate_python_host()
    if not python_host then
        return nil
    end

    if not check_dependencies(python_host) then
        return nil
    end

    state.state.python_host = python_host
    return python_host
end

--- List available Jupyter kernels via the remote plugin.
---@return pyrepl.KernelSpec[]|nil
local function list_kernels()
    local ok, result = pcall(vim.fn.ListKernels)
    if not ok then
        vim.notify(
            string.format("PyREPL: Failed to list kernels: %s", result),
            vim.log.levels.ERROR
        )
        return nil
    end

    if not result.ok then
        local message = result.message or "Failed to list kernels."
        vim.notify("PyREPL: " .. message, vim.log.levels.ERROR)
        return nil
    end

    local kernels = result.value
    if type(kernels) ~= "table" or #kernels == 0 then
        vim.notify(
            "PyREPL: No kernels found, install ipykernel first",
            vim.log.levels.ERROR
        )
        return nil
    end

    return kernels
end

--- Prefer a kernel that matches the active virtual environment.
---@param kernels pyrepl.KernelSpec[]
---@return integer
local function preferred_kernel_index(kernels)
    local venv = util.normalize_path(util.get_active_venv())
    if not venv then
        return 1
    end

    for idx, kernel in ipairs(kernels) do
        local kernel_venv_path = util.normalize_path(kernel.path)
        if util.has_path_prefix(kernel_venv_path, venv) then
            return idx
        end
    end

    return 1
end

---@param on_choice fun(name: string)
local function prompt_kernel_choice(on_choice)
    local kernels = list_kernels()
    if not kernels then
        return
    end

    local preferred = preferred_kernel_index(kernels)
    if preferred > 1 then
        local selected = table.remove(kernels, preferred)
        table.insert(kernels, 1, selected)
    end

    vim.ui.select(
        kernels,
        {
            prompt = "PyREPL: Select Jupyter kernel",
            format_item = function(item)
                local path = item.path
                if type(path) ~= "string" or path == "" then
                    return item.name
                end
                return string.format("%s  (%s)", item.name, path)
            end,
        },
        function(choice)
            if not choice then
                vim.notify("PyREPL: Kernel selection cancelled.", vim.log.levels.WARN)
                return
            end
            on_choice(choice.name)
        end
    )
end

--- Start a kernel via the remote plugin and return a connection file.
---@param kernel_name string
---@return string|nil
local function init_kernel(kernel_name)
    local ok, result = pcall(vim.fn.InitKernel, kernel_name)
    if not ok then
        vim.notify(
            string.format("PyREPL: Kernel initialization failed: %s", result),
            vim.log.levels.ERROR
        )
        return nil
    end

    if result.ok then
        return result.connection_file
    end

    local error_message = result.message
    local message = error_message or "Unknown error"
    vim.notify("PyREPL: " .. message, vim.log.levels.ERROR)
    return nil
end

--- Ensure a session has a running kernel and connection file.
---@param session pyrepl.Session
---@param callback fun(ok: boolean)
function M.ensure_kernel(session, callback)
    if session.connection_file then
        callback(true)
        return
    end

    prompt_kernel_choice(function(kernel_name)
        if not kernel_name or kernel_name == "" then
            vim.notify("PyREPL: Kernel name is missing.", vim.log.levels.ERROR)
            callback(false)
            return
        end

        local connection_file = init_kernel(kernel_name)
        if not connection_file then
            callback(false)
            return
        end

        session.connection_file = connection_file
        session.kernel_name = kernel_name
        callback(true)
    end)
end

---@param session pyrepl.Session|nil
function M.shutdown_kernel(session)
    if not session or not session.connection_file then
        return
    end

    local ok, result = pcall(vim.fn.ShutdownKernel, session.connection_file)
    if not ok then
        vim.notify(
            string.format("PyREPL: Kernel shutdown failed: %s", result),
            vim.log.levels.ERROR
        )
    elseif not result.ok then
        local message = result.message or "Kernel shutdown failed."
        vim.notify("PyREPL: " .. message, vim.log.levels.ERROR)
    end
    pcall(os.remove, session.connection_file)
    session.connection_file = nil
    session.kernel_name = nil
end

return M
