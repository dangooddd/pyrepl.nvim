local api, fn, ts = vim.api, vim.fn, vim.treesitter

local M = {
    config = {
        split_horizontal = false,
        split_ratio = 0.65,
        image = {
            cell_width = 10,
            cell_height = 20,
            max_width_ratio = 0.5,
            max_height_ratio = 0.5
        }
    },
    term = {
        opened = 0,
        winid = 0,
        bufid = 0,
        chanid = 0
    },
    kernelname = nil,
    send_queue = {},
    send_flushing = false,
    repl_ready = false
}

local function is_vim_nil(value)
    return vim.NIL ~= nil and value == vim.NIL
end

local function normalize_vim_value(value)
    if is_vim_nil(value) then
        return nil
    end
    return value
end

local function resolve_python_executable()
    local host_prog = normalize_vim_value(vim.g.python3_host_prog)
    if type(host_prog) == "string" and host_prog ~= "" then
        return vim.fn.expand(host_prog)
    end
    return "python3"
end

local function validate_python_host()
    local host_prog = vim.g.python3_host_prog
    if is_vim_nil(host_prog) then
        vim.notify(
            "Pyrepl: g:python3_host_prog is v:null. Unset it or set a valid python3 path.",
            vim.log.levels.ERROR
        )
        return nil
    end
    host_prog = normalize_vim_value(host_prog)
    if host_prog ~= nil and type(host_prog) ~= "string" then
        vim.notify("Pyrepl: g:python3_host_prog must be a string path to python3.", vim.log.levels.ERROR)
        return nil
    end
    local python_executable = resolve_python_executable()
    if fn.executable(python_executable) == 0 then
        vim.notify(
            string.format(
                "Pyrepl: python3 executable not found (%s). Set g:python3_host_prog to a valid python3 path.",
                python_executable
            ),
            vim.log.levels.ERROR
        )
        return nil
    end
    return python_executable
end

local function normalize_path(path)
    if not path or path == "" then
        return nil
    end
    local normalized = path
    if vim.fs and vim.fs.normalize then
        local ok, value = pcall(vim.fs.normalize, path)
        if ok and value then
            normalized = value
        end
    else
        normalized = fn.fnamemodify(path, ":p")
    end
    normalized = normalized:gsub("/+$", "")
    return normalized
end

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

local function list_kernels()
    local ok, result = pcall(fn.ListKernels)
    if not ok then
        if string.find(result, "Unknown function") then
            vim.notify(
                "Pyrepl: Remote plugin not loaded. Run :UpdateRemotePlugins and restart Neovim.",
                vim.log.levels.ERROR
            )
        else
            vim.notify(string.format("Pyrepl: Failed to list kernels: %s", result), vim.log.levels.ERROR)
        end
        return nil
    end

    result = normalize_vim_value(result)
    if type(result) ~= "table" or #result == 0 then
        vim.notify("Pyrepl: No kernels found. Install ipykernel first.", vim.log.levels.ERROR)
        return nil
    end

    local kernels = {}
    for _, item in ipairs(result) do
        if type(item) == "table" then
            local name = item.name
            if type(name) == "string" and name ~= "" then
                table.insert(kernels, {
                    name = name,
                    path = item.path or "",
                    argv0 = item.argv0 or ""
                })
            end
        end
    end

    if #kernels == 0 then
        vim.notify("Pyrepl: No kernels found. Install ipykernel first.", vim.log.levels.ERROR)
        return nil
    end

    table.sort(kernels, function(a, b)
        return a.name < b.name
    end)

    return kernels
end

local function preferred_kernel_index(kernels)
    local venv = get_active_venv()
    if not venv then
        return 1
    end
    local venv_path = normalize_path(venv)
    if not venv_path then
        return 1
    end
    for idx, kernel in ipairs(kernels) do
        local kernel_path = normalize_path(kernel.path)
        local argv0 = normalize_path(kernel.argv0)
        if has_path_prefix(kernel_path, venv_path) or has_path_prefix(argv0, venv_path) then
            return idx
        end
    end
    return 1
end

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

    local function handle_choice(choice)
        if not choice then
            vim.notify("Pyrepl: Kernel selection cancelled.", vim.log.levels.WARN)
            return
        end
        on_choice(choice.name)
    end

    if vim.ui and vim.ui.select then
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
                end
            },
            handle_choice
        )
        return
    end

    local choices = { "Select Jupyter kernel:" }
    for _, item in ipairs(kernels) do
        local label = item.name
        if item.path and item.path ~= "" then
            label = string.format("%s (%s)", item.name, item.path)
        end
        table.insert(choices, label)
    end
    local selection = fn.inputlist(choices)
    if selection < 1 or selection > #kernels then
        vim.notify("Pyrepl: Kernel selection cancelled.", vim.log.levels.WARN)
        return
    end
    handle_choice(kernels[selection])
