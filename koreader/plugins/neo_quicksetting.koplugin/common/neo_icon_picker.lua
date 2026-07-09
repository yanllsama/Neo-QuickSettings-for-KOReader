
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

    local sw, sh   = Screen:getWidth(), Screen:getHeight()
    local icon_sz  = Screen:scaleBySize(48)
    local label_h  = Screen:scaleBySize(18)
    local cell_pad = Screen:scaleBySize(6)
    local pad      = Size.padding.default
    local brd      = Size.border.window
    local span     = Size.span.vertical_default

    local bar_area_h = pager.PN_FOOTER_H

    local close_sz  = Screen:scaleBySize(24)
    local close_gap = Screen:scaleBySize(6)
    local close_iw  = IW:new{ icon = "close", width = close_sz, height = close_sz }
    local back_iw   = IW:new{ icon = "back.top", width = close_sz, height = close_sz }

    local frame_w   = math.floor(sw * 0.90)
    local content_w = frame_w - 2*pad - 2*brd
    local cols      = math.max(3, math.floor(content_w / Screen:scaleBySize(96)))
    local cell_w    = math.floor(content_w / cols)
    local cell_h    = icon_sz + label_h + cell_pad * 2

    local title_text_w = content_w - (close_sz * 2) - (close_gap * 2)
    local title_tw = TW:new{
        text  = _("Select icon"),
        face  = Font:getFace("smallinfofont"),
        width = title_text_w,
    }
    local title_text_h = title_tw:getSize().h
    local title_h      = math.max(close_sz, title_text_h)

    local overhead      = 2*pad + 2*brd + title_h + span + span + bar_area_h
    local max_grid_h    = math.max(cell_h, sh - overhead - Screen:scaleBySize(40))
    local rows_per_page = math.max(1, math.floor(max_grid_h / cell_h))
    local grid_h        = rows_per_page * cell_h
    local per_page      = cols * rows_per_page

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

    local current_node = root_node
    local history_stack = {}
    
    local cur_page = 1
    local total_pages = 1
    local page_vgs = {}
    local current_items = {}

    local function rebuildGrid()
        current_items = {}
        
        if current_node == root_node then
            table.insert(current_items, { is_search = true, name = _(_("🔍 Search on WEB")) })
            if root_node.dirs["Search Results"] then
                table.insert(current_items, { is_clear_temp = true, name = _("🧹 Clear Search History") })
            end
        end
        
        local dnames = {}
        for k in pairs(current_node.dirs) do table.insert(dnames, k) end
        table.sort(dnames)
        for _, d in ipairs(dnames) do
            table.insert(current_items, { is_dir = true, name = d, node = current_node.dirs[d] })
        end
        
        for _, f in ipairs(current_node.files) do
            table.insert(current_items, { is_dir = false, item = f })
        end
        
        total_pages = math.max(1, math.ceil(math.max(#current_items, 1) / per_page))
        if cur_page > total_pages then cur_page = total_pages end
        if cur_page < 1 then cur_page = 1 end
        
        if page_vgs then
            for _, pv in pairs(page_vgs) do
                pv:free()
            end
        end
        page_vgs = {}
        for p = 1, total_pages do
            local pv      = VG:new{ align = "left" }
            local start_i = (p - 1) * per_page + 1
            local row_g
            for offset = 0, per_page - 1 do
                local i = start_i + offset
                if i > #current_items then break end
                if offset % cols == 0 then
                    row_g = HG:new{ align = "top" }
                    table.insert(pv, row_g)
                end
                
                local cell = current_items[i]
                local is_dir = cell.is_dir
                local is_sel = cell.item and (current_icon == cell.item.name)
                local short
                local icon_w
                
                if is_dir then
                    short = cell.name
                    local custom_icon_path
                    if plugin_root then
                        local utils = require("common/utils")
                        custom_icon_path = utils.resolveIcon(plugin_root .. "/icons/", "custom")
                    end
                    icon_w = IW:new{ file = custom_icon_path or nil, icon = custom_icon_path and nil or "custom", width = icon_sz, height = icon_sz, alpha = true }
                elseif cell.is_search then
                    short = cell.name
                    icon_w = IW:new{ file = plugin_root .. "/icons/web.svg", icon = "search", width = icon_sz, height = icon_sz, alpha = true }
                elseif cell.is_clear_temp then
                    short = cell.name
                    icon_w = IW:new{ icon = "close", width = icon_sz, height = icon_sz, alpha = true }
                else
                    local name = cell.item.name
                    short = name:gsub("^quick_", ""):gsub("^tab_", ""):gsub("^lookup_", ""):match("([^/]+)$") or name
                    icon_w = IW:new{ file = cell.item.file or nil, icon = cell.item.file and nil or name, width = icon_sz, height = icon_sz, alpha = true }
                end
                
                local cell_brd = is_sel and Screen:scaleBySize(2) or Screen:scaleBySize(1)
                table.insert(row_g, FC:new{
                    width      = cell_w,
                    height     = cell_h,
                    bordersize = cell_brd,
                    color      = is_sel and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
                    background = is_sel and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                    padding    = cell_pad,
                    CC:new{
                        dimen = Geom:new{ w = cell_w - cell_pad*2 - 2*cell_brd, h = cell_h - cell_pad*2 - 2*cell_brd },
                        VG:new{
                            align = "center",
                            icon_w,
                            TW:new{
                                text      = short,
                                face      = Font:getFace("xx_smallinfofont"),
                                max_width = cell_w - cell_pad * 2,
                            },
                        },
                    },
                })
            end
            page_vgs[p] = pv
        end
        
        local t = current_node.path
        title_tw:setText(t)
    end

    rebuildGrid()

    local frame_h = 2*pad + 2*brd + title_h + span + grid_h + span + bar_area_h
    local frame_x = math.floor((sw - frame_w) / 2)
    local frame_y = math.floor((sh - frame_h) / 2)
    if frame_y < 0 then frame_y = 0 end

    local content_x = frame_x + brd + pad
    local content_y = frame_y + brd + pad
    local grid_x    = content_x
    local grid_y    = content_y + title_h + span
    local bar_y     = grid_y + grid_h + span

    local inner_frame = FC:new{
        width      = frame_w,
        height     = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        padding    = pad,
        VS:new{ height = 0 },
    }

    local dialog

    local function paintBar(bb)
        pager.paint(bb, content_x, bar_y, content_w, bar_area_h, cur_page, total_pages)
    end

    local function goToPage(p)
        if p < 1 or p > total_pages then return end
        cur_page = p
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end
    
    local function goBack()
        if #history_stack > 0 then
            current_node = table.remove(history_stack)
            cur_page = 1
            rebuildGrid()
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
        end
    end

    local function promptSaveDestination(item)
        local InputDialog = require("ui/widget/inputdialog")
        local InfoMessage = require("ui/widget/infomessage")
        local lfs = require("libs/libkoreader-lfs")
        
        local dest_dlg
        dest_dlg = InputDialog:new{
            title = _(_("Where to save the icon?")),
            input_hint = _("E.g.: custom, default_ico, or new_folder_name"),
            input = "custom",
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function() UIManager:close(dest_dlg) end,
                    },
                    {
                        text = _("Save"),
                        is_enter = true,
                        callback = function()
                            local folder_name = dest_dlg:getInputValue()
                            UIManager:close(dest_dlg)
                            if not folder_name or folder_name == "" then return end
                            
                            folder_name = folder_name:gsub("[^%w_%-]", "")
                            if folder_name == "" then folder_name = "custom" end
                            
                            local target_dir = plugin_root .. "/icons/" .. folder_name .. "/"
                            if lfs.attributes(target_dir, "mode") ~= "directory" then
                                lfs.mkdir(target_dir)
                            end
                            
                            local filename = item.file:match("([^/]+)$")
                            local new_path = target_dir .. filename
                            os.rename(item.file, new_path)
                            
                            UIManager:close(dialog)
                            on_select(folder_name .. "/" .. filename:gsub("%.svg$", ""))
                            UIManager:show(InfoMessage:new{ text = _(_("Icon saved and applied.")), timeout = 2 })
                        end,
                    },
                },
            },
        }
        UIManager:show(dest_dlg)
        dest_dlg:onShowKeyboard()
    end

    local function triggerSearch()
        local Menu        = require("ui/widget/menu")
        local InputDialog = require("ui/widget/inputdialog")
        local NetworkMgr  = require("ui/network/manager")
        local InfoMessage = require("ui/widget/infomessage")
        local Screen      = require("device").screen
        local Size        = require("ui/size")
        
        local choices = {
            { text = _(_("Best (Mixed)")), id = "mdi,ph,tabler,lucide" },
            { text = _("Dark / Solid (Mixed)"), id = "bxs,fa6-solid,heroicons-solid,zondicons" },
            { text = _("Material Design"), id = "mdi" },
            { text = _("Phosphor"), id = "ph" },
            { text = _("Tabler"), id = "tabler" },
            { text = _("Lucide"), id = "lucide" },
            { text = _("Boxicons Solid"), id = "bxs" },
            { text = _("FontAwesome Solid"), id = "fa6-solid" },
            { text = _("Fluent UI"), id = "fluent" },
            { text = _("All Sources (Legacy)"), id = "" },
        }
        
        local choice_dlg
        choice_dlg = Menu:new{
            title = _("Icon Search Source"),
            item_table = choices,
            width = math.floor(Screen:getWidth() * 0.8),
            height = math.floor(Screen:getHeight() * 0.8),
            items_per_page = 10,
            onMenuChoice = function(menu_instance, item)
                UIManager:close(choice_dlg)
                local prefixes = item.id
                local input_dlg
                input_dlg = InputDialog:new{
                    title = _("Search icon (English word)"),
                    input_hint = "book, wifi, battery...",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                callback = function() UIManager:close(input_dlg) end,
                            },
                            {
                                text = _("Search"),
                                is_enter = true,
                                callback = function()
                                    local query = input_dlg:getInputValue()
                                    UIManager:close(input_dlg)
                                    if not query or query == "" then return end
                                    
                                    NetworkMgr:runWhenOnline(function()
                                        local msg = InfoMessage:new{ text = _("Searching and downloading icons... Please wait.") }
                                        UIManager:show(msg)
                                        UIManager:forceRePaint()
                                        
                                        UIManager:scheduleIn(0.1, function()
                                            local ok_http, http = pcall(require, "socket.http")
                                            if not ok_http then
                                                UIManager:close(msg)
                                                UIManager:show(InfoMessage:new{ text = _("HTTP library not found."), timeout = 2 })
                                                return
                                            end
                                            
                                            local ltn12 = require("ltn12")
                                            local json = require("json")
                                            local socketutil = require("socketutil")
                                            
                                            local resp = {}
                                            socketutil:set_timeout(5, 10)
                                            local q_escaped = string.gsub(query, " ", "+")
                                            local api_url = "https://api.iconify.design/search?query=" .. q_escaped .. "&limit=12"
                                            if prefixes and prefixes ~= "" then
                                                api_url = api_url .. "&prefixes=" .. prefixes
                                            end
                                            local dummy, code = http.request{
                                                url = api_url,
                                                sink = ltn12.sink.table(resp),
                                            }
                                            socketutil:reset_timeout()
                                    
                                    if code == 200 then
                                        local ok_j, data = pcall(json.decode, table.concat(resp))
                                        if ok_j and data and data.icons and #data.icons > 0 then
                                            local downloaded = 0
                                            local lfs = require("libs/libkoreader-lfs")
                                            local dest_dir = plugin_root .. "/icons/.temp_search/"
                                            if lfs.attributes(dest_dir, "mode") == "directory" then
                                                for file in lfs.dir(dest_dir) do
                                                    if file ~= "." and file ~= ".." then
                                                        os.remove(dest_dir .. file)
                                                    end
                                                end
                                            else
                                                lfs.mkdir(dest_dir)
                                            end
                                            
                                            local temp_node = root_node.dirs["Search Results"]
                                            if not temp_node then
                                                temp_node = { name = "Search Results", path = "Search Results", files = {}, dirs = {} }
                                                root_node.dirs["Search Results"] = temp_node
                                            else
                                                temp_node.files = {}
                                            end
                                            
                                            for _, icon_id in ipairs(data.icons) do
                                                local prefix, name = icon_id:match("([^:]+):([^:]+)")
                                                if prefix and name then
                                                    local svg_url = "https://api.iconify.design/" .. prefix .. "/" .. name .. ".svg"
                                                    local svg_path = dest_dir .. prefix .. "_" .. name .. ".svg"
                                                    
                                                    if lfs.attributes(svg_path, "mode") ~= "file" then
                                                        local f = io.open(svg_path, "w")
                                                        if f then
                                                            socketutil:set_timeout(5, 5)
                                                            local dummy, c2 = http.request{
                                                                url = svg_url,
                                                                sink = ltn12.sink.file(f),
                                                            }
                                                            pcall(function() f:close() end)
                                                            socketutil:reset_timeout()
                                                            if c2 ~= 200 then
                                                                os.remove(svg_path)
                                                                logger.warn("neo_quicksettings: iconify download failed. Code/Err:", c2)
                                                                break
                                                            else
                                                                table.insert(temp_node.files, { name = ".temp_search/" .. prefix .. "_" .. name, file = svg_path })
                                                                downloaded = downloaded + 1
                                                            end
                                                        end
                                                    else
                                                        local found = false
                                                        for _, exist_f in ipairs(temp_node.files) do
                                                            if exist_f.file == svg_path then found = true break end
                                                        end
                                                        if not found then
                                                            table.insert(temp_node.files, { name = ".temp_search/" .. prefix .. "_" .. name, file = svg_path })
                                                        end
                                                    end
                                                end
                                            end
                                            
                                            UIManager:close(msg)
                                            if downloaded > 0 then
                                                UIManager:show(InfoMessage:new{ text = string.format(_(_("%d new icons found!")), downloaded), timeout = 2 })
                                            else
                                                UIManager:show(InfoMessage:new{ text = _("Icons already exist or could not be downloaded."), timeout = 2 })
                                            end
                                            
                                            table.insert(history_stack, current_node)
                                            current_node = temp_node
                                            cur_page = 1
                                            rebuildGrid()
                                            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                                        else
                                            UIManager:close(msg)
                                            UIManager:show(InfoMessage:new{ text = _("No search results found."), timeout = 2 })
                                        end
                                    else
                                        UIManager:close(msg)
                                        UIManager:show(InfoMessage:new{ text = _("Internet connection error."), timeout = 2 })
                                    end
                                end)
                            end)
                        end,
                    },
                },
            },
        }
        UIManager:show(input_dlg)
        input_dlg:onShowKeyboard()
    end}
        if choice_dlg[1] then choice_dlg[1].radius = Size.radius.window end
        local x = math.floor((Screen:getWidth() - choice_dlg.dimen.w) / 2)
        local y = math.floor((Screen:getHeight() - choice_dlg.dimen.h) / 2)
        UIManager:show(choice_dlg, nil, nil, x, y)
    end

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
                    
                    if #history_stack > 0 then
                        local back_x = content_x
                        if gx >= back_x and gx < back_x + close_sz
                           and gy >= content_y and gy < content_y + title_h then
                            goBack()
                            return true
                        end
                    end
                    local close_x = content_x + content_w - close_sz
                    if gx >= close_x and gx < close_x + close_sz
                       and gy >= content_y and gy < content_y + title_h then
                        UIManager:close(dialog)
                        return true
                    end
                    
                    if gy >= bar_y and gy < bar_y + bar_area_h and pager.getStyle() == "page_number" then
                        if gx < content_x + pager.CHEV_W then
                            goToPage(cur_page - 1)
                        elseif gx > content_x + content_w - pager.CHEV_W then
                            goToPage(cur_page + 1)
                        end
                        return true
                    end
                    
                    local grid_geom = Geom:new{
                        x = grid_x, y = grid_y,
                        w = cols * cell_w, h = rows_per_page * cell_h,
                    }
                    if ges.pos:intersectWith(grid_geom) then
                        local col_i = math.floor((gx - grid_x) / cell_w)
                        local row_i = math.floor((gy - grid_y) / cell_h)
                        local idx   = (cur_page - 1) * per_page + row_i * cols + col_i + 1
                        if idx >= 1 and idx <= #current_items then
                            local cell = current_items[idx]
                            if cell.is_dir then
                                table.insert(history_stack, current_node)
                                current_node = cell.node
                                cur_page = 1
                                rebuildGrid()
                                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                            elseif cell.is_search then
                                triggerSearch()
                            elseif cell.is_clear_temp then
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
                                local InfoMessage = require("ui/widget/infomessage")
                                UIManager:show(InfoMessage:new{ text = _("Temporary search folder cleared!"), timeout = 2 })
                                rebuildGrid()
                                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                            else
                                if current_node.name == "Search Results" then
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
                    if dir == "west" then
                        goToPage(cur_page + 1)
                    elseif dir == "east" then
                        goToPage(cur_page - 1)
                    else
                        UIManager:close(dialog)
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)
        
        local title_start_x = content_x
        if #history_stack > 0 then
            back_iw:paintTo(bb, title_start_x, content_y + math.floor((title_h - close_sz) / 2))
            title_start_x = title_start_x + close_sz + close_gap
        end
        
        title_tw:paintTo(bb, title_start_x, content_y + math.floor((title_h - title_text_h) / 2))
        
        local close_x = content_x + content_w - close_sz
        close_iw:paintTo(bb, close_x, content_y + math.floor((title_h - close_sz) / 2))
        
        if page_vgs[cur_page] then
            page_vgs[cur_page]:paintTo(bb, grid_x, grid_y)
        end
        if total_pages > 1 then
            paintBar(bb)
        end
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end

return showIconPickerDialog
