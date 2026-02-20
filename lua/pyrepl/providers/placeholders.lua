---@class pyrepl.PlaceholdersObject
---@field buf integer
---@field id integer

---@type pyrepl.ImageProvider<pyrepl.PlaceholdersObject>
local M = {}

local ns = vim.api.nvim_create_namespace("PyreplPlaceholders")
local tmux_detected = nil
local used_ids = {}
local next_id = 0
local max_ids = 256
local placeholder = "\u{10EEEE}"
local esc = "\x1b"

-- stylua: ignore start
local diac = {
    "\u{0305}", "\u{030D}", "\u{030E}", "\u{0310}", "\u{0312}", "\u{033D}", "\u{033E}",
    "\u{033F}", "\u{0346}", "\u{034A}", "\u{034B}", "\u{034C}", "\u{0350}", "\u{0351}",
    "\u{0352}", "\u{0357}", "\u{035B}", "\u{0363}", "\u{0364}", "\u{0365}", "\u{0366}",
    "\u{0367}", "\u{0368}", "\u{0369}", "\u{036A}", "\u{036B}", "\u{036C}", "\u{036D}",
    "\u{036E}", "\u{036F}", "\u{0483}", "\u{0484}", "\u{0485}", "\u{0486}", "\u{0487}",
    "\u{0592}", "\u{0593}", "\u{0594}", "\u{0595}", "\u{0597}", "\u{0598}", "\u{0599}",
    "\u{059C}", "\u{059D}", "\u{059E}", "\u{059F}", "\u{05A0}", "\u{05A1}", "\u{05A8}",
    "\u{05A9}", "\u{05AB}", "\u{05AC}", "\u{05AF}", "\u{05C4}", "\u{0610}", "\u{0611}",
    "\u{0612}", "\u{0613}", "\u{0614}", "\u{0615}", "\u{0616}", "\u{0617}", "\u{0655}",
    "\u{0656}", "\u{0657}", "\u{0658}", "\u{0659}", "\u{065A}", "\u{065B}", "\u{065C}",
    "\u{065D}", "\u{065E}", "\u{06D6}", "\u{06D7}", "\u{06D8}", "\u{06D9}", "\u{06DA}",
    "\u{06DB}", "\u{06DC}", "\u{06DF}", "\u{06E0}", "\u{06E1}", "\u{06E2}", "\u{06E4}",
    "\u{06E7}", "\u{06E8}", "\u{06EA}", "\u{06EB}", "\u{06EC}", "\u{06ED}", "\u{0730}",
    "\u{0732}", "\u{0733}", "\u{0735}", "\u{0736}", "\u{073A}", "\u{073D}", "\u{073F}",
    "\u{0740}", "\u{0741}", "\u{0743}", "\u{0745}", "\u{0746}", "\u{0747}", "\u{0749}",
    "\u{074A}", "\u{07EB}", "\u{07EC}", "\u{07ED}", "\u{07EE}", "\u{07EF}", "\u{07F0}",
    "\u{07F1}", "\u{07F3}", "\u{0816}", "\u{0817}", "\u{0818}", "\u{0819}", "\u{081B}",
    "\u{081C}", "\u{081D}", "\u{081E}", "\u{081F}", "\u{0820}", "\u{0821}", "\u{0822}",
    "\u{0823}", "\u{0825}", "\u{0826}", "\u{0827}", "\u{0829}", "\u{082A}", "\u{082B}",
    "\u{082C}", "\u{082D}", "\u{0951}", "\u{0952}", "\u{0953}", "\u{0954}", "\u{0F18}",
    "\u{0F19}", "\u{0F35}", "\u{0F37}", "\u{0F39}", "\u{0F71}", "\u{0F72}", "\u{0F73}",
    "\u{0F74}", "\u{0F75}", "\u{0F76}", "\u{0F77}", "\u{0F78}", "\u{0F79}", "\u{0F7A}",
    "\u{0F7B}", "\u{0F7C}", "\u{0F7D}", "\u{0F7E}", "\u{0F7F}", "\u{0F80}", "\u{0F81}",
    "\u{0F82}", "\u{0F83}", "\u{0F84}", "\u{0F86}", "\u{0F87}", "\u{0FC6}", "\u{1037}",
    "\u{1039}", "\u{103A}", "\u{1087}", "\u{1088}", "\u{1089}", "\u{108A}", "\u{108B}",
    "\u{108C}", "\u{108D}", "\u{108F}", "\u{109A}", "\u{109B}", "\u{109C}", "\u{109D}",
    "\u{109E}", "\u{109F}", "\u{17C9}", "\u{17CA}", "\u{17CB}", "\u{17CC}", "\u{17CD}",
    "\u{17CE}", "\u{17CF}", "\u{17D0}", "\u{17D1}", "\u{17D2}", "\u{17D3}", "\u{17D7}",
    "\u{17DD}", "\u{1A75}", "\u{1A76}", "\u{1A77}", "\u{1A78}", "\u{1A79}", "\u{1A7A}",
    "\u{1A7B}", "\u{1A7C}", "\u{1A7F}", "\u{1B6B}", "\u{1B6D}", "\u{1B6E}", "\u{1B6F}",
    "\u{1B70}", "\u{1B71}", "\u{1B72}", "\u{1B73}", "\u{1CD0}", "\u{1CD1}", "\u{1CD2}",
    "\u{1CD3}", "\u{1CD4}", "\u{1CD5}", "\u{1CD6}", "\u{1CD7}", "\u{1CD8}", "\u{1CD9}",
    "\u{1CDA}", "\u{1CDB}", "\u{1CDC}", "\u{1CDD}", "\u{1CDE}", "\u{1CDF}", "\u{1CE0}",
    "\u{1CE2}", "\u{1CE3}", "\u{1CE4}", "\u{1CE5}", "\u{1CE6}", "\u{1CE7}", "\u{1CE8}",
    "\u{1CED}", "\u{1CF4}", "\u{1CF8}", "\u{1CF9}", "\u{1DC0}", "\u{1DC1}", "\u{1DC3}",
    "\u{1DC4}", "\u{1DC5}", "\u{1DC6}", "\u{1DC7}", "\u{1DC8}", "\u{1DC9}", "\u{1DCB}",
    "\u{1DCC}", "\u{1DD1}", "\u{1DD2}", "\u{1DD3}", "\u{1DD4}", "\u{1DD5}", "\u{1DD6}",
    "\u{1DD7}", "\u{1DD8}", "\u{1DD9}", "\u{1DDA}", "\u{1DDB}", "\u{1DDC}", "\u{1DDD}",
    "\u{1DDE}", "\u{1DDF}", "\u{1DE0}", "\u{1DE1}", "\u{1DE2}", "\u{1DE3}", "\u{1DE4}",
    "\u{1DE5}", "\u{1DE6}", "\u{1DE7}", "\u{1DE8}", "\u{1DE9}", "\u{1DEA}", "\u{1DEB}",
    "\u{1DEC}", "\u{1DED}", "\u{1DEE}", "\u{1DEF}", "\u{1DF0}", "\u{1DF1}", "\u{1DF2}",
    "\u{1DF3}", "\u{1DF4}", "\u{1DF5}", "\u{1DF6}", "\u{1DF7}", "\u{1DF8}", "\u{1DF9}",
    "\u{1DFA}", "\u{1DFB}", "\u{1DFC}", "\u{1DFD}", "\u{1DFE}", "\u{1DFF}", "\u{20D0}",
    "\u{20D1}", "\u{20D4}", "\u{20D5}",
}
-- stylua: ignore end

