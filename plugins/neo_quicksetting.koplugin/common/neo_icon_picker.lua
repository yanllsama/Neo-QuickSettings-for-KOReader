
local function showIconPickerDialog(plugin_root, icons_list, current_icon, on_select)
    local _          = require("neo_i18n").gettext
    local Screen     = require("device").screen
    local Geom       = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local Font       = require("ui/font")
    local Size       = require("ui/size")
    local UIManager  = require("ui/uimanager")
    local IC         = require("ui/widget/container/inputcontainer")
    local CC         = require("ui/widget/container/centercontainer")
    local FC         = require("ui/widget/container/framecontainer")
    local VG         = require("ui/widget/verticalgroup")
    local HG         = require("ui/widget/horizontalgroup")
    local VS         = require("ui/widget/verticalspan")
    local IW         = require("ui/widget/iconwidget")
    local TW         = require("ui/widget/textwidget")
    local pager      = require("common/neo_pager")
    local logger     = require("logger")

    local sw, sh   = Screen:getWidth(), Screen:getHeight()
    local icon_sz  = Screen:scaleBySize(48)
    local label_h  = Screen:scaleBySize(20)
    local cell_pad = Screen:scaleBySize(6)
    local pad      = Size.padding.default
    local brd      = Screen:scaleBySize(3) -- slightly thinner modern border
    local span     = Size.span.vertical_default

    local bar_area_h = pager.PN_FOOTER_H + Screen:scaleBySize(16)

    local close_sz  = Screen:scaleBySize(24)
    local close_gap = Screen:scaleBySize(6)
    local close_iw  = IW:new{ icon = "close",    width = close_sz, height = close_sz }
    local back_sz   = Screen:scaleBySize(40)
    local back_iw   = IW:new{ icon = "back.top", width = back_sz, height = back_sz }

    local frame_w   = math.floor(sw * 0.95) -- Wider frame for modern look
    local content_w = frame_w - 2*pad - 2*brd
    local cols      = 5
    local cell_w    = math.floor(content_w / cols)
    local cell_h    = icon_sz + (label_h * 2) + cell_pad * 2 + Screen:scaleBySize(8) -- accommodate 2 text lines

    local title_text_w = content_w - (close_sz * 2) - (close_gap * 2)
    local title_tw = TW:new{
        text  = _("Select icon"),
        face  = Font:getFace("smallinfofont"),
        width = title_text_w,
    }
    local title_text_h = title_tw:getSize().h
    local title_h      = math.max(close_sz, title_text_h, back_sz) + Screen:scaleBySize(24)

    -- Toolbar row: filter + status
    local toolbar_h = Screen:scaleBySize(44)

    local overhead      = 2*pad + 2*brd + title_h + span + toolbar_h + span + span + bar_area_h
    local max_grid_h    = math.max(cell_h, sh - overhead - Screen:scaleBySize(40))
    local rows_per_page = math.min(6, math.max(1, math.floor(max_grid_h / cell_h)))
    local grid_h        = rows_per_page * cell_h
    local per_page      = cols * rows_per_page

    -- Layout positions
    local frame_h = 2*pad + 2*brd + title_h + span + toolbar_h + span + grid_h + span + bar_area_h
    local frame_x = math.floor((sw - frame_w) / 2)
    local frame_y = math.max(0, math.floor((sh - frame_h) / 2))

    local content_x  = frame_x + brd + pad
    local content_y  = frame_y + brd + pad
    local toolbar_y  = content_y + title_h + span
    local grid_y     = toolbar_y + toolbar_h + span
    local bar_y      = grid_y + grid_h + span

    -- Build tree from icons_list
    local root_node = { dirs = {}, files = {}, path = _("Icons") }
    for _, item in ipairs(icons_list) do
        local parts = {}
        for part in item.name:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        local curr = root_node
        local current_path = ""
        for i = 1, #parts - 1 do
            local d = parts[i]
            current_path = current_path == "" and d or (current_path .. "/" .. d)
            if not curr.dirs[d] then
                curr.dirs[d] = { dirs = {}, files = {}, path = current_path }
            end
            curr = curr.dirs[d]
        end
        table.insert(curr.files, item)
    end

    local state = {
        current_node = root_node,
        history_stack = {},
        cur_page = 1,
        total_pages = 1,
        page_vgs = {},
        current_items = {},
        active_filter = "",   -- local name filter
        search_status = "",   -- e.g. "36 results | load more"
        search_offset = 0,    -- for load-more
        last_query = "",
        last_prefixes = "",
        can_load_more = false,
    }
    local SEARCH_LIMIT   = 30

    

    local ui = {}
    ui.search_tw = TW:new{ text = _("Search Online"), face = Font:getFace("smallinfofont") }
    ui.filter_tw = TW:new{ text = _("Filter"), face = Font:getFace("smallinfofont") }
    ui.clear_tw = TW:new{ text = _("Clear"), face = Font:getFace("smallinfofont") }

    local isz = math.floor(Screen:scaleBySize(20))
    ui.first_btn_tw = IW:new{ file = plugin_root .. "/icons/d-arrow-left.svg", width = isz, height = isz, alpha = true }
    ui.prev_btn_tw = IW:new{ file = plugin_root .. "/icons/tab_left_new.svg", width = isz, height = isz, alpha = true }
    ui.next_btn_tw = IW:new{ file = plugin_root .. "/icons/tab_right_new.svg", width = isz, height = isz, alpha = true }
    ui.last_btn_tw = IW:new{ file = plugin_root .. "/icons/d-arrow-right.svg", width = isz, height = isz, alpha = true }

    local rebuildGrid
    local function clearSearchAndFilter()
        state.active_filter = ""
        local lfs = require("libs/libkoreader-lfs")
        local dest_dir = plugin_root .. "/icons/.temp_search/"
        if lfs.attributes(dest_dir, "mode") == "directory" then
            for file in lfs.dir(dest_dir) do
                if file ~= "." and file ~= ".." then
                    os.remove(dest_dir .. file)
                end
            end
            lfs.rmdir(dest_dir)
        end
        root_node.dirs["Search Results"] = nil
        state.can_load_more = false
        state.search_status = ""
        state.cur_page = 1
        rebuildGrid()
    end

    -- ── apply local filter to a files list ─────────────────────────────────
    local function applyFilter(files)
        if state.active_filter == "" then return files end
        local q = state.active_filter:lower()
        local out = {}
        for _, f in ipairs(files) do
            local base = (f.name:match("([^/]+)$") or f.name):lower()
            if base:find(q, 1, true) then
                table.insert(out, f)
            end
        end
        return out
    end

    -- ── rebuild grid ────────────────────────────────────────────────────────
    function rebuildGrid()
        state.current_items = {}

        if state.current_node == root_node then
            if state.can_load_more and state.current_node == root_node.dirs["Search Results"] then
                -- handled below
            end
        end

        local dnames = {}
        for k in pairs(state.current_node.dirs) do table.insert(dnames, k) end
        table.sort(dnames)
        for _, d in ipairs(dnames) do
            table.insert(state.current_items, { is_dir = true, name = d, node = state.current_node.dirs[d] })
        end

        -- apply filter to local files
        local files = applyFilter(state.current_node.files)
        for _, f in ipairs(files) do
            table.insert(state.current_items, { is_dir = false, item = f })
        end

        -- Load More button inside Search Results
        if state.current_node.name == "Search Results" and state.can_load_more then
            table.insert(state.current_items, { is_load_more = true, name = _("⬇  Load More") })
        end

        state.total_pages = math.max(1, math.ceil(math.max(#state.current_items, 1) / per_page))
        if state.cur_page > state.total_pages then state.cur_page = state.total_pages end
        if state.cur_page < 1 then state.cur_page = 1 end

        -- Pre-compute constants used inside the cell loop (avoid repeated scaleBySize + font lookups)
        local _cell_margin  = Screen:scaleBySize(4)
        local _cell_brd_sel = Screen:scaleBySize(2)
        local _radius_cell  = Screen:scaleBySize(8)
        local _face_xs      = Font:getFace("x_smallinfofont")
        local _max_tw       = cell_w - cell_pad * 2
        local _cell_inner_w = cell_w - _cell_margin - cell_pad*2 - 2  -- brd=1 for normal
        local _cell_inner_h = cell_h - _cell_margin - cell_pad*2 - 2
        local _cell_inner_w_sel = cell_w - _cell_margin - cell_pad*2 - 2*_cell_brd_sel
        local _cell_inner_h_sel = cell_h - _cell_margin - cell_pad*2 - 2*_cell_brd_sel

        -- Cache the custom folder icon path (only computed once per rebuildGrid call)
        local _custom_icon_path
        do
            local ok_u, utils2 = pcall(require, "common/utils")
            _custom_icon_path = ok_u and utils2 and utils2.resolveIcon(plugin_root .. "/icons/", "custom") or nil
        end

        -- Cache web.svg existence check (only computed once per rebuildGrid call)
        local _web_icon_path
        do
            local lfs2 = require("libs/libkoreader-lfs")
            local p = plugin_root .. "/icons/web.svg"
            _web_icon_path = (lfs2.attributes(p, "mode") == "file") and p or nil
        end

        if state.page_vgs then
            for _, pv in pairs(state.page_vgs) do pv:free() end
        end
        state.page_vgs = {}

        for p = 1, state.total_pages do
            local pv      = VG:new{ align = "left" }
            local start_i = (p - 1) * per_page + 1
            local row_g
            for offset = 0, per_page - 1 do
                local i = start_i + offset
                if i > #state.current_items then break end
                if offset % cols == 0 then
                    row_g = HG:new{ align = "top" }
                    table.insert(pv, row_g)
                end

                local cell   = state.current_items[i]
                local is_dir = cell.is_dir
                local is_sel = cell.item and (current_icon == cell.item.name)
                local short, icon_w, sub_label

                if cell.is_search or cell.is_filter or cell.is_clear_temp or cell.is_load_more then
                    short  = cell.name
                    local ico = cell.is_search     and "search"
                             or cell.is_filter     and "resources"
                             or cell.is_load_more  and "refresh"
                             or "close"
                    if cell.is_search and _web_icon_path then
                        icon_w = IW:new{ file = _web_icon_path, width = icon_sz, height = icon_sz, alpha = true }
                    end
                    if not icon_w then
                        icon_w = IW:new{ icon = ico, width = icon_sz, height = icon_sz, alpha = true }
                    end
                elseif is_dir then
                    short  = cell.name
                    local cnt = #cell.node.files
                    for _ in pairs(cell.node.dirs) do cnt = cnt + 1 end
                    sub_label = "(" .. cnt .. ")"
                    icon_w = IW:new{
                        file   = _custom_icon_path or nil,
                        icon   = _custom_icon_path and nil or "custom",
                        width  = icon_sz, height = icon_sz, alpha = true,
                    }
                else
                    local name = cell.item.name
                    local base = name:match("([^/]+)$") or name
                    base = base:gsub("^quick_",""):gsub("^tab_",""):gsub("^lookup_","")
                    local set_prefix = name:match("%.temp_search/([^_]+)_")
                    short     = base
                    sub_label = set_prefix and ("[" .. set_prefix .. "]") or nil
                    icon_w = IW:new{
                        file   = cell.item.file or nil,
                        icon   = cell.item.file and nil or name,
                        width  = icon_sz, height = icon_sz, alpha = true,
                    }
                end

                local cell_brd = is_sel and _cell_brd_sel or 1
                local cell_bg  = is_sel and Blitbuffer.COLOR_LIGHT_GRAY
                             or is_dir  and Blitbuffer.COLOR_GRAY_E
                             or           Blitbuffer.COLOR_WHITE

                local inner = VG:new{ align = "center", icon_w }
                table.insert(inner, TW:new{
                    text      = short or "",
                    face      = _face_xs,
                    max_width = _max_tw,
                })
                if sub_label then
                    table.insert(inner, TW:new{
                        text      = sub_label,
                        face      = _face_xs,
                        max_width = _max_tw,
                        fgcolor   = Blitbuffer.COLOR_DARK_GRAY,
                    })
                end

                local iw = is_sel and _cell_inner_w_sel or _cell_inner_w
                local ih = is_sel and _cell_inner_h_sel or _cell_inner_h
                table.insert(row_g, CC:new{
                    dimen = Geom:new{ w = cell_w, h = cell_h },
                    FC:new{
                        width      = cell_w - _cell_margin,
                        height     = cell_h - _cell_margin,
                        bordersize = cell_brd,
                        radius     = _radius_cell,
                        color      = Blitbuffer.COLOR_BLACK,
                        background = cell_bg,
                        padding    = cell_pad,
                        CC:new{
                            dimen = Geom:new{ w = iw, h = ih },
                            inner,
                        },
                    }
                })
            end
            state.page_vgs[p] = pv
        end

        title_tw:setText(state.current_node.path or _("Icons"))
    end

    rebuildGrid()

    local inner_frame = FC:new{
        width      = frame_w,
        height     = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius     = Size.radius.window,
        padding    = pad,
        VS:new{ height = 0 },
    }

    local dialog

    local function paintBar(bb)
        if state.total_pages <= 1 then return end
        local bw = math.floor(content_w / 5)
        -- Pre-compute sizes once per paint call
        local btn_h   = ui.first_btn_tw:getSize().h
        local btn1_w  = ui.first_btn_tw:getSize().w
        local btn2_w  = ui.prev_btn_tw:getSize().w
        local btn3_w  = ui.next_btn_tw:getSize().w
        local btn4_w  = ui.last_btn_tw:getSize().w
        local cy = bar_y + math.floor((bar_area_h - btn_h) / 2)
        ui.first_btn_tw:paintTo(bb, content_x + math.floor((bw - btn1_w) / 2), cy)
        ui.prev_btn_tw:paintTo(bb,  content_x + bw + math.floor((bw - btn2_w) / 2), cy)

        local page_str = _("Page") .. " " .. state.cur_page .. "/" .. state.total_pages
        local page_tw = TW:new{ text = page_str, face = Font:getFace("smallinfofont") }
        local ptw_sz  = page_tw:getSize()
        local pcy = bar_y + math.floor((bar_area_h - ptw_sz.h) / 2)
        page_tw:paintTo(bb, content_x + 2*bw + math.floor((bw - ptw_sz.w) / 2), pcy)

        ui.next_btn_tw:paintTo(bb, content_x + 3*bw + math.floor((bw - btn3_w) / 2), cy)
        ui.last_btn_tw:paintTo(bb, content_x + 4*bw + math.floor((bw - btn4_w) / 2), cy)

        for i=1, 4 do
            local lx = content_x + i*bw
            bb:paintRect(lx, bar_y + 4, 1, bar_area_h - 8, Blitbuffer.COLOR_LIGHT_GRAY)
        end
    end

    local function goToPage(p)
        if p < 1 or p > state.total_pages then return end
        state.cur_page = p
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end

    local function goBack()
        if #state.history_stack > 0 then
            state.current_node = table.remove(state.history_stack)
            state.cur_page = 1
            rebuildGrid()
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
        end
    end

    local function promptSaveDestination(item)
        local InputDialog = require("ui/widget/inputdialog")
        local InfoMessage = require("ui/widget/infomessage")
        local lfs = require("libs/libkoreader-lfs")

        local dest_dlg
        local default_name = item.file:match("([^/]+)$"):gsub("%.svg$", "")
        dest_dlg = InputDialog:new{
            title       = _("Icon Name (No extension):"),
            input_hint  = _("Ex: my_icon_name"),
            input       = default_name,
            buttons = {{
                { text = _("Cancel"), callback = function() UIManager:close(dest_dlg) end },
                {
                    text = _("Save"),
                    is_enter = true,
                    callback = function()
                        local icon_name = dest_dlg:getInputValue()
                        UIManager:close(dest_dlg)
                        if not icon_name or icon_name == "" then return end
                        icon_name = icon_name:gsub("[^%w_%-]", "")
                        if icon_name == "" then icon_name = default_name end

                        local target_dir = plugin_root .. "/icons/"
                        local new_path = target_dir .. icon_name .. ".svg"
                        os.rename(item.file, new_path)
                        -- The user requested NOT to apply the icon, just save it.
                        -- So we don't call on_select(icon_name)
                        -- We just close the input dialog, but we DON'T close the picker dialog
                        -- UIManager:close(dialog) -- Keep picker open
                        UIManager:show(InfoMessage:new{ text = _("Icon saved."), timeout = 2 })
                        
                        -- Reload the grid so the saved icon shows up in the parent folder,
                        -- but wait, if we are in Search Results, rebuilding grid would take us out?
                        -- If we don't rebuild, it's just saved in the background.
                    end,
                },
            }},
        }
        UIManager:show(dest_dlg)
        dest_dlg:onShowKeyboard()
    end

    -- ── download icons from Iconify API ─────────────────────────────────────
    local function urlencode(str)
        if str then
            str = str:gsub("\n", "\r\n")
            str = str:gsub("([^%w %-%_%.%~])", function(c)
                return string.format("%%%02X", string.byte(c))
            end)
            str = str:gsub(" ", "%%20")
        end
        return str
    end

    local function doDownload(query, prefixes, offset, append)
        local InfoMessage = require("ui/widget/infomessage")
        local lfs = require("libs/libkoreader-lfs")

        local msg = InfoMessage:new{ text = _("Searching icons… Please wait.") }
        UIManager:show(msg)
        UIManager:forceRePaint()

        UIManager:scheduleIn(0.1, function()
            local ok_http, http = pcall(require, "socket.http")
            if not ok_http then
                UIManager:close(msg)
                UIManager:show(InfoMessage:new{ text = _("HTTP library not found."), timeout = 3 })
                return
            end

            local ltn12      = require("ltn12")
            local json       = require("json")
            local socketutil = require("socketutil")

            local resp = {}
            socketutil:set_timeout(8, 15)
            local q_escaped = urlencode(query)
            local api_url   = "https://api.iconify.design/search?query=" .. q_escaped
                           .. "&limit=" .. SEARCH_LIMIT
                           .. "&start=" .. offset
            if prefixes and prefixes ~= "" then
                api_url = api_url .. "&prefixes=" .. prefixes
            end

            local _dummy, code = http.request{ url = api_url, sink = ltn12.sink.table(resp) }
            socketutil:reset_timeout()

            if code ~= 200 then
                UIManager:close(msg)
                UIManager:show(InfoMessage:new{
                    text    = _("Connection error. Code: ") .. tostring(code),
                    timeout = 3,
                })
                return
            end

            local ok_j, data = pcall(json.decode, table.concat(resp))
            if not ok_j or not data or not data.icons or #data.icons == 0 then
                UIManager:close(msg)
                UIManager:show(InfoMessage:new{ text = _("No icons found for that query."), timeout = 3 })
                return
            end

            local dest_dir = plugin_root .. "/icons/.temp_search/"
            if not append then
                -- clear old results
                if lfs.attributes(dest_dir, "mode") == "directory" then
                    for file in lfs.dir(dest_dir) do
                        if file ~= "." and file ~= ".." then os.remove(dest_dir .. file) end
                    end
                else
                    lfs.mkdir(dest_dir)
                end
            else
                if lfs.attributes(dest_dir, "mode") ~= "directory" then
                    lfs.mkdir(dest_dir)
                end
            end

            local temp_node = root_node.dirs["Search Results"]
            if not temp_node or not append then
                temp_node = {
                    name  = "Search Results",
                    path  = "Search Results",
                    files = {},
                    dirs  = {},
                }
                root_node.dirs["Search Results"] = temp_node
            end

            local downloaded = 0
            local total      = #data.icons

            for _, icon_id in ipairs(data.icons) do
                local prefix, name = icon_id:match("([^:]+):([^:]+)")
                if prefix and name then
                    local svg_url  = "https://api.iconify.design/" .. prefix .. "/" .. name .. ".svg"
                    local svg_path = dest_dir .. prefix .. "_" .. name .. ".svg"

                    local already = false
                    for _, ef in ipairs(temp_node.files) do
                        if ef.file == svg_path then already = true; break end
                    end

                    if not already then
                        if lfs.attributes(svg_path, "mode") ~= "file" then
                            local f = io.open(svg_path, "w")
                            if f then
                                socketutil:set_timeout(5, 8)
                                local _dummy2, c2 = http.request{
                                    url  = svg_url,
                                    sink = ltn12.sink.file(f),
                                }
                                pcall(function() f:close() end)
                                socketutil:reset_timeout()
                                if c2 == 200 then
                                    table.insert(temp_node.files, {
                                        name = ".temp_search/" .. prefix .. "_" .. name,
                                        file = svg_path,
                                    })
                                    downloaded = downloaded + 1
                                else
                                    os.remove(svg_path)
                                    logger.warn("neo_icon_picker: download failed", c2, svg_url)
                                end
                            end
                        else
                            table.insert(temp_node.files, {
                                name = ".temp_search/" .. prefix .. "_" .. name,
                                file = svg_path,
                            })
                            downloaded = downloaded + 1
                        end
                    end
                end
            end

            UIManager:close(msg)

            -- determine if there are likely more results
            local api_total = data.total or 0
            state.search_offset  = offset + total
            state.can_load_more  = (state.search_offset < api_total) and (state.search_offset <= 999 - SEARCH_LIMIT)
            state.last_query     = query
            state.last_prefixes  = prefixes

            local loaded_total = #temp_node.files
            state.search_status = string.format(_("%d icons loaded"), loaded_total)
                         .. (state.can_load_more and _(" · Tap ⬇ for more") or "")

            if downloaded > 0 or append then
                UIManager:show(InfoMessage:new{
                    text    = string.format(_("%d new icons downloaded!"), downloaded),
                    timeout = 2,
                })
            else
                UIManager:show(InfoMessage:new{
                    text    = _("Icons already cached."),
                    timeout = 2,
                })
            end

            if not append then
                table.insert(state.history_stack, state.current_node)
                state.current_node = temp_node
            else
                state.current_node = temp_node
            end
            state.cur_page = 1
            rebuildGrid()
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
        end)
    end

    -- ── source selection → query → download ─────────────────────────────────
    local function triggerSearch()
        local Menu        = require("ui/widget/menu")
        local InputDialog = require("ui/widget/inputdialog")
        local NetworkMgr  = require("ui/network/manager")

        local choices = {
            { text = _("⭐  Best Mix (Recommended)"),        id = "mdi,ph,tabler,lucide,material-symbols" },
            { text = _("🔤  Material Symbols (Google)"),      id = "material-symbols" },
            { text = _("🔤  Material Symbols Sharp"),         id = "material-symbols-sharp" },
            { text = _("🎨  Material Design Icons"),          id = "mdi" },
            { text = _("💎  Phosphor Icons"),                 id = "ph" },
            { text = _("📐  Tabler Icons"),                   id = "tabler" },
            { text = _("🔷  Lucide Icons"),                   id = "lucide" },
            { text = _("⚡  Heroicons"),                      id = "heroicons" },
            { text = _("🔴  Font Awesome Solid"),             id = "fa6-solid" },
            { text = _("🪟  Fluent UI (Microsoft)"),          id = "fluent" },
            { text = _("📦  Boxicons Solid"),                 id = "bxs" },
            { text = _("🌑  Dark / Solid Mix"),               id = "bxs,fa6-solid,heroicons-solid,zondicons" },
            { text = _("🌐  All Sources"),                    id = "" },
        }

        local choice_dlg
        choice_dlg = Menu:new{
            title          = _("Choose Icon Source"),
            item_table     = choices,
            width          = math.floor(sw * 0.82),
            height         = math.floor(sh * 0.80),
            items_per_page = 13,
            onMenuChoice   = function(_menu_inst, item)
                UIManager:close(choice_dlg)
                local prefixes = item.id
                local input_dlg
                input_dlg = InputDialog:new{
                    title      = _("Search icons (English keyword)"),
                    input_hint = "book, wifi, moon, heart, settings…",
                    buttons = {{
                        { text = _("Cancel"), callback = function() UIManager:close(input_dlg) end },
                        {
                            text     = _("Search"),
                            is_enter = true,
                            callback = function()
                                local query = input_dlg:getInputValue()
                                UIManager:close(input_dlg)
                                if not query or query == "" then return end
                                NetworkMgr:runWhenOnline(function()
                                    doDownload(query, prefixes, 0, false)
                                end)
                            end,
                        },
                    }},
                }
                UIManager:show(input_dlg)
                input_dlg:onShowKeyboard()
            end,
        }
        if choice_dlg[1] then choice_dlg[1].radius = Size.radius.window end
        local x = math.floor((sw - choice_dlg.dimen.w) / 2)
        local y = math.floor((sh - choice_dlg.dimen.h) / 2)
        UIManager:show(choice_dlg, nil, nil, x, y)
    end

    -- ── local filter ─────────────────────────────────────────────────────────
    local function triggerFilter()
        local InputDialog = require("ui/widget/inputdialog")
        local filter_dlg
        filter_dlg = InputDialog:new{
            title      = _("Filter icons by name"),
            input_hint = _("Type to filter…"),
            input      = state.active_filter,
            buttons = {{
                {
                    text     = _("Clear"),
                    callback = function()
                        state.active_filter = ""
                        UIManager:close(filter_dlg)
                        state.cur_page = 1
                        rebuildGrid()
                        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                    end,
                },
                {
                    text     = _("Apply"),
                    is_enter = true,
                    callback = function()
                        state.active_filter = filter_dlg:getInputValue() or ""
                        UIManager:close(filter_dlg)
                        state.cur_page = 1
                        rebuildGrid()
                        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                    end,
                },
            }},
        }
        UIManager:show(filter_dlg)
        filter_dlg:onShowKeyboard()
    end

    -- ── delete a local icon file with confirmation ────────────────────────────
    local function deleteIconCell(cell)
        local ConfirmBox = require("ui/widget/confirmbox")
        local lfs        = require("libs/libkoreader-lfs")
        local item       = cell.item
        -- Safety: only delete files that live inside plugin_root/icons/
        if not item.file then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("Built-in icons cannot be deleted."), timeout = 2 })
            return
        end
        local icons_root = plugin_root .. "/icons/"
        if item.file:sub(1, #icons_root) ~= icons_root then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("Built-in icons cannot be deleted."), timeout = 2 })
            return
        end
        local short_name = item.file:match("([^/]+)$") or item.file
        local confirm
        confirm = ConfirmBox:new{
            text    = _("Delete icon?") .. "\n" .. short_name,
            ok_text = _("Delete"),
            ok_callback = function()
                os.remove(item.file)
                -- Remove from current node's files list
                for i, f in ipairs(state.current_node.files) do
                    if f == item then
                        table.remove(state.current_node.files, i)
                        break
                    end
                end
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = _("Icon deleted."), timeout = 2 })
                state.cur_page = math.min(state.cur_page, math.max(1, math.ceil((#state.current_node.files) / per_page)))
                rebuildGrid()
                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            end,
        }
        UIManager:show(confirm)
    end

    -- ── PickerDlg widget ─────────────────────────────────────────────────────
    local PickerDlg = IC:extend{}

    function PickerDlg:init()
        self:_init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id          = "picker_tap",
                ges         = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(dialog)
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y

                    -- Back button
                    if #state.history_stack > 0 then
                        if gx >= content_x and gx < content_x + close_sz
                           and gy >= content_y and gy < content_y + title_h then
                            goBack()
                            return true
                        end
                    end

                    -- Close button
                    local close_x = content_x + content_w - close_sz
                    if gx >= close_x and gx < close_x + close_sz
                       and gy >= content_y and gy < content_y + title_h then
                        UIManager:close(dialog)
                        return true
                    end

                    -- Toolbar (Search / Filter / Clear)
                    if gy >= toolbar_y and gy < toolbar_y + toolbar_h then
                        if gx < content_x + content_w / 3 then
                            triggerSearch()
                        elseif gx < content_x + 2 * content_w / 3 then
                            triggerFilter()
                        else
                            clearSearchAndFilter()
                            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                        end
                        return true
                    end

                    -- Pager bar
                    if gy >= bar_y and gy < bar_y + bar_area_h then
                        if gx < content_x + content_w / 5 then
                            goToPage(1)
                        elseif gx < content_x + 2 * content_w / 5 then
                            goToPage(state.cur_page - 1)
                        elseif gx >= content_x + 3 * content_w / 5 and gx < content_x + 4 * content_w / 5 then
                            goToPage(state.cur_page + 1)
                        elseif gx >= content_x + 4 * content_w / 5 then
                            goToPage(state.total_pages)
                        end
                        return true
                    end

                    -- Grid
                    local grid_geom = Geom:new{
                        x = content_x, y = grid_y,
                        w = cols * cell_w, h = rows_per_page * cell_h,
                    }
                    if ges.pos:intersectWith(grid_geom) then
                        local col_i = math.floor((gx - content_x) / cell_w)
                        local row_i = math.floor((gy - grid_y) / cell_h)
                        local idx   = (state.cur_page - 1) * per_page + row_i * cols + col_i + 1
                        if idx >= 1 and idx <= #state.current_items then
                            local cell = state.current_items[idx]
                            if cell.is_load_more then
                                local NetworkMgr = require("ui/network/manager")
                                NetworkMgr:runWhenOnline(function()
                                    doDownload(state.last_query, state.last_prefixes, state.search_offset, true)
                                end)
                            elseif cell.is_dir then
                                table.insert(state.history_stack, state.current_node)
                                state.current_node = cell.node
                                state.cur_page = 1
                                rebuildGrid()
                                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                            else
                                -- file selected
                                if state.current_node.name == "Search Results" then
                                    promptSaveDestination(cell.item)
                                else
                                    UIManager:close(dialog)
                                    on_select(cell.item.name)
                                end
                            end
                        end
                    end
                    return true
                end,
            },
            {
                id          = "picker_swipe",
                ges         = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local dir = ges.direction
                    if dir == "west"  then goToPage(state.cur_page + 1)
                    elseif dir == "east" then goToPage(state.cur_page - 1)
                    else UIManager:close(dialog)
                    end
                    return true
                end,
            },
        })
    end

    -- ── hold on grid cell → delete ────────────────────────────────────────────
    -- We add this AFTER init so it can reference `dialog` once assigned.


    local function rmdir_recursive(path)
        local lfs = require("libs/libkoreader-lfs")
        for file in lfs.dir(path) do
            if file ~= "." and file ~= ".." then
                local f = path .. "/" .. file
                if lfs.attributes(f, "mode") == "directory" then
                    rmdir_recursive(f)
                else
                    os.remove(f)
                end
            end
        end
        lfs.rmdir(path)
    end

    local function deleteDirCell(cell)
        local ConfirmBox = require("ui/widget/confirmbox")
        local lfs        = require("libs/libkoreader-lfs")
        
        local target_dir = plugin_root .. "/icons/" .. cell.name .. "/"
        if lfs.attributes(target_dir, "mode") ~= "directory" then return end
        
        local confirm = ConfirmBox:new{
            text    = _("Delete folder and ALL icons inside?\n") .. cell.name,
            ok_text = _("Delete"),
            ok_callback = function()
                rmdir_recursive(target_dir)
                root_node.dirs[cell.name] = nil
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = _("Folder deleted."), timeout = 2 })
                state.cur_page = 1
                rebuildGrid()
                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            end,
        }
        UIManager:show(confirm)
    end

    
    local function handleLongPress(cell)
        local lfs = require("libs/libkoreader-lfs")
        local Menu = require("ui/widget/menu")
        local InfoMessage = require("ui/widget/infomessage")
        
        local is_dir = cell.is_dir
        local item = cell.item
        local target_path = ""
        local icons_root = plugin_root .. "/icons/"
        local short_name = ""
        
        if is_dir then
            target_path = icons_root .. cell.name
            short_name = cell.name
            -- Ensure it's not a built-in thing if it's somehow outside
            if target_path:sub(1, #icons_root) ~= icons_root then return end
        else
            if not item or not item.file then return end
            target_path = item.file
            short_name = item.file:match("([^/]+)$") or item.file
            if target_path:sub(1, #icons_root) ~= icons_root then
                UIManager:show(InfoMessage:new{ text = _("Built-in icons cannot be modified."), timeout = 2 })
                return
            end
        end
        
        local dir, file = target_path:match("^(.*)/([^/]+)/?$")
        if not dir or not file then return end
        local lock_file = dir .. "/." .. file .. ".lock"
        
        local is_locked = lfs.attributes(lock_file, "mode") == "file"
        
        local ConfirmBox = require("ui/widget/confirmbox")
        local action_dlg
        if is_locked then
            action_dlg = ConfirmBox:new{
                text = short_name .. "\\n" .. _("This item is locked."),
                ok_text = _("Unlock"),
                ok_callback = function()
                    os.remove(lock_file)
                    UIManager:show(InfoMessage:new{ text = _("Unlocked"), timeout = 2 })
                end,
            }
        else
            action_dlg = ConfirmBox:new{
                text = short_name,
                ok_text = _("Delete"),
                ok_callback = function()
                    if is_dir then
                        deleteDirCell(cell)
                    else
                        deleteIconCell(cell)
                    end
                end,
                other_buttons = {{
                    {
                        text = _("Lock"),
                        callback = function()
                            UIManager:close(action_dlg)
                            local f = io.open(lock_file, "w")
                            if f then f:close() end
                            UIManager:show(InfoMessage:new{ text = _("Locked"), timeout = 2 })
                        end
                    }
                }},
                other_buttons_first = true,
            }
        end
        UIManager:show(action_dlg)
    end

    local function registerHold(dlg)
        dlg:registerTouchZones({
            {
                id          = "picker_hold",
                ges         = "hold",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides   = { "picker_tap", "picker_swipe" },
                handler     = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then return false end
                    local gx, gy = ges.pos.x, ges.pos.y
                    local grid_geom = Geom:new{
                        x = content_x, y = grid_y,
                        w = cols * cell_w, h = rows_per_page * cell_h,
                    }
                    if ges.pos:intersectWith(grid_geom) then
                        local col_i = math.floor((gx - content_x) / cell_w)
                        local row_i = math.floor((gy - grid_y) / cell_h)
                        local idx   = (state.cur_page - 1) * per_page + row_i * cols + col_i + 1
                        if idx >= 1 and idx <= #state.current_items then
                            local cell = state.current_items[idx]
                            if cell.is_dir and cell.name ~= "Search Results" then
                                handleLongPress(cell)
                                return true
                            elseif not cell.is_dir and cell.item then
                                handleLongPress(cell)
                                return true
                            end
                        end
                    end
                    return false
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)

        -- Title row
        local title_start_x = content_x
        if #state.history_stack > 0 then
            back_iw:paintTo(bb, title_start_x, content_y + math.floor((title_h - back_sz) / 2))
            title_start_x = title_start_x + back_sz + close_gap
        end
        title_tw:paintTo(bb, title_start_x, content_y + math.floor((title_h - title_text_h) / 2))
        local close_x = content_x + content_w - close_sz
        close_iw:paintTo(bb, close_x, content_y + math.floor((title_h - close_sz) / 2))

        -- Toolbar: divider line
        bb:paintRect(content_x, toolbar_y - 1, content_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)

        -- Toolbar
        local bw = math.floor(content_w / 3)
        local cy = toolbar_y + math.floor((toolbar_h - ui.search_tw:getSize().h) / 2)
        ui.search_tw:paintTo(bb, content_x + math.floor((bw - ui.search_tw:getSize().w)/2), cy)
        ui.filter_tw:paintTo(bb, content_x + bw + math.floor((bw - ui.filter_tw:getSize().w)/2), cy)
        ui.clear_tw:paintTo(bb, content_x + 2*bw + math.floor((bw - ui.clear_tw:getSize().w)/2), cy)
        
        for i=1, 2 do
            local lx = content_x + i*bw
            bb:paintRect(lx, toolbar_y + 4, 1, toolbar_h - 8, Blitbuffer.COLOR_LIGHT_GRAY)
        end

        -- Toolbar divider bottom
        bb:paintRect(content_x, toolbar_y + toolbar_h, content_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)

        -- Grid
        if state.page_vgs[state.cur_page] then
            state.page_vgs[state.cur_page]:paintTo(bb, content_x, grid_y)
        end

        -- Pager
        if state.total_pages > 1 then
            paintBar(bb)
        end
    end

    dialog = PickerDlg:new{}
    registerHold(dialog)
    UIManager:show(dialog, "full")
end

return showIconPickerDialog
