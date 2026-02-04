local state = require("pyrepl.state")
local util = require("pyrepl.util")

local M = {}

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

---@return pyrepl.KernelSpec[]|nil
local function list_kernels()
    local ok, kernels = pcall(vim.fn.ListKernels)
    if not ok then
        if string.find(kernels, "Unknown function") then
            vim.notify(
                "PyREPL: Remote plugin not loaded. Run :UpdateRemotePlugins and restart Neovim",
                vim.log.levels.ERROR
            )
        else
            vim.notify(
                string.format("PyREPL: Failed to list kernels: %s", kernels),
                vim.log.levels.ERROR
            )
        end
        return nil
    end

    if type(kernels) ~= "table" or #kernels == 0 then
        vim.notify(
            "PyREPL: No kernels found, install ipykernel first",
            vim.log.levels.ERROR
        )
        return nil
    end

    return kernels
end

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

---@param kernel_name string
---@return string|nil
local function init_kernel(kernel_name)
    local success, result = pcall(vim.fn.InitKernel, kernel_name)
    if not success then
        if string.find(result, "Unknown function") then
            vim.notify(
                "PyREPL: Remote plugin not loaded. Run :UpdateRemotePlugins and restart Neovim.",
                vim.log.levels.ERROR
            )
        else
            vim.notify(
                string.format("PyREPL: Kernel initialization failed: %s", result),
                vim.log.levels.ERROR
            )
        end
        return nil
    end

    if type(result) == "table" then
        if result.ok == true then
            local connection_file = result.connection_file
            if type(connection_file) ~= "string" or connection_file == "" then
                vim.notify("PyREPL: Kernel initialization failed with empty connection file.", vim.log.levels.ERROR)
                return nil
            end
            return connection_file
        end

        local error_type = result.error_type
        local error_message = result.error
        local requested_kernel_name = result.requested_kernel_name
        local effective_kernel_name = result.effective_kernel_name
        local spec_argv0 = result.spec_argv0

        local debug_parts = {}
        if type(requested_kernel_name) == "string" and requested_kernel_name ~= "" then
            table.insert(debug_parts, string.format("requested: %s", requested_kernel_name))
        end
        if type(effective_kernel_name) == "string" and effective_kernel_name ~= "" then
            table.insert(debug_parts, string.format("effective: %s", effective_kernel_name))
        end
        if type(spec_argv0) == "string" and spec_argv0 ~= "" then
            table.insert(debug_parts, string.format("argv0: %s", spec_argv0))
        end
        local debug_suffix = ""
        if #debug_parts > 0 then
            debug_suffix = string.format(" (%s)", table.concat(debug_parts, "; "))
        end

        if error_type == "no_such_kernel" then
            vim.notify(
                string.format(
                    "PyREPL: Kernel '%s' not found. Please install it manually (see README) and try again.",
                    kernel_name
                ),
                vim.log.levels.ERROR
            )
        elseif error_type == "missing_kernel_name" then
            vim.notify("PyREPL: Kernel name is missing.", vim.log.levels.ERROR)
        else
            local message = error_message or "Unknown error"
            vim.notify(
                string.format("PyREPL: Kernel initialization failed: %s%s", message, debug_suffix),
                vim.log.levels.ERROR
            )
        end
        return nil
    end

    if not result or result == "" then
        vim.notify(
            "PyREPL: Kernel initialization failed with empty connection file.",
            vim.log.levels.ERROR
        )
        return nil
    end

    return result
end

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

    pcall(vim.fn.ShutdownKernel, session.connection_file)
    pcall(os.remove, session.connection_file)
    session.connection_file = nil
    session.kernel_name = nil
end

return M