---Wrap an escape sequence so tmux passes it through to the terminal.
---@param sequence string
---@return string
local function wrap_tmux(sequence)
    return esc .. "Ptmux;" .. sequence:gsub(esc, esc .. esc) .. esc .. "\\"
end

---Detect tmux by sending DA1.
---@param timeout_ms integer
---@return boolean
local function detect_tmux(timeout_ms)
    if type(vim.api.nvim_ui_send) ~= "function" then
        return false
    end

    local detected = false
    local autocmd

    autocmd = vim.api.nvim_create_autocmd("TermResponse", {
        callback = function(args)
            local sequence = args.data.sequence
            if type(sequence) ~= "string" then
                return
            end

            if sequence:find(esc .. "%[%?[%d;]*c") then
                detected = true
                pcall(vim.api.nvim_del_autocmd, autocmd)
            end
        end,
    })

    vim.api.nvim_ui_send(wrap_tmux(esc .. "[c"))
    vim.wait(timeout_ms, function()
        return detected
    end, 5)
    pcall(vim.api.nvim_del_autocmd, autocmd)
    return detected
end

---@return boolean
local function is_tmux()
    if tmux_detected ~= nil then
        return tmux_detected
    end

    if vim.env.TMUX and vim.env.TMUX ~= "" then
        tmux_detected = true
        return tmux_detected
    end

    tmux_detected = detect_tmux(150)
    return tmux_detected
