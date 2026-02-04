local api = vim.api
local fn = vim.fn

local M = {}

local NS = api.nvim_create_namespace("PyreplImagePlaceholders")
local AUGROUP = api.nvim_create_augroup("PyreplImagePlaceholders", { clear = false })

local PLACEHOLDER = "\u{10EEEE}"

local DIACRITICS = {
    "\u{0305}", "\u{030D}", "\u{030E}", "\u{0310}", "\u{0312}", "\u{033D}", "\u{033E}", "\u{033F}",
    "\u{0346}", "\u{034A}", "\u{034B}", "\u{034C}", "\u{0350}", "\u{0351}", "\u{0352}", "\u{0357}",
    "\u{035B}", "\u{0363}", "\u{0364}", "\u{0365}", "\u{0366}", "\u{0367}", "\u{0368}", "\u{0369}",
    "\u{036A}", "\u{036B}", "\u{036C}", "\u{036D}", "\u{036E}", "\u{036F}", "\u{0483}", "\u{0484}",
    "\u{0485}", "\u{0486}", "\u{0487}", "\u{0592}", "\u{0593}", "\u{0594}", "\u{0595}", "\u{0597}",
    "\u{0598}", "\u{0599}", "\u{059C}", "\u{059D}", "\u{059E}", "\u{059F}", "\u{05A0}", "\u{05A1}",
    "\u{05A8}", "\u{05A9}", "\u{05AB}", "\u{05AC}", "\u{05AF}", "\u{05C4}", "\u{0610}", "\u{0611}",
    "\u{0612}", "\u{0613}", "\u{0614}", "\u{0615}", "\u{0616}", "\u{0617}", "\u{0655}", "\u{0656}",
    "\u{0657}", "\u{0658}", "\u{0659}", "\u{065A}", "\u{065B}", "\u{065C}", "\u{065D}", "\u{065E}",
    "\u{06D6}", "\u{06D7}", "\u{06D8}", "\u{06D9}", "\u{06DA}", "\u{06DB}", "\u{06DC}", "\u{06DF}",
    "\u{06E0}", "\u{06E1}", "\u{06E2}", "\u{06E4}", "\u{06E7}", "\u{06E8}", "\u{06EA}", "\u{06EB}",
    "\u{06EC}", "\u{06ED}", "\u{0730}", "\u{0732}", "\u{0733}", "\u{0735}", "\u{0736}", "\u{073A}",
    "\u{073D}", "\u{073F}", "\u{0740}", "\u{0741}", "\u{0743}", "\u{0745}", "\u{0746}", "\u{0747}",
    "\u{0749}", "\u{074A}", "\u{07EB}", "\u{07EC}", "\u{07ED}", "\u{07EE}", "\u{07EF}", "\u{07F0}",
    "\u{07F1}", "\u{07F3}", "\u{0816}", "\u{0817}", "\u{0818}", "\u{0819}", "\u{081B}", "\u{081C}",
    "\u{081D}", "\u{081E}", "\u{081F}", "\u{0820}", "\u{0821}", "\u{0822}", "\u{0823}", "\u{0825}",
    "\u{0826}", "\u{0827}", "\u{0829}", "\u{082A}", "\u{082B}", "\u{082C}", "\u{082D}", "\u{0951}",
    "\u{0952}", "\u{0953}", "\u{0954}", "\u{0F18}", "\u{0F19}", "\u{0F35}", "\u{0F37}", "\u{0F39}",
    "\u{0F71}", "\u{0F72}", "\u{0F73}", "\u{0F74}", "\u{0F75}", "\u{0F76}", "\u{0F77}", "\u{0F78}",
    "\u{0F79}", "\u{0F7A}", "\u{0F7B}", "\u{0F7C}", "\u{0F7D}", "\u{0F7E}", "\u{0F7F}", "\u{0F80}",
    "\u{0F81}", "\u{0F82}", "\u{0F83}", "\u{0F84}", "\u{0F86}", "\u{0F87}", "\u{0FC6}", "\u{1037}",
    "\u{1039}", "\u{103A}", "\u{1087}", "\u{1088}", "\u{1089}", "\u{108A}", "\u{108B}", "\u{108C}",
    "\u{108D}", "\u{108F}", "\u{109A}", "\u{109B}", "\u{109C}", "\u{109D}", "\u{109E}", "\u{109F}",
    "\u{17C9}", "\u{17CA}", "\u{17CB}", "\u{17CC}", "\u{17CD}", "\u{17CE}", "\u{17CF}", "\u{17D0}",
    "\u{17D1}", "\u{17D2}", "\u{17D3}", "\u{17D7}", "\u{17DD}", "\u{1A75}", "\u{1A76}", "\u{1A77}",
    "\u{1A78}", "\u{1A79}", "\u{1A7A}", "\u{1A7B}", "\u{1A7C}", "\u{1A7F}", "\u{1B6B}", "\u{1B6D}",
    "\u{1B6E}", "\u{1B6F}", "\u{1B70}", "\u{1B71}", "\u{1B72}", "\u{1B73}", "\u{1CD0}", "\u{1CD1}",
    "\u{1CD2}", "\u{1CD3}", "\u{1CD4}", "\u{1CD5}", "\u{1CD6}", "\u{1CD7}", "\u{1CD8}", "\u{1CD9}",
    "\u{1CDA}", "\u{1CDB}", "\u{1CDC}", "\u{1CDD}", "\u{1CDE}", "\u{1CDF}", "\u{1CE0}", "\u{1CE2}",
    "\u{1CE3}", "\u{1CE4}", "\u{1CE5}", "\u{1CE6}", "\u{1CE7}", "\u{1CE8}", "\u{1CED}", "\u{1CF4}",
    "\u{1CF8}", "\u{1CF9}", "\u{1DC0}", "\u{1DC1}", "\u{1DC3}", "\u{1DC4}", "\u{1DC5}", "\u{1DC6}",
    "\u{1DC7}", "\u{1DC8}", "\u{1DC9}", "\u{1DCB}", "\u{1DCC}", "\u{1DD1}", "\u{1DD2}", "\u{1DD3}",
    "\u{1DD4}", "\u{1DD5}", "\u{1DD6}", "\u{1DD7}", "\u{1DD8}", "\u{1DD9}", "\u{1DDA}", "\u{1DDB}",
    "\u{1DDC}", "\u{1DDD}", "\u{1DDE}", "\u{1DDF}", "\u{1DE0}", "\u{1DE1}", "\u{1DE2}", "\u{1DE3}",
    "\u{1DE4}", "\u{1DE5}", "\u{1DE6}", "\u{1DE7}", "\u{1DE8}", "\u{1DE9}", "\u{1DEA}", "\u{1DEB}",
    "\u{1DEC}", "\u{1DED}", "\u{1DEE}", "\u{1DEF}", "\u{1DF0}", "\u{1DF1}", "\u{1DF2}", "\u{1DF3}",
    "\u{1DF4}", "\u{1DF5}", "\u{1DF6}", "\u{1DF7}", "\u{1DF8}", "\u{1DF9}", "\u{1DFA}", "\u{1DFB}",
    "\u{1DFC}", "\u{1DFD}", "\u{1DFE}", "\u{1DFF}", "\u{20D0}", "\u{20D1}", "\u{20D4}", "\u{20D5}",
}

