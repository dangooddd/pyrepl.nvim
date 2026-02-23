---@meta

---@class pyrepl.Config
---@field split_horizontal boolean
---@field split_ratio number
---@field style string
---@field style_treesitter boolean
---@field image_max_history integer
---@field image_width_ratio number
---@field image_height_ratio number
---@field image_provider string
---@field cell_pattern string
---@field python_path string|nil
---@field preferred_kernel string|nil
---@field jupytext_hook boolean

---@class pyrepl.ConfigOpts
---@field split_horizontal? boolean
---@field split_ratio? number
---@field style? string
---@field style_treesitter? boolean
---@field image_max_history? integer
---@field image_width_ratio? number
---@field image_height_ratio? number
---@field image_provider? string
---@field cell_pattern? string
---@field python_path? string
---@field preferred_kernel? string
---@field jupytext_hook? boolean

---@class pyrepl.KernelSpec
---@field name string
---@field resource_dir string

---@class pyrepl.ReplState
---@field chan integer
---@field kernel string
---@field closing boolean
---@field buf integer
---@field win? integer

---@class pyrepl.Image
---@field create fun(img_base64: string): pyrepl.Image|nil
---@field render fun(self: pyrepl.Image, buf: integer, win: integer)
---@field clear fun(self: pyrepl.Image)
---@field delete fun(self: pyrepl.Image)

---@class pyrepl.ImageHistoryState
---@field history pyrepl.Image[]
---@field idx integer
---@field closing boolean
---@field buf? integer
---@field win? integer