end

local function repl_ready()
    return M.term.opened == 1 and M.term.chanid ~= 0 and M.connection_file_path
end

local function get_console_path()
    if M.console_path then
        return M.console_path
    end
    local candidates = api.nvim_get_runtime_file("rplugin/python3/console.py", false)
    if candidates and #candidates > 0 then
        M.console_path = candidates[1]
        return M.console_path
    end
    return nil
end

local function register_kernel_cleanup()
    if M.kernel_cleanup_set then
        return
    end
    api.nvim_create_autocmd(
        "VimLeavePre",
        {
            callback = function()
                if M.connection_file_path then
                    fn.ShutdownKernel(M.connection_file_path)
                    os.remove(M.connection_file_path)
                end
            end,
            once = true
        }
    )
    M.kernel_cleanup_set = true
end

local function init_kernel(kernelname)
    local success, result = pcall(fn.InitKernel, kernelname)
    if not success then
        if string.find(result, "Unknown function") then
            vim.notify(
                "Pyrepl: Remote plugin not loaded. Run :UpdateRemotePlugins and restart Neovim.",
                vim.log.levels.ERROR
            )
        else
            vim.notify(string.format("Pyrepl: Kernel initialization failed: %s", result), vim.log.levels.ERROR)
        end
        return nil
    end
    result = normalize_vim_value(result)
    if type(result) == "table" then
        if result.ok == true then
            local connection_file = normalize_vim_value(result.connection_file)
            if type(connection_file) ~= "string" or connection_file == "" then
                vim.notify("Pyrepl: Kernel initialization failed with empty connection file.", vim.log.levels.ERROR)
                return nil
            end
            return connection_file
        end

        local error_type = normalize_vim_value(result.error_type)
        local error_message = normalize_vim_value(result.error)
        local requested_kernel_name = normalize_vim_value(result.requested_kernel_name)
        local effective_kernel_name = normalize_vim_value(result.effective_kernel_name)
        local spec_argv0 = normalize_vim_value(result.spec_argv0)

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
                    "Pyrepl: Kernel '%s' not found. Please install it manually (see README) and try again.",
                    kernelname
                ),
                vim.log.levels.ERROR
            )
        elseif error_type == "missing_kernel_name" then
            vim.notify("Pyrepl: Kernel name is missing.", vim.log.levels.ERROR)
        else
            local message = error_message or "Unknown error"
            vim.notify(string.format("Pyrepl: Kernel initialization failed: %s%s", message, debug_suffix), vim.log.levels.ERROR)
        end
        return nil
    end
    if not result or result == "" then
        vim.notify("Pyrepl: Kernel initialization failed with empty connection file.", vim.log.levels.ERROR)
        return nil
    end
    return result
end

local function build_repl_env()
    local image = M.config.image or {}
    local cell_width = tonumber(image.cell_width) or 10
    local cell_height = tonumber(image.cell_height) or 20
    local max_width_ratio = tonumber(image.max_width_ratio) or 0.5
    local max_height_ratio = tonumber(image.max_height_ratio) or 0.5

    return {
        PYREPL_IMAGE_CELL_WIDTH = tostring(cell_width),
        PYREPL_IMAGE_CELL_HEIGHT = tostring(cell_height),
        PYREPL_IMAGE_MAX_WIDTH_RATIO = tostring(max_width_ratio),
        PYREPL_IMAGE_MAX_HEIGHT_RATIO = tostring(max_height_ratio)
    }
end

