---@meta

---@class pyrepl.Config
---@field split_horizontal boolean
---@field split_ratio number
---@field style string
---@field image_max_history integer
---@field image_width_ratio number
---@field image_height_ratio number
---@field block_pattern string|nil
---@field python_path string|nil
---@field preferred_kernel string|nil

---@class pyrepl.ConfigOpts
---@field split_horizontal? boolean
---@field split_ratio? number
---@field style? string
---@field image_max_history? integer
---@field image_width_ratio? number
---@field image_height_ratio? number
---@field block_pattern? string
---@field python_path? string
---@field preferred_kernel? string

---@class pyrepl.KernelSpec
---@field name string
---@field resource_dir string

---@class pyrepl.ReplState
---@field buf integer
---@field chan integer
---@field win? integer
---@field kernel string

---@class pyrepl.ImageState
---@field history string[]
---@field history_index integer
---@field buf integer|nil
---@field win integer|nil
