local fn = vim.fn

local root = fn.fnamemodify(fn.resolve(fn.expand("<sfile>:p")), ":h:h")
local deps = root .. "/tests/deps"
local mini_path = deps .. "/mini.nvim"

if fn.isdirectory(mini_path) == 0 then
    fn.system({
        "git",
        "clone",
        "--depth",
        "1",
        "https://github.com/echasnovski/mini.nvim",
        mini_path,
    })
end

vim.opt.runtimepath:prepend(mini_path)
vim.opt.runtimepath:prepend(root)

vim.o.swapfile = false
vim.o.shadafile = "NONE"

local function collect_test_files()
    local files = vim.fs.find(function(name)
        return name:match("^test_.*%.lua$") ~= nil
    end, {
        path = root .. "/tests",
        type = "file",
        limit = math.huge,
    })
    local filtered = {}
    for _, path in ipairs(files) do
        if not path:find("/tests/deps/") then
            table.insert(filtered, path)
        end
    end
    return filtered
end

require("mini.test").setup({
    collect = {
        find_files = collect_test_files,
    },
})