local function open_terminal(python_executable, kernelname)
    local origin_win = api.nvim_get_current_win()
    local filetype = vim.bo.filetype
    if filetype ~= "python" then
        vim.notify("Pyrepl: Only Python filetype is supported.", vim.log.levels.WARN)
        return
    end
    kernelname = kernelname or M.kernelname
    if not kernelname or kernelname == "" then
        vim.notify("Pyrepl: Kernel name is missing.", vim.log.levels.ERROR)
        return
    end

    if not M.connection_file_path then
        local connection_file = init_kernel(kernelname)
        if not connection_file then
            return
        end
        M.connection_file_path = connection_file
        M.kernelname = kernelname
        register_kernel_cleanup()
    end

    local bufid = api.nvim_create_buf(false, true)

    if M.config.split_horizontal then
        local height = math.floor(vim.o.lines * M.config.split_ratio)
        local split_cmd = "botright " .. height .. "split"
        vim.cmd(split_cmd)
    else
        local width = math.floor(vim.o.columns * M.config.split_ratio)
        local split_cmd = "botright " .. width .. "vsplit"
        vim.cmd(split_cmd)
    end

    vim.opt.termguicolors = true

    api.nvim_win_set_buf(0, bufid)
    local winid = api.nvim_get_current_win()

    if M.config.split_horizontal then
        vim.wo.winfixheight = true
        vim.wo.winfixwidth = false
    else
        vim.wo.winfixwidth = true
        vim.wo.winfixheight = false
    end

    local statusline_format = string.format("Kernel: %s  |  Line : %%l ", kernelname)
    vim.wo[winid].statusline = statusline_format

    local console_path = get_console_path()
    if not console_path then
        vim.notify(
            "Pyrepl: Console script not found. Run :UpdateRemotePlugins and restart Neovim.",
            vim.log.levels.ERROR
        )
        return
    end

    if M.connection_file_path then
        local nvim_socket = vim.v.servername
        local term_cmd = {
            python_executable,
            console_path,
            "--existing",
            M.connection_file_path,
            "--nvim-socket",
            nvim_socket
        }

        -- Open terminal with environment and options
        local chanid =
            fn.termopen(
                term_cmd,
                {
                    env = build_repl_env(),
                    on_exit = function()
                    end
                }
            )

        M.term = {
            opened = 1,
            winid = winid,
            bufid = bufid,
            chanid = chanid
        }
        M.repl_ready = false
        if api.nvim_win_is_valid(origin_win) then
            api.nvim_set_current_win(origin_win)
        end
    else
        api.nvim_err_writeln("Failed to initialize kernel")
    end
end

