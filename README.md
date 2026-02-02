# pyrepl.nvim

pyrepl.nvim provides a Python REPL inside Neovim using Jupyter kernels.

## Install (lazy.nvim)

```lua
{
    "dangooddd/pyrepl.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "3rd/image.nvim",
    },
    build = ":UpdateRemotePlugins",
    config = function()
        require("pyrepl").setup({
            style = "default",
            split_horizontal = false,
            split_ratio = 0.5,
            image_max_width_ratio = 0.4,
            image_max_height_ratio = 0.4,
        })
    end,
}
```

If you use image rendering, also call `require("image").setup()` in your
Neovim config per image.nvim docs.

## Usage

- Start REPL: `:PyREPL`
- Send code: `require("pyrepl").send_statement()`,
  `require("pyrepl").send_visual()`, `require("pyrepl").send_buffer()`
- Image manager: `require("pyrepl").open_images()`

## Dependencies

- Neovim Python provider configured (see `:help provider-python`)
- Python packages installed in the `python3_host_prog` interpreter:
  `pynvim`, `jupyter-client`, `prompt-toolkit`, `pillow`, `pygments`,
  `ipykernel`
- Tree-sitter Python parser (for `send_statement`)
- Image rendering uses image.nvim and supports whatever image.nvim supports
  (formats and backends). Install image.nvim dependencies as documented there.
  `image_max_*_ratio` sets the target render size and can upscale images.

## Docs

```
:help pyrepl
```
