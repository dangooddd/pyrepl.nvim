# pyrepl.nvim

pyrepl.nvim is a Python REPL inside Neovim powered by Jupyter kernels. It opens a real `jupyter-console` UI in a terminal split and provides commands to send code from your buffer to the selected kernel.

<img width="1429" height="909" alt="SCR-20260210-objh" src="https://github.com/user-attachments/assets/c042f069-59aa-4e33-8468-b5d0c0f53412" />

## Quickstart

Minimal lazy.nvim setup with the default config and example keymaps:

```lua
{
  "dangooddd/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("pyrepl").setup({
      -- defaults (you can omit these):
      split_horizontal = false,
      split_ratio = 0.5,
      style_treesitter = true,
      image_max_history = 10,
      image_width_ratio = 0.5,
      image_height_ratio = 0.5,
      block_pattern = "^# %%%%.*$",
      python_path = "python",
      preferred_kernel = "python3",
      jupytext_integration = true,
    })

    -- main commands
    vim.keymap.set("n", "<leader>jo", ":PyreplOpen<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jh", ":PyreplHide<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jc", ":PyreplClose<CR>", { silent = true })
    vim.keymap.set("n", "<leader>ji", ":PyreplOpenImages<CR>", { silent = true })

    -- send commands
    vim.keymap.set("n", "<leader>jb", ":PyreplSendBlock<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jf", ":PyreplSendBuffer<CR>", { silent = true })
    vim.keymap.set("v", "<leader>jv", ":<C-u>PyreplSendVisual<CR>gv<Esc>", { silent = true })

    -- utility commands
    vim.keymap.set("n", "<leader>jp", ":PyreplBlockBackward<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jn", ":PyreplBlockForward<CR>", { silent = true })
    vim.keymap.set("n", "<leader>je", ":PyreplExport")
    vim.keymap.set("n", "<leader>js", ":PyreplInstall")
  end,
}
```

Then install pyrepl runtime packages with `uv` or `pip` directly from Neovim:

```vim
:PyreplInstall pip
:PyreplInstall uv
```

## Demo

https://github.com/user-attachments/assets/7f6796fc-ed75-4771-9f39-3245470460c1

## Preface

This plugin aims to provide sensible workflow to work with python REPL.
It was started as a fork of [pyrola.nvim](https://github.com/robitx/pyrola.nvim).

Main goals of this project:
- Ability to send code from buffer to REPL;
- Ability to display images in Neovim directly;
- Balance code complication with sinsible features for REPL workflow.

What features `pyrepl.nvim` currently provides:
- Convert notebook files from and to python with `jupytext`;
- Install all runtime deps required with command (no need to install kernel globally with default settings);
- Use `jupyter-console` TUI for REPL;
- Prompt user to choose jupyter kernel on REPL start;
- Send code to the REPL from current buffer;
- Automatically display output images and save them to image history.
  On supported terminals image display works over tmux and docker (tested in ssh + tmux + docker at one time);
- Neovim theme integration for `jupyter-console`

## Known Limitations

- Only Python is officially supported and will be prioritized. For R, see https://github.com/R-nvim/R.nvim;
- Persistance in kernel outputs is not possible right now. Implementing cell logic like `molten.nvim` will complicate current approach;
- Currently image display supported only on terminals, that support [kitty unicode placeholders protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders).
  That allows correct image display in docker - other protocols are limited in this case, see [this image.nvim issue](https://github.com/3rd/image.nvim/issues/331).

## How It Works

This plugin opens `jupyter-console` in a terminal buffer. Then you can send commands in this console using provided commands.

Images handled from `jupyter-console`: pyrepl defines custom `image_handler` function in python, so images are forwarded to neovim.

Jupytext integration converts notebook buffers from and to `py:percent` format.

## Commands and API

Commands:

- `:PyreplOpen` - select a kernel and open the REPL.
- `:PyreplHide` - hide the REPL window (kernel stays alive).
- `:PyreplClose` - close the REPL and shut down the kernel.
- `:PyreplSendVisual` - send the last visual selection.
- `:PyreplSendBuffer` - send the entire buffer.
- `:PyreplSendBlock` - send the "block" around the cursor (by default blocks are separated by lines matching `# %% ...`; configure via `block_pattern`).
- `:PyreplBlockForward` - move cursor to the start of the next block separated by `block_pattern`.
- `:PyreplBlockBackward` - move cursor to the start of the previous block separated by `block_pattern`.
- `:PyreplOpenImages` - open the image manager (history of recent images). Use `j`/`h` for previous, `k`/`l` for next, `dd` to delete, `q` or `<Esc>` to close.
- `:PyreplExport {path?}` - (python buffers only) export current buffer using `jupytext` (should be installed). Optionally provide path to export.
- `:PyreplInstall {tool}` - install pyrepl runtime packages into the configured Python (`tool`: `pip` or `uv`).

Lua API:

```lua
require("pyrepl").setup(opts)
require("pyrepl").open_repl()
require("pyrepl").hide_repl()
require("pyrepl").close_repl()
require("pyrepl").send_visual()
require("pyrepl").send_buffer()
require("pyrepl").send_block()
require("pyrepl").block_forward()
require("pyrepl").block_backward()
require("pyrepl").open_images()
require("pyrepl").export_to_notebook([name], [buf])
require("pyrepl").install_packages(tool)
```

## Tips & Tricks

### Use a dedicated Python environment

- By default pyrepl.nvim uses `python` (`python_path = "python"`). If Neovim is started inside a venv, that venv is usually used.
- For one dedicated interpreter, set `python_path` directly (or set `python_path = nil` to use `vim.g.python3_host_prog`).

Example dedicated interpreter workflow:

```bash
uv venv ~/.venv_nvim
source ~/.venv_nvim/bin/activate
uv pip install pynvim jupyter-console ipykernel
uv pip install pillow cairosvg # optional, for jpg and svg support
```

Then, in `init.lua`:

```lua
require("pyrepl").setup({
  python_path = "~/.venv_nvim/bin/python",
})
```

If to use this workflow you need to install kernels globally:

```bash
# from kernel virtual environment
python -m ipykernel install --user --name {kernel_name}
```

### Use a built-in Pygments style instead

If you do not like the treesitter-based REPL colors, disable it and pick a built-in Pygments theme:

```lua
require("pyrepl").setup({
  style_treesitter = false,
  style = "default", -- or another Pygments style, e.g. "gruvbox-dark"
})
```

### Send block and move to the next one

Combine "send" and "block" commands:

```lua
vim.keymap.set("n", "<leader>jb", function()
  vim.cmd("PyreplSendBlock")
  vim.cmd("PyreplBlockForward")
end)
```

## Thanks

- [molten.nvim](https://github.com/benlubas/molten-nvim)
- [pyrola.nvim](https://github.com/robitx/pyrola.nvim)
- [iron.nvim](https://github.com/Vigemus/iron.nvim)
