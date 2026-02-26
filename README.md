# pyrepl.nvim

pyrepl.nvim is a Python REPL inside Neovim powered by Jupyter kernels. It opens `jupyter-console` in a terminal split and provides commands to send code from your buffer to the selected kernel.

<img width="1624" height="971" alt="preview" src="https://github.com/user-attachments/assets/f126b07a-20ac-4fa4-9b58-815ac8fb6230" />

## Quickstart

Minimal lazy.nvim setup with the default config and example keymaps:

```lua
{
  "dangooddd/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    local pyrepl = require("pyrepl")

    -- default config
    -- :h pyrepl-config
    pyrepl.setup({
      split_horizontal = false,
      split_ratio = 0.5,
      image_max_history = 10,
      image_width_ratio = 0.5,
      image_height_ratio = 0.5,
      -- built-in provider, works best for ghostty and kitty
      -- for other terminals use "image" instead of "placeholders"
      image_provider = "placeholders",
      cell_pattern = "^# %%%%.*$",
      python_path = "python",
      preferred_kernel = "python3",
      jupytext_hook = true,
      style = "default",
      style_treesitter = true,
      -- pass nil to use jupyter-console built-in banner
      banner = [[
┏━┓╻ ╻┏━┓┏━╸┏━┓╻
┣━┛┗┳┛┣┳┛┣╸ ┣━┛┃
╹   ╹ ╹┗╸┗━╸╹  ┗━╸
jupyter-console {version}
      ]],
    })

    -- main commands
    vim.keymap.set("n", "<leader>jo", pyrepl.open_repl)
    vim.keymap.set("n", "<leader>jh", pyrepl.hide_repl)
    vim.keymap.set("n", "<leader>jc", pyrepl.close_repl)
    vim.keymap.set("n", "<leader>ji", pyrepl.open_image_history)
    vim.keymap.set({ "n", "t" }, "<C-j>", pyrepl.toggle_repl_focus)

    -- send commands
    vim.keymap.set("n", "<leader>jb", pyrepl.send_buffer)
    vim.keymap.set("n", "<leader>jl", pyrepl.send_cell)
    vim.keymap.set("v", "<leader>jv", pyrepl.send_visual)

    -- utility commands
    vim.keymap.set("n", "<leader>jp", pyrepl.step_cell_backward)
    vim.keymap.set("n", "<leader>jn", pyrepl.step_cell_forward)
    vim.keymap.set("n", "<leader>je", pyrepl.export_to_notebook)
    vim.keymap.set("n", "<leader>js", ":PyreplInstall")
  end,
}
```

Then install pyrepl runtime packages with `uv` or `pip` directly from Neovim:

```vim
:PyreplInstall pip
:PyreplInstall uv
```

To use jupytext integration, make sure jupytext is available in neovim:

```bash
# pipx install jupytext
uv tool install jupytext
```

For mason users:

```vim
:MasonInstall jupytext
```

## Demo

https://github.com/user-attachments/assets/19822d92-5173-4441-8cec-6a59f9eb41b9

## Preface

This plugin aims to provide a sensible workflow to work with Python REPL.

Features `pyrepl.nvim` currently provides:

- Convert notebook files from and to python with `jupytext`;
- Install all runtime deps required with a command (no need to install kernel globally with default settings);
- Start `jupyter-console` in neovim terminal;
- Prompt the user to choose jupyter kernel on REPL start;
- Send code to the REPL from current buffer;
- Automatically display output images;
- Neovim theme integration for `jupyter-console`;
- Jupytext cell navigation;
- Toggle focus to REPL in active terminal mode.

## Tips & Tricks

### Image display