end

---Send a kitty graphics APC sequence to stderr.
---@param body string
local function send_apc(body)
    local sequence = esc .. "_G" .. body .. esc .. "\\"
    if is_tmux() then
        sequence = wrap_tmux(sequence)
    end
    vim.api.nvim_chan_send(vim.v.stderr, sequence)
end

---Upload base64 PNG data to the terminal image store.
---@param img_id integer
---@param img_data string
local function upload_image(img_id, img_data)
    send_apc(("f=100,t=d,i=%d,q=2;%s"):format(img_id, img_data))
    used_ids[img_id] = true
end

---@param img_id integer
local function delete_image(img_id)
    pcall(send_apc, ("a=d,d=I,i=%d,q=2"):format(img_id))
    used_ids[img_id] = false
end

---Place an uploaded image into a cell region.
---@param img_id integer
---@param cols integer
---@param rows integer
local function create_placement(img_id, cols, rows)
    send_apc(("a=p,U=1,i=%d,c=%d,r=%d,C=1,q=2"):format(img_id, cols, rows))
end

---@return integer
local function get_image_id()
    for _ = 1, max_ids do
        next_id = (next_id % max_ids) + 1
        if not used_ids[next_id] then
            return next_id
        end
    end
    next_id = (next_id % max_ids) + 1
    return next_id
end

---@class pyrepl.PlaceholdersGeometry
---@field x? integer
---@field y? integer
---@field rows? integer
---@field cols? integer

---Draw image in buffer with given geometry.
---@param buf integer
---@param img_id integer
---@param geometry pyrepl.PlaceholdersGeometry
local function draw(buf, img_id, geometry)
    local x = geometry.x or 0
    local y = geometry.y or 0
    local rows = geometry.rows or 0
    local cols = geometry.cols or 0
    vim.bo[buf].modifiable = true

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    -- pad buffer so image can fit
    local buf_lines = vim.api.nvim_buf_line_count(buf)
    local extra = {}
    for _ = 1, (y + rows - buf_lines) do
        extra[#extra + 1] = ""
    end
    vim.api.nvim_buf_set_lines(buf, buf_lines, buf_lines, false, extra)

    -- highlight placeholders
    local hl = string.format("PyreplPlaceholdersImage_%d", img_id)
    if vim.fn.hlexists(hl) == 0 then
        -- unique for each image
        vim.api.nvim_set_hl(0, hl, { fg = img_id, ctermfg = img_id })
    end

    -- write placeholders
    for r = 1, rows do
        local line = placeholder .. diac[r] .. string.rep(placeholder, cols - 1)
        vim.api.nvim_buf_set_extmark(buf, ns, y + r - 1, 0, {
            virt_text = { { line, hl } },
            virt_text_win_col = x,
            hl_mode = "combine",
        })
    end

    vim.bo[buf].modifiable = false
    vim.defer_fn(function()
        create_placement(img_id, cols, rows)
    end, 25)
end

---Render a placeholder grid that the terminal replaces with the image.
---@param img_base64 string
---@param buf integer
---@param win integer
---@return pyrepl.PlaceholdersObject|nil
function M.create(img_base64, buf, win)
    if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
        return
    end

    local id = get_image_id()
    local rows = vim.api.nvim_win_get_height(win)
    local cols = vim.api.nvim_win_get_width(win)

    upload_image(id, img_base64)

    draw(buf, id, {
        x = 0,
        y = 0,
        rows = rows,
        cols = cols,
    })

    return {
        buf = buf,
        id = id,
    }
end

---Delete placeholders image, clear hl groups.
---@param image pyrepl.PlaceholdersObject|nil
function M.delete(image)
    if image then
        delete_image(image.id)
        pcall(vim.api.nvim_set_hl, 0, "PyreplPlaceholdersImage_" .. image.id, {})
        pcall(vim.api.nvim_buf_clear_namespace, image.buf, ns, 0, -1)
    end
end

return M