local function raw_send_message(message)
    local function normalize_python_message(msg)
        local lines = vim.split(msg, "\n", { plain = true })
        if #lines <= 1 then
            return msg
        end

        local function ends_with_colon(line)
            local trimmed = line:gsub("%s+$", "")
            if trimmed == "" then
                return false
            end
            local comment_pos = trimmed:find("#")
            if comment_pos then
                trimmed = trimmed:sub(1, comment_pos - 1):gsub("%s+$", "")
            end
            return trimmed:sub(-1) == ":"
        end

        local function is_continuation(line)
            local trimmed = line:gsub("^%s+", "")
            return trimmed:match("^(else|elif|except|finally)%f[%w]")
        end

        local out = {}
        local in_top_block = false

        for _, line in ipairs(lines) do
            local indent = line:match("^(%s*)") or ""
            local trimmed = line:gsub("%s+$", "")
            local is_blank = trimmed == ""
            local is_top = #indent == 0
            local continuation = is_top and is_continuation(line)

            if is_top and not is_blank and in_top_block and not continuation then
                table.insert(out, "")
                in_top_block = false
            end

            table.insert(out, line)

            if is_top and ends_with_colon(line) then
                in_top_block = true
            end
        end

        if in_top_block then
            local last = out[#out] or ""
            if not last:match("^%s*$") then
                table.insert(out, "")
            end
        end

        local normalized = table.concat(out, "\n")
        return normalized
    end

    if not repl_ready() then
        return
    end
    if not message or message == "" then
        return
    end

    local prefix = api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    local normalized = normalize_python_message(message)
    api.nvim_chan_send(M.term.chanid, prefix .. normalized .. suffix .. "\n")

    if api.nvim_win_is_valid(M.term.winid) then
        api.nvim_win_set_cursor(
            M.term.winid,
            { api.nvim_buf_line_count(api.nvim_win_get_buf(M.term.winid)), 0 }
        )
    end
end

local function flush_send_queue()
    if M.send_flushing then
        return
    end
    if not M.repl_ready then
        return
    end
    if #M.send_queue == 0 then
        return
    end
    M.send_flushing = true
    local next_message = table.remove(M.send_queue, 1)
    M.repl_ready = false
    raw_send_message(next_message)
    M.send_flushing = false
end

local function send_message(message)
    if not message or message == "" then
        return
    end
    table.insert(M.send_queue, message)
    flush_send_queue()
end

function M._on_repl_ready()
    M.repl_ready = true
    flush_send_queue()
end

local function move_cursor_to_next_line(end_row)
    local comment_char = "#"
    local line_count = api.nvim_buf_line_count(0)
    local row = end_row + 2

    while row <= line_count do
        local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
        local col = line:find("%S")
        if col and line:sub(col, col + (#comment_char - 1)) ~= comment_char then
            api.nvim_win_set_cursor(0, { row, 0 })
            return
        end
        row = row + 1
    end
end

local function get_visual_selection()
    local start_pos, end_pos = fn.getpos("v"), fn.getcurpos()
    local start_line, end_line = start_pos[2], end_pos[2]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end
    local lines = api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n"), end_line
end

local function check_and_install_dependencies(python_executable)
    python_executable = python_executable or resolve_python_executable()

    if fn.executable(python_executable) == 0 then
        return false
    end

    local check_cmd = {
        python_executable,
        "-c",
        "import pynvim, jupyter_client, prompt_toolkit, PIL, pygments"
    }

    fn.system(check_cmd)

    if vim.v.shell_error ~= 0 then
        local pip_path = fn.system({ python_executable, "-m", "pip", "--version" }):gsub("\n", "")
        local install_path = fn.system({
            python_executable,
            "-c",
            "import site, sys; "
            .. "print(site.getsitepackages()[0] if hasattr(site, 'getsitepackages') and site.getsitepackages() else sys.prefix)"
        }):gsub("\n", "")

        local choice = fn.confirm(
            string.format(
                "Pyrepl: Missing packages. Install?\n\nPython: %s\nPip: %s\nInstall path: %s",
                python_executable,
                pip_path,
                install_path
            ),
            "&Yes\n&No",
            1
        )
        if choice == 1 then
            local bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Installing dependencies..." })

            local width = math.floor(vim.o.columns * 0.6)
            local height = math.floor(vim.o.lines * 0.4)
            local winid = api.nvim_open_win(bufnr, false, {
                relative = "editor",
                width = width,
                height = height,
                row = math.floor((vim.o.lines - height) / 2),
                col = math.floor((vim.o.columns - width) / 2),
                style = "minimal",
                border = "rounded",
                title = " Installing Dependencies ",
                title_pos = "center"
            })

            local error_lines = {}

            local pip_args = { python_executable, "-m", "pip", "install" }
            table.insert(pip_args, "pynvim")
            table.insert(pip_args, "jupyter-client")
            table.insert(pip_args, "prompt-toolkit")
            table.insert(pip_args, "pillow")
            table.insert(pip_args, "pygments")

            fn.jobstart(pip_args, {
                stdout_buffered = false,
                stderr_buffered = false,
                on_stdout = function(_, data)
                    if data then
                        vim.schedule(function()
                            for _, line in ipairs(data) do
                                if line ~= "" then
                                    api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
                                end
                            end
                        end)
                    end
                end,
                on_stderr = function(_, data)
                    if data then
                        vim.schedule(function()
                            for _, line in ipairs(data) do
                                if line ~= "" then
                                    table.insert(error_lines, line)
                                    api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
                                end
                            end
                        end)
                    end
                end,
                on_exit = function(_, return_val)
                    vim.schedule(function()
                        if api.nvim_win_is_valid(winid) then
                            api.nvim_win_close(winid, true)
                        end
                        if return_val == 0 then
                            vim.cmd("UpdateRemotePlugins")
                            vim.notify(
                                "Pyrepl: Dependencies installed and remote plugins updated. Please restart Neovim.",
                                vim.log.levels.INFO)
                        else
                            vim.notify(string.format(
                                "Pyrepl: Failed to install dependencies (exit code: %d)\nPython: %s\nCheck output above for details.",
                                return_val, python_executable), vim.log.levels.ERROR)
                        end
                    end)
                end
            })
        end
        return false
    end
    return true
end

function M.setup(opts)
    vim.env.PYTHONDONTWRITEBYTECODE = "1"
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    if not M.commands_set then
        api.nvim_create_user_command("Pyrepl", function()
            M.init()
        end, { nargs = 0 })
        M.commands_set = true
    end
    return M
end

function M.init()
    local python_executable = validate_python_host()
    if not python_executable then
        return
    end
    if not check_and_install_dependencies(python_executable) then
        return
    end
    local filetype = vim.bo.filetype
    if filetype ~= "python" then
        vim.notify("Pyrepl: Only Python filetype is supported.", vim.log.levels.WARN)
        return
    end
    if M.connection_file_path then
        open_terminal(python_executable, M.kernelname)
        return
    end

    prompt_kernel_choice(function(kernelname)
        if not kernelname or kernelname == "" then
            vim.notify("Pyrepl: Kernel name is missing.", vim.log.levels.ERROR)
            return
        end
        local connection_file = init_kernel(kernelname)
        if not connection_file then
            return
        end
        M.connection_file_path = connection_file
        M.kernelname = kernelname
        register_kernel_cleanup()
        open_terminal(python_executable, kernelname)
    end)
end

function M.send_visual_to_repl()
    if not repl_ready() then
        return
    end
    local current_winid = api.nvim_get_current_win()
    local msg, end_row = get_visual_selection()
    send_message(msg)
    api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

function M.send_buffer_to_repl()
    if not repl_ready() then
        return
    end
    local current_winid = api.nvim_get_current_win()
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    if not lines or #lines == 0 then
        return
    end
    local msg = table.concat(lines, "\n")
    if msg == "" then
        return
    end
    send_message(msg)
    if api.nvim_win_is_valid(current_winid) then
        api.nvim_set_current_win(current_winid)
    end
end

local function handle_cursor_move()
    local row = api.nvim_win_get_cursor(0)[1]
    local comment_char = "#"
    while row <= api.nvim_buf_line_count(0) do
        local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local col = line:find("%S")

        -- Skip empty lines or comment lines
        if not col or line:sub(col, col + (#comment_char - 1)) == comment_char then
            row = row + 1
            pcall(function()
                api.nvim_win_set_cursor(0, { row, 0 })
            end)
        else
            local cursor_pos = api.nvim_win_get_cursor(0)
            local current_col = cursor_pos[2] + 1

            -- If cursor is already on a non-whitespace character, do nothing
            local char_under_cursor = line:sub(current_col, current_col)
            if not char_under_cursor:match("%s") then
                break
            end

            -- Find nearest non-whitespace characters backward and forward
            local backward_pos, forward_pos
            for i = current_col - 1, 1, -1 do
                if not line:sub(i, i):match("%s") then
                    backward_pos = i
                    break
                end
            end

            for i = current_col + 1, #line do
                if not line:sub(i, i):match("%s") then
                    forward_pos = i
                    break
                end
            end

            -- Calculate distances and move cursor
            local backward_dist = backward_pos and (current_col - backward_pos) or math.huge
            local forward_dist = forward_pos and (forward_pos - current_col) or math.huge

            if backward_dist < forward_dist then
                api.nvim_win_set_cursor(0, { row, backward_pos - 1 })
            elseif forward_dist <= backward_dist then
                api.nvim_win_set_cursor(0, { row, forward_pos - 1 })
            end

            break
        end
    end
end

function M.send_statement_definition()
    if not repl_ready() then
        api.nvim_feedkeys(
            api.nvim_replace_termcodes("<CR>", true, false, true),
            "n",
            false
        )
        return
    end
    handle_cursor_move()
    local ok_parser, parser = pcall(ts.get_parser, 0)
    if not ok_parser or not parser then
        vim.notify("Pyrepl: Tree-sitter parser not available for this buffer.", vim.log.levels.WARN)
        return
    end
    local tree = parser:parse()[1]
    if not tree then
        print("No valid node found!")
        return
    end
    local root = tree:root()
    local function node_at_cursor()
        local row, col = unpack(api.nvim_win_get_cursor(0))
        row = row - 1
        local line = api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ""
        local max_col = math.max(#line - 1, 0)
        if col > max_col then
            col = max_col
        end
        local node = root:named_descendant_for_range(row, col, row, col)
        if node == root then
            node = nil
        end
        if not node and #line > 0 then
            node = root:named_descendant_for_range(row, 0, row, max_col)
            if node == root then
                node = nil
            end
        end
        return node
    end
    local node = node_at_cursor()

    local current_winid = api.nvim_get_current_win()

    local function find_and_return_node()
        local function immediate_child(node)
            for child in root:iter_children() do
                if child:id() == node:id() then
                    return true
                end
            end
            return false
        end

        while node and not immediate_child(node) do
            node = node:parent()
        end

        return node, current_winid
    end

    local node, winid = find_and_return_node()
    if not node then
        print("No valid node found!")
        return
    end

    local ok, msg = pcall(ts.get_node_text, node, 0)

    if not ok then
        print("Error getting node text!")
        return
    end

    local end_row = select(3, node:range())
    if msg then
        send_message(msg)
    end
    api.nvim_set_current_win(winid)
    move_cursor_to_next_line(end_row)
end

-- Image history functions
function M.open_history_manager()
    require("pyrepl.image").open_history_manager()
end

function M.show_last_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrepl.image").show_last_image()
end

function M.show_previous_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrepl.image").show_previous_image()
end

function M.show_next_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrepl.image").show_next_image()
end

return M
