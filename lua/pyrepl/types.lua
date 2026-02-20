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
---@field cell_pattern string|nil
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
---@field buf integer
---@field chan integer
---@field win? integer
---@field kernel string

---@generic pyrepl.TImage
---@class pyrepl.ImageProvider
---@field create fun(img_base64: string, buf: integer, win: integer): pyrepl.TImage|nil
---@field delete fun(image: pyrepl.TImage|nil): nil

---@class pyrepl.ImageState
---@field history string[]
---@field history_idx integer
---@field buf? integer
---@field win? integer
---@field image? any
