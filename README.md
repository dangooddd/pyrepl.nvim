
<div align="center">

</div><img width="2004" height="538" alt="logo" src="https://github.com/user-attachments/assets/f4e9d2f9-488a-4d02-9cea-a7ced4c44011" />

---

# pyrepl.nvim

If you are seeking an alternative to **Jupyter**, **Spyder**, or **RStudio** in Neovim, **pyrepl.nvim** is the solution.

pyrepl.nvim delivers a **Python REPL (Read–Eval–Print Loop)** experience inside **Neovim**. It is designed for interactive programming, especially for **data scientists**, and supports:

* Real-time code execution
* Image visualization

pyrepl.nvim is built on the Jupyter kernel stack and focuses exclusively on **Python** for simplicity.

---

## DEMO VIDEO

<div align="center">
  <a href="https://www.youtube.com/watch?v=S3arFOPnD40">
    <img src="https://img.youtube.com/vi/S3arFOPnD40/0.jpg" alt="Watch the video" style="width:100%;">
  </a>
</div>

## Features

- **Real-time REPL**: Execute code dynamically within Neovim, allowing for immediate feedback and interaction.

- **Multiple Code Block Selection Methods**: You can send code via semantic code block identification (based on the Tree-sitter syntax parser), visual selection, or send the entire buffer to the REPL console with one click.

- **Image Viewer**: Preview image outputs inside Neovim using `image.nvim`, providing a clean, dedicated floating window for plots and figures.

- **Images Manager**: Stores historical images and allows browsing previously plotted images in a Neovim floating window.

## Installation

### 1) Default setup

Add pyrepl.nvim to your plugin manager. An example using `lazy.nvim` is provided below:

```lua
{
  "matarina/pyrepl.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "3rd/image.nvim" },
  build = ":UpdateRemotePlugins",
  config = function()
    local pyrepl = require("pyrepl")

    pyrepl.setup({
      split_horizontal = false,
      split_ratio = 0.65, -- width of split REPL terminal
      image = {
        cell_width = 10, -- approximate terminal cell width in pixels
        cell_height = 20, -- approximate terminal cell height in pixels
        max_width_ratio = 0.5, -- image width as a fraction of editor columns
        max_height_ratio = 0.5, -- image height as a fraction of editor lines
      },
    })

    -- Default key mappings (adjust to taste)

    -- Send semantic code block under cursor
    vim.keymap.set("n", "<CR>", function()
      pyrepl.send_statement()
    end, { noremap = true })

    -- Send visual selection
    vim.keymap.set("v", "<leader>vs", function()
      pyrepl.send_visual()
    end, { noremap = true })

    -- Send entire buffer
    vim.keymap.set("n", "<leader>vb", function()
      pyrepl.send_buffer()
    end, { noremap = true })

    -- Open images manager
    vim.keymap.set("n", "<leader>im", function()
      pyrepl.open_images()
    end, { noremap = true })
  end,
},

-- Tree-sitter is required.
-- Install the Python parser for Tree-sitter.
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local ts = require("nvim-treesitter")

    ts.setup({
      install_dir = vim.fn.stdpath("data") .. "/site",
    })

    -- Install required parsers
    ts.install({ "python", "lua" })
  end,
}

```

Highlight groups are theme-aware by default (linked to `FloatBorder`, `FloatTitle`, and `NormalFloat`). Override them if you want custom colors:

```lua
vim.api.nvim_set_hl(0, "PyREPLImageBorder", { link = "FloatBorder" })
vim.api.nvim_set_hl(0, "PyREPLImageTitle", { link = "FloatTitle" })
vim.api.nvim_set_hl(0, "PyREPLImageNormal", { link = "NormalFloat" })
```

Vim help is available after running `:helptags` in the plugin `doc` directory:

```vim
:help pyrepl

```

### 2) Python + Pip in PATH

pyrepl.nvim is built on `pynvim`, so ensure `python` and `pip` are available in your PATH. Virtual environments (like Conda) are highly recommended.

If you use uv (recommended for this repo), install the package in editable mode:

```bash
uv pip install -e .

```

after setting up your `init.lua` and then activate a Conda environment, pyrepl.nvim will automatically prompt you to install the related Python dependencies when first time run `:PyREPL`. Alternatively, you can install them manually:

```bash
python3 -m pip install pynvim jupyter-client prompt-toolkit pillow pygments

```

Then, install a Python Jupyter kernel:

```bash
python3 -m pip install ipykernel
python3 -m ipykernel install --user --name python3

```

### 3) Image Rendering (Recommended)

pyrepl.nvim renders images using [image.nvim](https://github.com/3rd/image.nvim). Install it and its dependencies:

- A supported terminal (Kitty recommended) or ueberzugpp backend
- ImageMagick

Follow the [image.nvim setup guide](https://github.com/3rd/image.nvim#dependencies) for your platform.

Make sure you call `require("image").setup()` in your Neovim config as described in the image.nvim README.

**Note for tmux:**
Image hiding/showing on pane or window switches relies on focus events. to enable tmux focus events for the current session.  configure  the following to your `~/.tmux.conf`:

```tmux
set -g focus-events on
set -g allow-passthrough all

```

## Usage

### Start a REPL

1. Open a Python file (filetype `python`).
```vim
:echo &filetype

```


2. Start the kernel and REPL (you will be prompted to select a kernel):
```vim
:PyREPL

```

pyrepl.nvim prefers the active `VIRTUAL_ENV` kernel first, then `CONDA_PREFIX`, when available.



### Send Code

* **Current semantic block**:
```lua
pyrepl.send_statement()

```


* **Visual selection**:
```lua
pyrepl.send_visual()

```


* **Whole buffer**:
```lua
pyrepl.send_buffer()

```



### Images Manager

Press `<leader>im` (or your configured key) to open the images manager.

When focused:

* `h` — Previous image
* `l` — Next image
* `q` — Close
  
## Tests

### Python

```bash
python3 -m pip install pytest

python3 -m pytest tests/python

```

### Lua (mini.test)

```bash
nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"

```

### Makefile

```bash
make test

```

The Lua test runner will bootstrap `mini.nvim` into `tests/deps/mini.nvim` if it's missing (requires `git`).

## Credits

* [Jupyter Team](https://github.com/jupyter/jupyter)
* [nvim-python-repl](https://github.com/geg2102/nvim-python-repl) — pyrepl.nvim draws inspiration from this project.
