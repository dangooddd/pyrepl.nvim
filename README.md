# pyrepl.nvim

pyrepl.nvim is a Python REPL inside Neovim powered by Jupyter kernels. It opens a real `jupyter-console` UI in a terminal split and provides commands to send code from your buffer to the selected kernel.

## Quickstart

Important: this is a Python remote plugin. After installation you must run `:UpdateRemotePlugins` (for example via `build = ":UpdateRemotePlugins"` in lazy.nvim) and restart Neovim.

Recommended workflow for a quick start:

```bash
uv venv ~/.venv_nvim
source ~/.venv_nvim/bin/activate
uv pip install pynvim jupyter-client jupyter-console
uv pip install pillow cairosvg # for jpg and svg support
```

Then, in `init.lua`:

```lua
vim.g.python3_host_prog = "~/.venv_nvim/bin/python"
```

Next, install the plugin and register a kernelspec (once per user/system):

```bash
~/.venv_nvim/bin/python -m pip install ipykernel
~/.venv_nvim/bin/python -m ipykernel install --user --name python3
```

Minimal lazy.nvim setup with the default config and example keymaps:

```lua
{
  "dangooddd/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  build = ":UpdateRemotePlugins",
  config = function()
    require("pyrepl").setup({
      -- defaults (you can omit these):
      split_horizontal = false,
      split_ratio = 0.5,
      style = "default",
      image_width_ratio = 0.4,
      image_height_ratio = 0.5,
      filetypes = nil,
      block_pattern = "^# %%%%.*$",
    })

    vim.keymap.set("n", "<leader>jo", ":PyreplOpen<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jh", ":PyreplHide<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jc", ":PyreplClose<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jb", ":PyreplSendBlock<CR>", { silent = true })
    vim.keymap.set("n", "<leader>jf", ":PyreplSendBuffer<CR>", { silent = true })
    vim.keymap.set("v", "<leader>jv", ":<C-u>PyreplSendVisual<CR>gv<Esc>", { silent = true })
    vim.keymap.set("n", "<leader>ji", ":PyreplOpenImages<CR>", { silent = true })
  end,
}
```

## Preface

pyrepl.nvim is a heavily rewritten fork of [pyrola.nvim](https://github.com/robitx/pyrola.nvim). The goal was to make the workflow nicer for Python and to keep the codebase cleaner (subjective).

Main differences from pyrola:

- Uses `jupyter-console` as the UI instead of a custom console. Less code, and usually better maintained.
- Supports Pygments styles via the `style` config option for REPL highlighting.
- Kernel is initialized via a prompt rather than fixed values. The kernel from the current venv is always offered first for better UX (thanks molten.nvim for the idea).
- Supports multiple kernels at the same time for different buffers (unlike pyrola).
- On supported terminals, images render correctly via kitty unicode placeholders.

And a quick note about images: I'm really proud of this part, because the plugin worked even in a local -> ssh -> tmux -> docker setup (and images still rendered!).

## Known Limitations / Regressions

- Inspector is not supported for now (to keep maintenance simpler). Contributions appreciated.
- Image rendering currently requires terminals that support kitty graphics protocol (unicode placeholders). Why: inside Docker containers `TIOCGWINSZ` can return pixel size as `0`, and backends that depend on pixel dimensions fail to compute scaling correctly (see https://github.com/3rd/image.nvim/issues/331). Supporting other backends is possible with contributions.
- According to kitty's documentation, the protocol is implemented not only in kitty, but also in other terminals: Ghostty, Konsole, st (with a patch), Warp, wayst, WezTerm, iTerm2: https://sw.kovidgoyal.net/kitty/graphics-protocol/
- Only Python is officially supported and will be prioritized. For R, see https://github.com/R-nvim/R.nvim. In theory, an R kernel should work, but it's not a project goal.

## How It Works

In short: pyrepl.nvim starts a Jupyter kernel (via `jupyter_client`) and opens `jupyter-console` as the UI in a terminal buffer. Neovim commands send code into that terminal using bracketed paste (so pasted code behaves predictably), and you see the output right in `jupyter-console`.

Each source buffer has its own kernel session. This is convenient when you keep multiple files/projects open and don't want namespaces to mix.

## Commands and API

Commands are created buffer-locally (for selected filetypes, see `filetypes` in config).

Commands:

- `:PyreplOpen` - select a kernel and open the REPL.
- `:PyreplHide` - hide the REPL window (kernel stays alive).
- `:PyreplClose` - close the REPL and shut down the kernel.
- `:PyreplSendVisual` - send the last visual selection.
- `:PyreplSendBuffer` - send the entire buffer.
- `:PyreplSendBlock` - send the "block" around the cursor (by default blocks are separated by lines matching `# %% ...`; configure via `block_pattern`).
- `:PyreplOpenImages` - open the image manager (history of recent images).

Lua API:

```lua
require("pyrepl").setup(opts)
require("pyrepl").open_repl([buf])
require("pyrepl").hide_repl([buf])
require("pyrepl").close_repl([buf])
require("pyrepl").send_visual([buf])
require("pyrepl").send_buffer([buf])
require("pyrepl").send_block([buf])
require("pyrepl").open_images()
require("pyrepl").get_config()
```

## Thanks

- [molten.nvim](https://github.com/benlubas/molten-nvim)
- [pyrola.nvim](https://github.com/robitx/pyrola.nvim)
- [iron.nvim](https://github.com/Vigemus/iron.nvim)

## Documentation

```
:help pyrepl
```
