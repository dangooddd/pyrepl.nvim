---@meta
error("Cannot require a meta file")

---@class pyrepl.Config
---@field split_horizontal boolean
---@field split_ratio number
---@field style string
---@field image_width_ratio number
---@field image_height_ratio number
---@field filetypes table<string>|nil
---@field block_pattern string|nil

---@class pyrepl.ConfigOpts
---@field split_horizontal? boolean
---@field split_ratio? number
---@field style? string
---@field image_width_ratio? number
---@field image_height_ratio? number
---@field filetypes? table<string>
---@field block_pattern? string

---@class pyrepl.KernelSpec
---@field name string
---@field resource_dir string

---@class pyrepl.ReplState
---@field buf integer
---@field chan integer
---@field win? integer
---@field kernel string

---@class pyrepl.ImageState
---@field history pyrepl.ImageEntry[]
---@field history_index integer
---@field current_buf integer|nil
---@field current_winid integer|nil
---@field manager_active boolean

---@class pyrepl.ImageConfig
---@field image_width_ratio number
---@field image_height_ratio number

---@class pyrepl.ImageEntry
---@field data string
