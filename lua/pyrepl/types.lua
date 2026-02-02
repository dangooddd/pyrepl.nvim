---@meta
error("Cannot require a meta file")

---@class pyrepl.Session
---@field bufnr integer
---@field kernel_name string|nil
---@field connection_file string|nil
---@field term_buf integer|nil
---@field term_win integer|nil
---@field term_chan integer|nil
---@field send_queue string[]
---@field send_flushing boolean
---@field repl_ready boolean
---@field closing boolean

---@class pyrepl.State
---@field sessions table<integer, pyrepl.Session>
---@field python_host string|nil

---@class pyrepl.Config
---@field split_horizontal boolean
---@field split_ratio number
---@field style string
---@field image_max_width_ratio number
---@field image_max_height_ratio number

---@class pyrepl.ConfigOpts
---@field split_horizontal? boolean
---@field split_ratio? number
---@field style? string
---@field image_max_width_ratio? number
---@field image_max_height_ratio? number

---@class pyrepl.KernelSpec
---@field name string
---@field path string|nil

---@class pyrepl.ImageConfig
---@field max_width_ratio number
---@field max_height_ratio number

---@class pyrepl.ImageEntry
---@field path string
