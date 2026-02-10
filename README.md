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
      style = "default",
      image_max_history = 10,
      image_width_ratio = 0.5,
      image_height_ratio = 0.5,
      block_pattern = "^# %%%%.*$",
      python_path = "python",
      preferred_kernel = "python3",
    })

    vim.keymap.set("n", "<leader>jo", ":PyreplOpen<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jh", ":PyreplHide<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jc", ":PyreplClose<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jb", ":PyreplSendBlock<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jf", ":PyreplSendBuffer<CR>", { silent = true })
    vim.keymap.set("v", "<leader>jv", ":<C-u>PyreplSendVisual<CR>gv<Esc>", { silent = true })
    vim.keymap.set("n", "<leader>ji", ":PyreplOpenImages<CR>", { silent = true })
    vim.keymap.set("n", "<leader>js", ":PyreplInstall")
  end,
}
```

> [!NOTE]
> pyrepl.nvim is no longer a Python remote plugin. You do not need `:UpdateRemotePlugins`.

Minimal environment:

```bash
python -m pip install pynvim jupyter-console
python -m pip install pillow cairosvg # optional, for jpg and svg support
python -m ipykernel install --user --name python3
```

You can also install pyrepl runtime packages in the configured Python directly from Neovim:

```vim
:PyreplInstall pip
:PyreplInstall uv
```

> [!NOTE]
> `uv` and `pip` is a backend used to install packages

Notes:

- By default pyrepl.nvim uses `python` (`python_path = "python"`). If Neovim is started inside a venv, that venv will be used.
- If you prefer one dedicated global interpreter, you can set `python_path = "~/.venv_nvim/bin/python"` or `python_path = nil` - `vim.g.python3_host_prog` will be used instead.

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
  python_path = "~/.venv_nvim/bin/python", -- optional; default is "python"
})
```

## Demo

https://github.com/user-attachments/assets/96cfd16b-4049-44e6-ae24-14739b6fbfcb

## Preface

pyrepl.nvim is a heavily rewritten fork of [pyrola.nvim](https://github.com/robitx/pyrola.nvim). The goal was to make the workflow nicer for Python and to keep the codebase cleaner (subjective).

Main differences from pyrola:

- No Neovim remote plugin dependency (`:UpdateRemotePlugins` is not needed).
- Uses `jupyter-console` as the UI instead of a custom console. Less code, and usually better maintained.
- Supports Pygments styles via the `style` config option for REPL highlighting.
- Kernel is initialized via a prompt rather than fixed values. You can tune default ordering with `preferred_kernel`.
- On supported terminals, images render correctly via kitty unicode placeholders.
- Utility functions to make life easier: Close, Hide and Install commands.

And a quick note about images: I'm really proud of this part, because the plugin worked even in a local -> ssh -> tmux -> docker setup (and images still rendered!).

## Known Limitations / Regressions

- Inspector is not supported for now (to keep maintenance simpler). Contributions appreciated.
- Image rendering currently requires terminals that support kitty graphics protocol (unicode placeholders). Why: inside Docker containers `TIOCGWINSZ` can return pixel size as `0`, and backends that depend on pixel dimensions fail to compute scaling correctly (see https://github.com/3rd/image.nvim/issues/331). Supporting other backends is possible with contributions.
- According to kitty's documentation, the protocol is implemented not only in kitty, but also in other terminals: Ghostty, Konsole, st (with a patch), Warp, wayst, WezTerm, iTerm2: https://sw.kovidgoyal.net/kitty/graphics-protocol/
- Only Python is officially supported and will be prioritized. For R, see https://github.com/R-nvim/R.nvim. In theory, an R kernel should work, but it's not a project goal.

## How It Works

In short: pyrepl.nvim starts a Jupyter kernel and opens `jupyter-console` as the UI in a terminal buffer. Neovim commands send code into that terminal using bracketed paste (so pasted code behaves predictably), and you see the output right in `jupyter-console`.

pyrepl.nvim keeps one active REPL session. You can hide/show that REPL from any buffer, and `:PyreplClose` shuts the kernel down.

## Commands and API

Commands are regular user commands created by `require("pyrepl").setup(...)`.

Commands:

- `:PyreplOpen` - select a kernel and open the REPL.
- `:PyreplHide` - hide the REPL window (kernel stays alive).
- `:PyreplClose` - close the REPL and shut down the kernel.
- `:PyreplSendVisual` - send the last visual selection.
- `:PyreplSendBuffer` - send the entire buffer.
- `:PyreplSendBlock` - send the "block" around the cursor (by default blocks are separated by lines matching `# %% ...`; configure via `block_pattern`).
- `:PyreplOpenImages` - open the image manager (history of recent images). Use `j`/`h` for previous, `k`/`l` for next, `dd` to delete, `q` or `<Esc>` to close.
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
require("pyrepl").open_images()
require("pyrepl").install_packages(tool)
```

## Thanks

- [molten.nvim](https://github.com/benlubas/molten-nvim)
- [pyrola.nvim](https://github.com/robitx/pyrola.nvim)
- [iron.nvim](https://github.com/Vigemus/iron.nvim)

## Documentation

```
:help pyrepl
```