local function diac(n)
    return DIACRITICS[n + 1]
end

local function wrap_tmux_passthrough(sequence)
    if not vim.env.TMUX or vim.env.TMUX == "" then
        return sequence
    end
    local escaped = sequence:gsub("\x1b", "\x1b\x1b")
    return "\x1bPtmux;" .. escaped .. "\x1b\\"
end

local function send_apc(body)
    local sequence = "\x1b_G" .. body .. "\x1b\\"
    api.nvim_chan_send(vim.v.stderr, wrap_tmux_passthrough(sequence))
end

local function gen_id(maxn)
    local uv = vim.uv or vim.loop
    local t = uv.hrtime()
    return (t % maxn) + 1
end

local buffer_state = {}

local function configure_placeholder_window(win)
    if not api.nvim_win_is_valid(win) then
        return
    end
    api.nvim_set_option_value("wrap", false, { win = win })
    api.nvim_set_option_value("number", false, { win = win })
    api.nvim_set_option_value("relativenumber", false, { win = win })
    api.nvim_set_option_value("cursorline", false, { win = win })
    api.nvim_set_option_value("signcolumn", "no", { win = win })
    api.nvim_set_option_value("foldcolumn", "0", { win = win })
    api.nvim_set_option_value("spell", false, { win = win })
