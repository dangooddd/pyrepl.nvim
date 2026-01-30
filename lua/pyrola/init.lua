local api, fn, ts = vim.api, vim.fn, vim.treesitter

local M = {
    config = {
        kernel_map = {
            python = "python3",
            r = "ir",
            cpp = "xcpp17"
        },
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
    send_queue = {},
    send_flushing = false,
    repl_ready = false
}

local function is_vim_nil(value)
    return vim.NIL ~= nil and value == vim.NIL
end

local function resolve_python_executable()
    local host_prog = vim.g.python3_host_prog
    if is_vim_nil(host_prog) then
        host_prog = nil
    end
    if type(host_prog) == "string" and host_prog ~= "" then
        return vim.fn.expand(host_prog)
    end
    return "python3"
end

local function validate_python_host()
    local host_prog = vim.g.python3_host_prog
    if is_vim_nil(host_prog) then
        vim.notify(
            "Pyrola: g:python3_host_prog is v:null. Unset it or set a valid python3 path.",
            vim.log.levels.ERROR
        )
        return nil
    end
    if host_prog ~= nil and type(host_prog) ~= "string" then
        vim.notify("Pyrola: g:python3_host_prog must be a string path to python3.", vim.log.levels.ERROR)
        return nil
    end
    local python_executable = resolve_python_executable()
    if fn.executable(python_executable) == 0 then
        vim.notify(
            string.format(
                "Pyrola: python3 executable not found (%s). Set g:python3_host_prog to a valid python3 path.",
                python_executable
            ),
            vim.log.levels.ERROR
        )
        return nil
    end
    return python_executable
end

local function repl_ready()
    return M.term.opened == 1 and M.term.chanid ~= 0 and M.connection_file_path
end

local function get_plugin_path()
    if M.plugin_path then
        return M.plugin_path
    end
    local runtime_paths = api.nvim_list_runtime_paths()
    for _, path in ipairs(runtime_paths) do
        if path:match("pyrola.nvim$") then
            M.plugin_path = path
            return path
        end
    end
end

local function register_kernel_cleanup()
    if M.kernel_cleanup_set then
        return
    end
    api.nvim_create_autocmd(
        "VimLeavePre",
        {
            callback = function()
                if M.filetype and M.connection_file_path then
                    fn.ShutdownKernel(M.filetype, M.connection_file_path)
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
                "Pyrola: Remote plugin not loaded. Run :UpdateRemotePlugins and restart Neovim.",
                vim.log.levels.ERROR
            )
        elseif string.find(result, "No such kernel") then
            vim.notify(
                string.format(
                    "Pyrola: Kernel '%s' not found. Please install it manually (see README) and update setup config.",
                    kernelname
                ),
                vim.log.levels.ERROR
            )
        else
            vim.notify(string.format("Pyrola: Kernel initialization failed: %s", result), vim.log.levels.ERROR)
        end
        return nil
    end
    if not result or result == "" then
        vim.notify("Pyrola: Kernel initialization failed with empty connection file.", vim.log.levels.ERROR)
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
        PYROLA_IMAGE_CELL_WIDTH = tostring(cell_width),
        PYROLA_IMAGE_CELL_HEIGHT = tostring(cell_height),
        PYROLA_IMAGE_MAX_WIDTH_RATIO = tostring(max_width_ratio),
        PYROLA_IMAGE_MAX_HEIGHT_RATIO = tostring(max_height_ratio)
    }
end

local function open_terminal(python_executable)
    M.filetype = vim.bo.filetype
    local origin_win = api.nvim_get_current_win()
    local kernelname = M.config.kernel_map[M.filetype]
    if not kernelname then
        vim.notify(
            string.format("Pyrola: No kernel mapped for filetype '%s'.", M.filetype),
            vim.log.levels.ERROR
        )
        return
    end

    if not M.connection_file_path then
        local connection_file = init_kernel(kernelname)
        if not connection_file then
            return
        end
        M.connection_file_path = connection_file
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

    local console_path = get_plugin_path()

    if M.connection_file_path then
        local nvim_socket = vim.v.servername
        local term_cmd = {
            python_executable,
            string.format("%s/rplugin/python3/console.py", console_path),
            "--existing",
            M.connection_file_path,
            "--filetype",
            M.filetype,
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

    if M.filetype == "python" then
        local normalized = normalize_python_message(message)
        api.nvim_chan_send(M.term.chanid, prefix .. normalized .. suffix .. "\n")
    else
        api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
    end

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
    if not repl_ready() then
        return
    end
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
    local comment_char = vim.bo.filetype == "cpp" and "//" or "#"
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

local function create_pretty_float(content)
    local content_lines = vim.split(content, "\n", { plain = true })
    local win_width = vim.o.columns
    local win_height = vim.o.lines

    local max_content_width = 0
    for _, line in ipairs(content_lines) do
        max_content_width = math.max(max_content_width, fn.strdisplaywidth(line))
    end

    local max_width = math.max(10, math.floor(win_width * 0.9))
    local max_height = math.max(6, math.floor(win_height * 0.9))
    local min_width = math.min(20, max_width)
    local min_height = math.min(4, max_height)

    local width = math.min(max_content_width + 4, max_width)
    local height = math.min(#content_lines + 2, max_height)
    width = math.max(width, min_width)
    height = math.max(height, min_height)

    local row = math.max(0, math.floor((win_height - height) / 2))
    local col = math.max(0, math.floor((win_width - width) / 2))

    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Inspector ",
        title_pos = "center"
    }

    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, content_lines)

    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].buftype = "nofile"

    local winid = api.nvim_open_win(bufnr, true, opts)

    local border_hl = "PyrolaInspectorBorder"
    local title_hl = "PyrolaInspectorTitle"
    local normal_hl = "PyrolaInspectorNormal"

    if not M._inspector_highlights_set then
        local border_target = fn.hlexists("FloatBorder") == 1 and "FloatBorder" or "WinSeparator"
        local title_target = fn.hlexists("FloatTitle") == 1 and "FloatTitle" or "Title"
        local normal_target = fn.hlexists("NormalFloat") == 1 and "NormalFloat" or "Normal"

        if fn.hlexists(border_hl) == 0 then
            api.nvim_set_hl(0, border_hl, { link = border_target })
        end
        if fn.hlexists(title_hl) == 0 then
            api.nvim_set_hl(0, title_hl, { link = title_target })
        end
        if fn.hlexists(normal_hl) == 0 then
            api.nvim_set_hl(0, normal_hl, { link = normal_target })
        end
        M._inspector_highlights_set = true
    end

    vim.wo[winid].winhl = string.format(
        "Normal:%s,FloatBorder:%s,FloatTitle:%s",
        normal_hl,
        border_hl,
        title_hl
    )

    local keymap_opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set(
        "n",
        "q",
        function()
            api.nvim_win_close(winid, true)
        end,
        keymap_opts
    )
    vim.keymap.set(
        "n",
        "<Esc>",
        function()
            api.nvim_win_close(winid, true)
        end,
        keymap_opts
    )

    vim.keymap.set("n", "j", "gj", keymap_opts)
    vim.keymap.set("n", "k", "gk", keymap_opts)
    vim.keymap.set("n", "<C-d>", "<C-d>zz", keymap_opts)
    vim.keymap.set("n", "<C-u>", "<C-u>zz", keymap_opts)
    vim.keymap.set("n", "<C-f>", "<C-f>zz", keymap_opts)
    vim.keymap.set("n", "<C-b>", "<C-b>zz", keymap_opts)

    api.nvim_set_current_win(winid)

    return winid, bufnr
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
                "Pyrola: Missing packages. Install?\n\nPython: %s\nPip: %s\nInstall path: %s",
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
                                "Pyrola: Dependencies installed and remote plugins updated. Please restart Neovim.",
                                vim.log.levels.INFO)
                        else
                            vim.notify(string.format(
                                "Pyrola: Failed to install dependencies (exit code: %d)\nPython: %s\nCheck output above for details.",
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

local function check_timg_available()
    if M.timg_checked then
        return
    end
    M.timg_checked = true
    if fn.executable("timg") == 0 then
        vim.notify(
            "Pyrola: 'timg' not found. Image previews are disabled. Install 'timg' to enable image rendering.",
            vim.log.levels.INFO
        )
    end
end

function M.setup(opts)
    vim.env.PYTHONDONTWRITEBYTECODE = "1"
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    if not M.commands_set then
        api.nvim_create_user_command("Pyrola", function(cmd)
            if cmd.args == "init" then
                M.init()
                return
            end
            vim.notify("Pyrola: Unknown command. Try :Pyrola init", vim.log.levels.WARN)
        end, { nargs = 1 })
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
    check_timg_available()
    local filetype = vim.bo.filetype
    local kernelname = M.config.kernel_map[filetype]
    if not kernelname then
        vim.notify(
            string.format("Pyrola: No kernel mapped for filetype '%s'. Update setup.kernel_map.", filetype),
            vim.log.levels.WARN
        )
        return
    end
    if not M.connection_file_path then
        local connection_file = init_kernel(kernelname)
        if not connection_file then
            return
        end
        M.connection_file_path = connection_file
        register_kernel_cleanup()
    end
    open_terminal(python_executable)
end

function M.inspect()
    if not repl_ready() then
        return
    end

    M.filetype = vim.bo.filetype
    local obj
    if ts.get_node then
        local ok_node, node = pcall(ts.get_node)
        if ok_node and node then
            local ok_text, text = pcall(ts.get_node_text, node, 0)
            if ok_text and text and text ~= "" then
                obj = text
            end
        end
    end
    if not obj then
        local ok_parser, parser = pcall(ts.get_parser, 0)
        if ok_parser and parser then
            local tree = parser:parse()[1]
            if tree then
                local root = tree:root()
                local row, col = unpack(api.nvim_win_get_cursor(0))
                row = row - 1
                local node = root:named_descendant_for_range(row, col, row, col)
                if node and node ~= root then
                    local ok_text, text = pcall(ts.get_node_text, node, 0)
                    if ok_text and text and text ~= "" then
                        obj = text
                    end
                end
            end
        end
    end
    if not obj or obj == "" then
        obj = fn.expand("<cword>")
    end
    if not obj or obj == "" then
        vim.notify("Pyrola: No symbol found under cursor to inspect.", vim.log.levels.WARN)
        return
    end

    local ok, result = pcall(fn.ExecuteKernelCode, M.filetype, M.connection_file_path, obj)
    if not ok then
        vim.notify(string.format("Pyrola: Inspect failed: %s", result), vim.log.levels.ERROR)
        return
    end
    result = tostring(result or ""):gsub("\\n", "\n")
    create_pretty_float(result)
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
    M.filetype = vim.bo.filetype
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
    local comment_char = vim.bo.filetype == "cpp" and "//" or "#"
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
        vim.notify("Pyrola: Tree-sitter parser not available for this buffer.", vim.log.levels.WARN)
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
    require("pyrola.image").open_history_manager()
end

function M.show_last_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrola.image").show_last_image()
end

function M.show_previous_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrola.image").show_previous_image()
end

function M.show_next_image()
    if M.term.opened == 0 or M.term.chanid == 0 then
        return
    end
    require("pyrola.image").show_next_image()
end

return M
