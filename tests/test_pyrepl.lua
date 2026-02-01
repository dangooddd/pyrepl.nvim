local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "tests/minimal_init.lua" })
        end,
        post_once = function()
            child.stop()
        end,
    },
})

T["setup registers PyREPL command"] = function()
    child.lua('require("pyrepl").setup()')
    local exists = child.fn.exists(":PyREPL")
    MiniTest.expect.equality(exists, 2)
end

T["setup merges config"] = function()
    child.lua([[require("pyrepl").setup({ split_ratio = 0.7, image = { cell_width = 12 } })]])

    local ratio = child.lua_get('require("pyrepl").config.split_ratio')
    local cell_width = child.lua_get('require("pyrepl").config.image.cell_width')
    local cell_height = child.lua_get('require("pyrepl").config.image.cell_height')

    MiniTest.expect.equality(ratio, 0.7)
    MiniTest.expect.equality(cell_width, 12)
    MiniTest.expect.equality(cell_height, 20)
end

T["image history updates without image.nvim"] = function()
    child.lua('require("pyrepl.image").history = {}')
    child.lua('require("pyrepl.image").history_index = 0')
    child.lua([[require("pyrepl.image").show_image_file("fake.png", 10, 10)]])

    local count = child.lua_get('#require("pyrepl.image").history')
    local index = child.lua_get('require("pyrepl.image").history_index')

    MiniTest.expect.equality(count, 1)
    MiniTest.expect.equality(index, 1)
end

T["image history no-op when empty"] = function()
    child.lua('require("pyrepl.image").history = {}')
    child.lua('require("pyrepl.image").history_index = 0')

    MiniTest.expect.no_error(function()
        child.lua('require("pyrepl.image").show_previous_image()')
    end)
end

T["send_buffer is safe when not ready"] = function()
    child.lua('require("pyrepl").setup()')

    MiniTest.expect.no_error(function()
        child.lua('require("pyrepl").send_buffer()')
    end)
end

return T