end

local function ensure_placeholder_hl(img_id, truecolor)
    local hl = ("PyREPLImagePlaceholder_%d"):format(img_id)
    if fn.hlexists(hl) == 0 then
        api.nvim_set_hl(0, hl, { fg = img_id, ctermfg = img_id })
        -- if truecolor then
        --     api.nvim_set_hl(0, hl, { fg = img_id })
        -- else
        --     api.nvim_set_hl(0, hl, { ctermfg = img_id })
        -- end
    end
    return hl
end

local function upload_image_data(img_id, data)
    send_apc(("f=100,t=d,i=%d,q=2;%s"):format(img_id, data))
end

local function create_virtual_placement(img_id, cols, rows)
    send_apc(("a=p,U=1,i=%d,c=%d,r=%d,C=1,q=2"):format(img_id, cols, rows))
end

local function delete_image(img_id)
    pcall(send_apc, ("a=d,d=I,i=%d,q=2"):format(img_id))
end

local function render_placeholders(buf, win)
    if not (api.nvim_buf_is_valid(buf) and api.nvim_win_is_valid(win)) then
        return
    end
    local st = buffer_state[buf]
    if not st then
        return
    end

    local cols = api.nvim_win_get_width(win)
    local rows = api.nvim_win_get_height(win)
    if cols < 1 or rows < 1 then
        return
    end

    local rows_with_img = math.min(rows, 256)
    if st.last_cols == cols and st.last_rows == rows then
        return
    end
    st.last_cols, st.last_rows = cols, rows

    create_virtual_placement(st.img_id, cols, rows_with_img)

    api.nvim_set_option_value("modifiable", true, { buf = buf })

    local lines = {}
    for r = 0, rows - 1 do
        if r < rows_with_img then
            if cols == 1 then
                lines[r + 1] = PLACEHOLDER .. diac(r)
            else
                lines[r + 1] = (PLACEHOLDER .. diac(r)) .. string.rep(PLACEHOLDER, cols - 1)
            end
        else
            lines[r + 1] = string.rep(" ", cols)
        end
    end

    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)

    local hl = ensure_placeholder_hl(st.img_id, st.truecolor)
    for r = 0, rows_with_img - 1 do
        api.nvim_buf_add_highlight(buf, NS, hl, r, 0, -1)
    end

    api.nvim_set_option_value("modifiable", false, { buf = buf })
end

local function create_placeholder_buffer(data)
    if type(data) ~= "string" or data == "" then
        error("image data missing")
    end

    local truecolor = vim.o.termguicolors
    local img_id = truecolor and gen_id(0xFFFFFF) or gen_id(255)

    upload_image_data(img_id, data)

    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.b[buf].pyrepl_image_placeholders = true

    buffer_state[buf] = {
        img_id = img_id,
        data_len = #data,
        truecolor = truecolor,
        last_cols = nil,
        last_rows = nil,
    }

    api.nvim_create_autocmd("BufWipeout", {
        group = AUGROUP,
        buffer = buf,
        once = true,
        callback = function()
            local st = buffer_state[buf]
            buffer_state[buf] = nil
            if st then
                delete_image(st.img_id)
            end
        end,
    })

    return buf
end

function M.create_handle(data)
    local buf = create_placeholder_buffer(data)
    local st = buffer_state[buf]
    local handle = {
        buf = buf,
        win = nil,
        id = st and st.img_id or nil,
    }

    function handle.attach(winid)
        if not api.nvim_win_is_valid(winid) then
            error("invalid win id: " .. tostring(winid))
        end
        api.nvim_win_set_buf(winid, buf)
        configure_placeholder_window(winid)
        render_placeholders(buf, winid)
        handle.win = winid
    end

    function handle.redraw()
        if handle.win and api.nvim_win_is_valid(handle.win) and api.nvim_buf_is_valid(buf) then
            configure_placeholder_window(handle.win)
            render_placeholders(buf, handle.win)
        end
    end

    function handle.wipe()
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_delete(buf, { force = true })
        end
    end

    return handle
end

return M
