# pyrepl.nvim

pyrepl.nvim provides a Python REPL inside Neovim using Jupyter kernels.

## Install (lazy.nvim)

```lua
{
    "dangooddd/pyrepl.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    build = ":UpdateRemotePlugins",
    config = function()
        require("pyrepl").setup({
            style = "default",
            split_horizontal = false,
            split_ratio = 0.5,
            image_width_ratio = 0.4,
            image_height_ratio = 0.4,
        })
    end,
}
```

Example with keymaps:

```lua
{
    "dangooddd/pyrepl.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    build = ":UpdateRemotePlugins",
    config = function()
        local pyrepl = require("pyrepl")

        pyrepl.setup({
            style = "gruvbox-dark",
        })

        vim.keymap.set("n", "<leader>jo", ":PyREPLOpen<CR>", { silent = true })
        vim.keymap.set("n", "<leader>jh", ":PyREPLHide<CR>", { silent = true })
        vim.keymap.set("n", "<leader>jc", ":PyREPLClose<CR>", { silent = true })
        vim.keymap.set("n", "<leader>js", ":PyREPLSendStatement<CR>", { silent = true })
        vim.keymap.set("n", "<leader>jb", ":PyREPLSendBuffer<CR>", { silent = true })
        vim.keymap.set("v", "<leader>jv", ":<C-u>PyREPLSendVisual<CR>gv", { silent = true })
        vim.keymap.set("n", "<leader>ji", ":PyREPLOpenImages<CR>", { silent = true })
    end,
}
```

Image rendering uses a terminal graphics protocol backend and sends PNG data.
Use a compatible terminal (for example kitty). Over SSH it requires a terminal
that passes graphics APC sequences.

## Usage

- Start REPL: `:PyREPLOpen`
- Send code: `:PyREPLSendStatement`, `:PyREPLSendVisual`, `:PyREPLSendBuffer`
  (visual uses last selection; map like `:<C-u>PyREPLSendVisual<CR>gv`)
- Image manager: `:PyREPLOpenImages`

Notes:
- Each buffer has its own kernel session.
- Closing the buffer shuts down its kernel and closes its terminal.
- Closing the REPL terminal window only clears the terminal; the kernel stays attached.
- Use `:PyREPLHide` to hide the REPL window and `:PyREPLClose` to close the REPL buffer and kernel.
- Commands are buffer-local and available in any filetype.

## Dependencies

- Neovim Python provider configured (see `:help provider-python`)
- Python packages installed in the `python3_host_prog` interpreter:
  `pynvim`, `jupyter-client`, `jupyter-console`, `ipykernel`
- Optional for images: `pillow` (JPEG conversion), `cairosvg` (SVG conversion)
- pyrepl.nvim does not auto-install dependencies.
- Tree-sitter Python parser (for `send_statement`)
- Image rendering uses a terminal graphics protocol backend (kitty-compatible)
  and sends PNG data (JPEG is converted). `image_*_ratio` sets the target
  render size and can upscale images.

## Docs

```
:help pyrepl
```
