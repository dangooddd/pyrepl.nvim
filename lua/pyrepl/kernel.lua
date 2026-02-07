local M = {}

local python_path = nil
local console_path = nil

---@return string|nil
function M.get_python_path()
    if python_path then return python_path end

    local host_prog = vim.g.python3_host_prog
    if host_prog == nil or host_prog == "" then
        host_prog = "python"
    elseif type(host_prog) ~= "string" then
        vim.notify("Pyrepl: vim.g.python3_host_prog is not a string", vim.log.levels.ERROR)
        return nil
    end

    local python_host = vim.fn.expand(host_prog)
    if vim.fn.executable(python_host) == 0 then
        vim.notify(string.format("Pyrepl: python3 executable not found (%s)", python_path), vim.log.levels.ERROR)
        return nil
    end

    python_path = python_host
    return python_path
end

--- Find the console.py script in runtimepath (cached).
---@return string|nil
function M.get_console_path()
    if console_path then return console_path end

    local candidates = vim.api.nvim_get_runtime_file(
        "rplugin/python3/pyrepl/console.py",
        false
    )

    if candidates and #candidates > 0 then
        console_path = candidates[1]
        return console_path
    end

    return nil
end

--- List available Jupyter kernels via the remote plugin.
---@return pyrepl.KernelSpec[]|nil
local function list_kernels()
    local result = vim.fn.ListKernels()
    if not result.ok then
        local message = result.message or "Failed to list kernels."
        vim.notify("Pyrepl: " .. message, vim.log.levels.ERROR)
        return nil
    end

    local kernels = result.value
    if type(kernels) ~= "table" or #kernels == 0 then
        vim.notify(
            "Pyrepl: No kernels found, install ipykernel first",
            vim.log.levels.ERROR
        )
        return nil
    end

    return kernels
end

---@return string|nil
local function get_active_venv()
    local venv = vim.env.VIRTUAL_ENV
    if venv and venv ~= "" then
        return venv
    end

    local conda = vim.env.CONDA_PREFIX
    if conda and conda ~= "" then
        return conda
    end

    return nil
end

---@param path string|nil
---@return string|nil
local function normalize_path(path)
    if not path or path == "" then return nil end
    path = vim.fn.fnamemodify(path, ":p")
    path = path:gsub("/+$", "")
    return path
end

---@param path string|nil
---@param prefix string|nil
---@return boolean
local function has_path_prefix(path, prefix)
    if not path or not prefix then
        return false
    end

    if path == prefix then
        return true
    end

    local sep = "/"
    if prefix:sub(-1) ~= sep then
        prefix = prefix .. sep
    end

    return path:sub(1, #prefix) == prefix
end

--- Prefer a kernel that matches the active virtual environment.
---@param kernels pyrepl.KernelSpec[]
---@return integer
local function preferred_kernel_index(kernels)
    local venv = normalize_path(get_active_venv())
    if not venv then
        return 1
    end

    for idx, kernel in ipairs(kernels) do
        local kernel_venv_path = normalize_path(kernel.path)
        if has_path_prefix(kernel_venv_path, venv) then
            return idx
        end
    end

    return 1
end


---@param kernel_name? string
---@return string?
function M.init_kernel(kernel_name)
    if not kernel_name or kernel_name == "" then
        vim.notify("Pyrepl: Kernel name is missing.", vim.log.levels.ERROR)
        return
    end

    local result = vim.fn.InitKernel(kernel_name)
    if not result.ok then
        vim.notify("Pyrepl: " .. result.message, vim.log.levels.ERROR)
        return
    end

    return result.connection_file
end

---@param connection_file? string
function M.shutdown_kernel(connection_file)
    if not connection_file then return end

    local result = vim.fn.ShutdownKernel(connection_file)
    if not result.ok then
        local message = result.message or "Kernel shutdown failed."
        vim.notify("Pyrepl: " .. message, vim.log.levels.ERROR)
    end

    pcall(os.remove, connection_file)
end

---@param on_choice fun(name: string)
function M.prompt_kernel(on_choice)
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
            prompt = "Pyrepl: Select Jupyter kernel",
            format_item = function(item)
                local path = item.path
                if type(path) ~= "string" or path == "" then
                    return item.name
                end
                return string.format("%s  (%s)", item.name, path)
            end,
        },
        function(choice)
            if not choice then return end
            on_choice(choice.name)
        end
    )
end

return M