Use `placeholders` provider for [ghostty](https://github.com/ghostty-org/ghostty) and [kitty](https://github.com/kovidgoyal/kitty) terminal.
This allows image display in hard cases (for example, when nvim started in nested `ssh`, `tmux` and `docker`).

For other terminals change provider to `image` - [image.nvim](https://github.com/3rd/image.nvim) will be used to display images.
For example, to display images in terminal with `sixel` protocol support:

```lua
{
  "3rd/image.nvim",
  config = function()
    require("image").setup({ backend = "sixel" })
  end,
},

{
  "dangooddd/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "3rd/image.nvim" },
  config = function()
    require("pyrepl").setup({ image_provider = "image" })
  end,
}
```

### Use a dedicated Python environment for runtime packages

By default pyrepl.nvim uses `python_path = "python"`.
If Neovim is started inside a venv, that venv should be used.

But you can install all required packages once in a dedicated python interpreter and set correct `python_path`
(or set `python_path = nil` and `vim.g.python3_host_prog` will be used as fallback).

Example:

```bash
uv venv ~/.venv_nvim
source ~/.venv_nvim/bin/activate
uv pip install pynvim jupyter-console ipykernel
uv pip install pillow cairosvg # optional, for jpg and svg support
```

Then, in `init.lua`:

```lua
require("pyrepl").setup({ python_path = "~/.venv_nvim/bin/python" })
```

To use arbitrary kernel in that case, you need to install it globally:

```bash
# from kernel virtual environment
python -m ipykernel install --user --name {kernel_name}
```

### Use a built-in Pygments style

If you do not like the treesitter-based REPL colors, pick a built-in Pygments theme:

```lua
require("pyrepl").setup({
  style_treesitter = false,
  style = "default", -- or another Pygments style, e.g. "gruvbox-dark"
})
```

### Send cell and move to the next one

Combine `send` and `step` commands:

```lua
vim.keymap.set("n", "<leader>jl", function()
  vim.cmd("PyreplSendCell")
  vim.cmd("PyreplStepCellForward")
end)
```

## Known Limitations

- Only Python is officially supported and will be prioritized. For R, see https://github.com/R-nvim/R.nvim;
- Persistence in kernel outputs is not possible right now. Implementing cell logic like `molten.nvim` will complicate current approach.

## Commands and API

Commands:

- `:PyreplOpen` - select a kernel and open the REPL;
- `:PyreplHide` - hide the REPL window (kernel stays alive);
- `:PyreplClose` - close the REPL and shut down the kernel;
- `:PyreplToggleFocus` - focus REPL in terminal mode or switch back to previous window;
- `:PyreplSendVisual` - send the last visual selection;
- `:PyreplSendBuffer` - send the entire buffer;
- `:PyreplSendCell` - send cell around the cursor (cells are separated by `cell_pattern`);
- `:PyreplStepCellForward` - move cursor to the start of the next cell separated by `cell_pattern`;
- `:PyreplStepCellBackward` - move cursor to the start of the previous cell separated by `cell_pattern`;
- `:PyreplOpenImageHistory` - open the image manager; use `j`/`h` for previous, `k`/`l` for next, `dd` to delete, `q` or `<Esc>` to close;
- `:PyreplExport` - export current buffer to notebook (`jupytext` should be installed);
- `:PyreplConvert` - prompt to convert current notebook buffer to python (`jupytext` should be installed);
- `:PyreplInstall {tool}` - install required packages into `python_path` (with `pip` or `uv` tool).

Highlight groups:

- `PyreplImageBorder` (link to `FloatBorder` by default);
- `PyreplImageTitle` (link to `FloatTitle` by default);
- `PyreplImageNormal` (link to `NormalFloat` by default).

Lua API:

```lua
require("pyrepl").setup(opts)
require("pyrepl").open_repl()
require("pyrepl").hide_repl()
require("pyrepl").close_repl()
require("pyrepl").toggle_repl_focus()
require("pyrepl").send_visual()
require("pyrepl").send_buffer()
require("pyrepl").send_cell()
require("pyrepl").step_cell_forward()
require("pyrepl").step_cell_backward()
require("pyrepl").open_image_history()
require("pyrepl").export_to_notebook()
require("pyrepl").convert_to_python()
require("pyrepl").install_packages(tool)
```

## Thanks

- [molten.nvim](https://github.com/benlubas/molten-nvim)
- [pyrola.nvim](https://github.com/robitx/pyrola.nvim)
- [iron.nvim](https://github.com/Vigemus/iron.nvim)
