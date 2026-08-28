
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local NeoQuickSettings

NeoCaptureState = {
    cb = nil,
    path = {},
    active = false
}

local DataStorage     = require("datastorage")

local _src = debug.getinfo(1, "S").source or ""
local _plugin_root = (_src:sub(1,1) == "@") and _src:sub(2):match("^(.*)/[^/]+$") or nil
if _plugin_root and _plugin_root:sub(1,1) ~= "/" then
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    local cwd = ok_lfs and lfs and lfs.currentdir()
    if cwd then _plugin_root = cwd .. "/" .. _plugin_root end
end

if _plugin_root then
    package.path = _plugin_root .. "/?.lua;" .. package.path
end

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Event           = require("ui/event")
local Font            = require("ui/font")
local FocusManager    = require("ui/widget/focusmanager")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local IconWidget      = require("ui/widget/iconwidget")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local NetworkMgr      = require("ui/network/manager")
local ConfirmBox      = require("ui/widget/confirmbox")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Dispatcher      = require("dispatcher")
local logger          = require("logger")
local _               = require("neo_i18n").gettext
local C_              = require("neo_i18n").pgettext
local ok_sui, sui_i18n = pcall(require, "infra/sui_i18n")
if not ok_sui then ok_sui, sui_i18n = pcall(require, "sui_i18n") end
if ok_sui and sui_i18n and sui_i18n.translate then C_ = sui_i18n.translate end
local Screen          = Device.screen

local NeoSlider       = require("common/neo_slider")
local utils           = require("common/utils")

local ok_lf, library_font = pcall(require, "common/library_font")
if not ok_lf then
    library_font = {
        getFontName = function() return "cfont" end,
        getFace     = function(sz) return Font:getFace("cfont", math.max(1, math.floor(sz))) end,
    }
end

local icon_picker_err = ""
local ok_ip, showIconPickerDialog = pcall(require, "common/neo_icon_picker")
if not ok_ip then 
    icon_picker_err = tostring(showIconPickerDialog)
    local logger = require("logger")
    logger.err("Failed to load neo_icon_picker:", showIconPickerDialog)
    showIconPickerDialog = nil 
end

local _icons_dir = _plugin_root and (_plugin_root .. "/icons/") or nil

local _settings_path = DataStorage:getSettingsDir() .. "/neo_quicksettings.lua"
local LuaSettings = require("luasettings")
local _settings = LuaSettings:open(_settings_path)

local config_defaults = {
        ["button_items_per_row"] = 8,
        ["button_order"] = {
            [1] = "wifi",
            [2] = "favgrp_1",
            [3] = "rotate",
            [4] = "filebrowserplus",
            [5] = "night",
            [6] = "sleep",
            [7] = "read_goal_pages",
            [8] = "read_goal_time",
            [9] = "screenshot",
            [10] = "ssh",
            [11] = "localsend",
            [12] = "restart",
            [13] = "exit",
            [14] = "cb_1",
            [15] = "settings",
            [16] = "cb_2",
            [17] = "search",
            [18] = "kosync",
            [19] = "bluetooth",
            [20] = "streak",
            [21] = "opds",
            [22] = "stats_progress",
            [23] = "stats_calendar",
            [24] = "battery_stats",
            [25] = "bookfusion",
            [26] = "focus",
            [27] = "cb_4",
            [28] = "cb_7",
        },
        ["button_style"] = "borderless",
        ["custom_builtin_icons"] = {
            ["filebrowserplus"] = "mdi--cellphone-wireless",
            ["read_goal_pages"] = "mdi--book-check",
            ["read_goal_time"] = "mdi--book-clock",
            ["screenshot"] = "fluent--screenshot-28-filled",
            ["settings"] = "hugeicons--ai",
        },
        ["custom_builtin_labels"] = {},
        ["custom_buttons"] = {
            [1] = {
                ["action"] = {
                    ["simpleui_settings_window"] = true,
                },
                ["icon"] = "iconamoon--options-duotone",
                ["id"] = "cb_1",
            },
            [2] = {
                ["action"] = {
                    ["stats_sync"] = true,
                },
                ["icon"] = "mdi--book-sync",
                ["id"] = "cb_2",
                ["label"] = "Sync",
            },
            [3] = {
                ["action"] = {
                    ["neo_menu_path"] = {
                        [1] = "Readest",
                        [2] = "İstatistikleri şimdi gönder",
                    },
                },
                ["icon"] = "tabler--book-upload",
                ["id"] = "cb_4",
                ["label"] = "ReadUp",
            },
            [4] = {
                ["action"] = {
                    ["neo_menu_path"] = {
                        [1] = "YENİ: Upload Statistics",
                        [2] = "Upload Statistics Now",
                    },
                },
                ["icon"] = "Dark_icons/statt",
                ["id"] = "cb_7",
                ["label"] = "KoStat",
            },
        },
        ["favorite_groups"] = {
            [1] = {
                ["buttons"] = {
                    [1] = "cb_2",
                    [2] = "stats_calendar",
                    [3] = "battery_stats",
                    [4] = "cb_7",
                    [5] = "cb_4",
                },
                ["icon"] = "Star",
                ["id"] = "favgrp_1",
                ["label"] = "Fav",
                ["title"] = "Favori Butonlar",
            },
        },
        ["icon_scale_level"] = 2,
        ["label_size"] = 2,
        ["next_custom_id"] = 8,
        ["next_fav_id"] = 1,
        ["open_by_default"] = true,
        ["progress_pages"] = {
            ["10"] = false,
            ["20"] = false,
            ["30"] = false,
            ["40"] = false,
            ["50"] = true,
        },
        ["progress_time"] = {
            ["10"] = false,
            ["20"] = false,
            ["30"] = true,
            ["40"] = false,
            ["50"] = false,
            ["60"] = true,
        },
        ["reminders_pages"] = {
            ["1"] = false,
            ["10"] = true,
            ["3"] = false,
            ["5"] = true,
        },
        ["reminders_time"] = {
            ["10"] = true,
            ["15"] = false,
            ["3"] = false,
            ["5"] = true,
        },
        ["row_count"] = 2,
        ["show_buttons"] = {
            ["battery_stats"] = false,
            ["bluetooth"] = false,
            ["bookfusion"] = false,
            ["cb_1"] = true,
            ["cb_2"] = false,
            ["cb_4"] = false,
            ["cb_7"] = false,
            ["exit"] = true,
            ["favgrp_1"] = true,
            ["filebrowserplus"] = true,
            ["focus"] = false,
            ["kosync"] = false,
            ["localsend"] = true,
            ["night"] = true,
            ["opds"] = false,
            ["read_goal_pages"] = true,
            ["read_goal_time"] = true,
            ["restart"] = true,
            ["rotate"] = true,
            ["screenshot"] = true,
            ["search"] = false,
            ["settings"] = true,
            ["sleep"] = true,
            ["ssh"] = true,
            ["stats_calendar"] = false,
            ["stats_progress"] = false,
            ["streak"] = false,
            ["wifi"] = true,
        },
        ["show_frontlight"] = true,
        ["show_info_header"] = false,
        ["show_warmth"] = true,
        ["slider_style"] = "piano",
        ["toast_position"] = "top_right",
        ["user_builtin_buttons"] = {},
}

local config

local function deepcopy(o)
    if type(o) ~= "table" then return o end
    local c = {}
    for k, v in pairs(o) do c[deepcopy(k)] = deepcopy(v) end
    return c
end

local config_backup = nil
local function loadConfig()
    config = _settings:readSetting("config") or {}
    if config.two_rows ~= nil then
        if config.row_count == nil then
            config.row_count = config.two_rows and 2 or 1
        end
        config.two_rows = nil
    end
    for k, v in pairs(config_defaults) do
        if config[k] == nil then config[k] = deepcopy(v) end
    end
    if type(config.show_buttons) ~= "table" then
        config.show_buttons = deepcopy(config_defaults.show_buttons)
    end
    for k, v in pairs(config_defaults.show_buttons) do
        if config.show_buttons[k] == nil then config.show_buttons[k] = v end
    end
    if type(config.button_order) ~= "table" then
        config.button_order = deepcopy(config_defaults.button_order)
    end
    if type(config.custom_buttons) ~= "table" then config.custom_buttons = {} end
    if type(config.custom_builtin_icons) ~= "table" then config.custom_builtin_icons = {} end
    if type(config.custom_builtin_labels) ~= "table" then config.custom_builtin_labels = {} end
    if type(config.user_builtin_buttons) ~= "table" then config.user_builtin_buttons = {} end
    if type(config.favorite_groups) ~= "table" then config.favorite_groups = {} end
    if type(config.reminders_time) ~= "table" then config.reminders_time = deepcopy(config_defaults.reminders_time) end
    if type(config.reminders_pages) ~= "table" then config.reminders_pages = deepcopy(config_defaults.reminders_pages) end
    if type(config.progress_time) ~= "table" then config.progress_time = deepcopy(config_defaults.progress_time) end
    if type(config.progress_pages) ~= "table" then config.progress_pages = deepcopy(config_defaults.progress_pages) end
    if config.custom_switch_states ~= nil then config.custom_switch_states = nil end
    local cb_ids = {}
    for idx, cb in ipairs(config.custom_buttons) do
        if type(cb.id) == "string" then
            cb_ids[cb.id] = true
            if config.show_buttons[cb.id] == nil then config.show_buttons[cb.id] = true end
        end
    end
    local in_order = {}
    for idx, id in ipairs(config.button_order) do in_order[id] = true end
    
    for idx, id in ipairs(config_defaults.button_order) do
        if not in_order[id] then
            table.insert(config.button_order, id)
            in_order[id] = true
        end
    end

    for idx, cb in ipairs(config.custom_buttons) do
        if type(cb.id) == "string" and not in_order[cb.id] then
            table.insert(config.button_order, cb.id)
            in_order[cb.id] = true
        end
    end
end

local buildSettingsMenuItems
local createQuickSettingsPanel

-- Icon path cache: resolveIcon() does lfs stat on every call — cache results per icon name
local _icon_path_cache = {}
local function resolveIconCached(icon_name)
    if _icon_path_cache[icon_name] ~= nil then return _icon_path_cache[icon_name] end
    local path = _icons_dir and utils.resolveIcon(_icons_dir, icon_name) or false
    _icon_path_cache[icon_name] = path
    return path
end

-- Flag: custom button_defs need rebuilding on next panel creation
local _button_defs_dirty = true

local function saveConfig()
    _settings:saveSetting("config", config)
    _settings:flush()
    _button_defs_dirty = true
    -- Defer the expensive panel rebuild to the next event-loop tick so
    -- the settings write does not block the UI thread.
    if createQuickSettingsPanel and UIManager and UIManager._window_stack then
        UIManager:scheduleIn(0, function()
            if not UIManager._window_stack then return end
            for i = #UIManager._window_stack, 1, -1 do
                local win = UIManager._window_stack[i]
                if win and type(win.updateItems) == "function" then
                    if win.item_table_stack then
                        for _, it in ipairs(win.item_table_stack) do
                            if it.panel then
                                it.panel = createQuickSettingsPanel(win)
                            end
                        end
                    end
                    if win.item_table and win.item_table.panel then
                        win.item_table.panel = createQuickSettingsPanel(win)
                        win:updateItems(1)
                        break -- only the topmost panel-bearing window needs updating
                    end
                end
            end
        end)
    end
end

loadConfig()

-- Cache for hasPlugin results (filesystem check is expensive; reset on config reload)
local _plugin_exists_cache = {}
local function hasPlugin(name)
    if _plugin_exists_cache[name] ~= nil then return _plugin_exists_cache[name] end
    if G_reader_settings:isTrue("plugin_" .. name .. "_enabled") then
        _plugin_exists_cache[name] = true
        return true
    end
    local ok_datastorage, DataStorage = pcall(require, "datastorage")
    local data_dir = ok_datastorage and DataStorage and DataStorage.getDataDir and DataStorage:getDataDir() or nil
    local candidates = { "plugins/" .. name .. ".koplugin/main.lua" }
    if data_dir then table.insert(candidates, data_dir .. "/plugins/" .. name .. ".koplugin/main.lua") end
    for idx, path in ipairs(candidates) do
        local file = io.open(path, "r")
        if file then file:close(); _plugin_exists_cache[name] = true; return true end
    end
    _plugin_exists_cache[name] = false
    return false
end

-- Separate caches for ReaderUI and FileManager
local _cached_reader_ui = nil
local _cached_fm_ui = nil

local function getMainUI()
    -- Prefer ReaderUI (plugin-specific items like Readest live there)
    if _cached_reader_ui and _cached_reader_ui.menu then
        return _cached_reader_ui
    end
    -- Fall back to FileManager
    if _cached_fm_ui and _cached_fm_ui.menu then
        return _cached_fm_ui
    end
    return nil
end

local function showPluginMissingMessage(text)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text })
end

local function showTopRightToast(msg)
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(0.3, function()
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
        local Size = require("ui/size")
        local Screen = require("device").screen
        local InputContainer = require("ui/widget/container/inputcontainer")
        local Blitbuffer = require("ffi/blitbuffer")
        
                local TextWidget = require("ui/widget/textwidget")
        local face = require("ui/font"):getFace("infofont")
        local max_line_w = 0
        for line in msg:gmatch("[^\r\n]+") do
            local lw = TextWidget:new{ text = line, face = face }:getSize().w
            if lw > max_line_w then max_line_w = lw end
        end
        local max_w = math.floor(Screen:getWidth() * 0.65)
        local final_w = math.min(max_line_w, max_w)
        
        local text_box = TextBoxWidget:new{
            text = msg,
            face = face,
            width = final_w,
            alignment = "center",
        }
        
        local frame = FrameContainer:new{
            margin = 0,
            padding = Size.padding.large,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.default,
            radius = Size.radius.window,
            text_box
        }
        
        local gap = math.floor(Screen:getWidth() * 0.03)
        local gap_container = require("ui/widget/container/widgetcontainer"):extend{
            getSize = function(this)
                local s = this[1]:getSize()
                return require("ui/geometry"):new{ w = s.w + gap*2, h = s.h + gap*2 }
            end,
            paintTo = function(this, b, x, y)
                this[1]:paintTo(b, x + gap, y + gap)
            end
        }
        local padded_frame = gap_container:new{ frame }
        
        local pos = config and config.toast_position or "center"
        local v_pos, h_pos = 0.5, 0.5
        if pos == "top" then v_pos = 0.0; h_pos = 0.5
        elseif pos == "bottom" then v_pos = 1.0; h_pos = 0.5
        elseif pos == "top_right" then v_pos = 0.0; h_pos = 1.0
        elseif pos == "bottom_right" then v_pos = 1.0; h_pos = 1.0
        elseif pos == "top_left" then v_pos = 0.0; h_pos = 0.0
        elseif pos == "bottom_left" then v_pos = 1.0; h_pos = 0.0
        end
        
        local align = CustomPositionContainer:new{
            vertical_position = v_pos,
            horizontal_position = h_pos,
            dimen = Screen:getSize(),
            widget = padded_frame
        }
        
        local Toast = InputContainer:extend{
            modal = false,
        }
        function Toast:init()
            self[1] = align
            self.dimen = Screen:getSize()
        end
        function Toast:paintTo(b, x, y)
            self[1]:paintTo(b, x, y)
        end
        function Toast:onShow()
            UIManager:scheduleIn(3.0, function()
                UIManager:close(self)
            end)
        end
        function Toast:onIgnoreTouchInput(toggle)
            return true
        end
        
        UIManager:show(Toast:new{})
    end)
end

local function isReadingActive()
    local UIManager = require("ui/uimanager")
    if not UIManager._window_stack then return false end
    if NeoQuickSettings._is_suspended then return false end
    
    local reader_idx = 0
    
    for i = 1, #UIManager._window_stack do
        local w = UIManager._window_stack[i].widget
        if w then
            local name = tostring(w.name or "")
            local id = tostring(w.id or "")
            if name == "ReaderUI" or id == "ReaderUI" then
                reader_idx = i
                break
            end
        end
    end
    
    if reader_idx == 0 then return false end
    
    local reader_ui = UIManager._window_stack[reader_idx].widget
    
    -- Check KOReader's internal menu states
    if reader_ui and type(reader_ui.ui) == "table" then
        if reader_ui.ui.menu and reader_ui.ui.menu.show_menu then return false end
        if reader_ui.ui.dictionary and reader_ui.ui.dictionary.show then return false end
        if reader_ui.ui.toc and reader_ui.ui.toc.show then return false end
        if reader_ui.ui.bookmark and reader_ui.ui.bookmark.show then return false end
    end
    
    local has_menu = false
    
    for i = reader_idx + 1, #UIManager._window_stack do
        local w = UIManager._window_stack[i].widget
        if w then
            local name = tostring(w.name or ""):lower()
            local id = tostring(w.id or ""):lower()
            local title = tostring(w.title or w.title_text or ""):lower()
            
            -- Ignore known transparent overlays
            if name:match("bookends") or id:match("bookends") or name:match("halo") then
                -- skip this harmless overlay
            else
                -- Is this unknown widget a menu?
                
                -- 1. Keyword check
                if name:match("menu") or id:match("menu") or title:match("menu") or title:match("menü") or
                   name:match("dialog") or id:match("dialog") or
                   name:match("box") or id:match("box") or
                   name:match("popup") or id:match("popup") or
                   name:match("manager") or id:match("manager") or
                   name:match("settings") or id:match("settings") or title:match("ayarlar") or
                   name:match("dict") or id:match("dict") or title:match("sözlük") or
                   name:match("keyboard") or id:match("keyboard") or
                   name:match("simpleui") or id:match("simpleui") or
                   name:match("bento") or id:match("bento") then
                    has_menu = true
                end
                
                -- 2. Property check
                if w.menu_items or w.items or w.buttons or w.dim ~= nil or w.show_menu then
                    has_menu = true
                end
                
                -- 3. Visual & Structure check (The Ultimate Catch-All for SimpleUI and Unknown Menus)
                -- If it has a background color, it blocks the screen -> Menu
                if w.background or w.bg_color then
                    has_menu = true
                end
                -- If it contains child widgets (buttons, icons, layouts), it's a UI Container -> Menu
                -- Pure gesture overlays have no children.
                if w[1] ~= nil then
                    has_menu = true
                end
            end
        end
    end
    
    return not has_menu
end

local function getActiveReaderUI()
    local UIManager = require("ui/uimanager")
    if UIManager._window_stack then
        for i = 1, #UIManager._window_stack do
            local w = UIManager._window_stack[i].widget
            if w and w.name == "ReaderUI" then
                return w
            end
        end
    end
    return nil
end

local button_defs
button_defs = {
    read_goal_time = {
        icon = "quick_time",
        label = C_("Time Goal"),
        label_func = function()
            if NeoQuickSettings.time_goal_remaining then
                return tostring(NeoQuickSettings.time_goal_remaining) .. "m"
            end
            return C_("Time Goal")
        end,
        active_func = function() return NeoQuickSettings.time_goal_remaining ~= nil end,
        callback = function(touch_menu)
            if not getActiveReaderUI() then
                showTopRightToast(_("Only available while reading a book"))
                return
            end
            local InputDialog = require("ui/widget/inputdialog")
            local InfoMessage = require("ui/widget/infomessage")
            local ConfirmBox = require("ui/widget/confirmbox")
            
            local function showGoalDialog()
                local dialog
                dialog = InputDialog:new{
                    title = _("Reading Time Goal (minutes)"),
                    input = NeoQuickSettings.time_goal_remaining and tostring(NeoQuickSettings.time_goal_remaining) or "30",
                    type = "number",
                    buttons = {{
                        {
                            text = C_("Cancel"),
                            id = "close",
                            callback = function() UIManager:close(dialog) end,
                        },
                        {
                            text = C_("Start"),
                            callback = function()
                                local val = tonumber(dialog:getInputText())
                                if val and val > 0 then
                                    NeoQuickSettings.time_goal_remaining = val
                                    NeoQuickSettings.time_goal_id = (NeoQuickSettings.time_goal_id or 0) + 1
                                    UIManager:show(InfoMessage:new{ text = _("Time goal started: ") .. val .. _(" min"), timeout = 2 })
                                else
                                    NeoQuickSettings.time_goal_remaining = nil
                                    NeoQuickSettings.time_goal_id = nil
                                end
                                UIManager:close(dialog)
                                if touch_menu and touch_menu.updateItems then touch_menu:updateItems(touch_menu.page or 1) end
                            end,
                        },
                    }},
                }
                UIManager:show(dialog)
            end

            if NeoQuickSettings.time_goal_remaining then
                local ButtonDialog = require("ui/widget/buttondialog")
                local dialog
                dialog = ButtonDialog:new{
                    
                    title = _("You have an active time goal (") .. NeoQuickSettings.time_goal_remaining .. _(" min remaining).\n\nDo you want to cancel it?"),
                    title_align = "center",
                    use_info_style = false,
                    buttons = {
                        {
                            {
                                text = _("Cancel Goal"),
                                callback = function()
                                    NeoQuickSettings.time_goal_remaining = nil
                                    NeoQuickSettings.time_goal_id = (NeoQuickSettings.time_goal_id or 0) + 1
                                    if touch_menu and touch_menu.updateItems then touch_menu:updateItems(touch_menu.page or 1) end
                                    UIManager:close(dialog)
                                end,
                            }
                        },
                        {
                            {
                                text = _("Change Goal"),
                                callback = function()
                                    UIManager:close(dialog)
                                    showGoalDialog()
                                end,
                            }
                        }
                    }
                }
                UIManager:show(dialog)
            else
                showGoalDialog()
            end
        end,
    },
    read_goal_pages = {
        icon = "quick_bookmark",
        label = C_("Page Goal"),
        label_func = function()
            if NeoQuickSettings.page_goal_remaining then
                return tostring(NeoQuickSettings.page_goal_remaining) .. "p"
            end
            return C_("Page Goal")
        end,
        active_func = function() return NeoQuickSettings.page_goal_remaining ~= nil end,
        hold_callback = function(touch_menu)
            local ui = getActiveReaderUI()
            if not ui then
                showTopRightToast(_("Only available while reading a book"))
                return
            end
            local pageno = ui.view and ui.view.state and ui.view.state.page or 1
            local left = 0
            if ui.toc and ui.toc.getChapterPagesLeft then
                left = ui.toc:getChapterPagesLeft(pageno) or 0
            end
            if left == 0 and ui.document and ui.document.getTotalPagesLeft then
                left = ui.document:getTotalPagesLeft(pageno) or 0
            end

            -- Ninja Motoru (Ninja Engine v4) Uyumluluğu
            if ui and ui.document and ui.doc_settings then
                local doc_settings = ui.doc_settings
                local sync_enabled = doc_settings:readSetting("yanllsama_sync_enabled")
                if sync_enabled == nil then sync_enabled = true end
                
                if sync_enabled then
                    local pagemap = ui.pagemap
                    local use_pm = pagemap and pagemap.has_pagemap and pagemap.use_page_labels
                    
                    if not use_pm then
                        local ratio = doc_settings:readSetting("yanllsama_screen_ratio") or 1.0
                        if doc_settings:readSetting("pagemap_chars_per_synthetic_page") then ratio = 1.0 end
                        
                        -- Ratio ile ekran sayısını fiziksel sayfa sayısına dönüştür (sayfa hedefini tutturmak için)
                        if ratio ~= 1.0 then
                            left = math.ceil(left / ratio)
                        end
                    end
                end
            end

            if left and left > 0 then
                NeoQuickSettings.page_goal_remaining = left
                NeoQuickSettings.last_phys_page = nil
                touch_menu:updateItems()
                local InfoMessage = require("ui/widget/infomessage")
                require("ui/uimanager"):show(InfoMessage:new{
                    text = _("Goal set to chapter end: ") .. left .. _(" pages"),
                    timeout = 3,
                })
            else
                showTopRightToast(_("Could not determine chapter length"))
            end
        end,
        callback = function(touch_menu)
            if not getActiveReaderUI() then
                showTopRightToast(_("Only available while reading a book"))
                return
            end
            local InputDialog = require("ui/widget/inputdialog")
            local InfoMessage = require("ui/widget/infomessage")
            local ConfirmBox = require("ui/widget/confirmbox")
            
            local function showGoalDialog()
                local dialog
                dialog = InputDialog:new{
                    title = _("Reading Page Goal"),
                    input = NeoQuickSettings.page_goal_remaining and tostring(NeoQuickSettings.page_goal_remaining) or "10",
                    type = "number",
                    buttons = {{
                        {
                            text = C_("Cancel"),
                            id = "close",
                            callback = function() UIManager:close(dialog) end,
                        },
                        {
                            text = C_("Start"),
                            callback = function()
                                local val = tonumber(dialog:getInputText())
                                if val and val > 0 then
                                    NeoQuickSettings.page_goal_remaining = val
                                    NeoQuickSettings.last_phys_page = nil
                                    local InfoMessage = require("ui/widget/infomessage")
                                    require("ui/uimanager"):show(InfoMessage:new{ text = _("Page goal started: ") .. val .. _(" pages"), timeout = 2 })
                                else
                                    NeoQuickSettings.page_goal_remaining = nil
                                    NeoQuickSettings.last_phys_page = nil
                                end
                                require("ui/uimanager"):close(dialog)
                                if touch_menu and touch_menu.updateItems then touch_menu:updateItems(touch_menu.page or 1) end
                            end,
                        },
                        {
                            text = _("End of Chapter"),
                            callback = function()
                                require("ui/uimanager"):close(dialog)
                                if button_defs and button_defs.read_goal_pages and button_defs.read_goal_pages.hold_callback then
                                    button_defs.read_goal_pages.hold_callback(touch_menu)
                                end
                            end,
                        },
                    }},
                }
                UIManager:show(dialog)
            end

            if NeoQuickSettings.page_goal_remaining then
                local ButtonDialog = require("ui/widget/buttondialog")
                local dialog
                dialog = ButtonDialog:new{
                    
                    title = _("You have an active page goal (") .. NeoQuickSettings.page_goal_remaining .. _(" pages remaining).\n\nDo you want to cancel it?"),
                    title_align = "center",
                    use_info_style = false,
                    buttons = {
                        {
                            {
                                text = _("Cancel Goal"),
                                callback = function()
                                    NeoQuickSettings.page_goal_remaining = nil
                                    NeoQuickSettings.last_phys_page = nil
                                    if touch_menu and touch_menu.updateItems then touch_menu:updateItems(touch_menu.page or 1) end
                                    UIManager:close(dialog)
                                end,
                            }
                        },
                        {
                            {
                                text = _("Change Goal"),
                                callback = function()
                                    UIManager:close(dialog)
                                    showGoalDialog()
                                end,
                            }
                        }
                    }
                }
                UIManager:show(dialog)
            else
                showGoalDialog()
            end
        end,
    },
    wifi = {
        icon  = "quick_wifi",
        label = C_("Wi-Fi"),
        label_func  = function()
            if NetworkMgr:isWifiOn() then
                local net = NetworkMgr.getCurrentNetwork and NetworkMgr:getCurrentNetwork()
                if net and net.ssid then return net.ssid end
            end
            return C_("Wi-Fi")
        end,
        active_func = function() return NetworkMgr:isWifiOn() end,
        callback = function(touch_menu)
            if NetworkMgr:isWifiOn() then
                NetworkMgr:toggleWifiOff()
            else
                NetworkMgr:toggleWifiOn()
            end
            UIManager:scheduleIn(1, function()
                if touch_menu.item_table and touch_menu.item_table.panel then
                    touch_menu:updateItems(1)
                end
            end)
        end,
    },
    night = {
        icon  = "quick_nightmode",
        label = C_("Night"),
        active_func = function() return G_reader_settings:isTrue("night_mode") end,
        callback = function(touch_menu)
            local night_mode = G_reader_settings:isTrue("night_mode")
            Screen:toggleNightMode()
            UIManager:ToggleNightMode(not night_mode)
            G_reader_settings:saveSetting("night_mode", not night_mode)
            touch_menu:updateItems(1)
            UIManager:setDirty("all", "full")
        end,
    },
    rotate = {
        icon  = "quick_rotate",
        label = C_("Rotate"),
        callback = function()
            UIManager:broadcastEvent(Event:new("IterateRotation"))
        end,
    },
    sleep = {
        icon  = "quick_sleep",
        label = C_("Sleep"),
        callback = function()
            if Device:canSuspend() then
                UIManager:broadcastEvent(Event:new("RequestSuspend"))
            elseif Device:canPowerOff() then
                UIManager:broadcastEvent(Event:new("RequestPowerOff"))
            end
        end,
    },
    restart = {
        icon  = "quick_restart",
        label = C_("Restart"),
        callback = function()
            local SlideConfirmBox = require("slideconfirmbox")
            UIManager:show(SlideConfirmBox:new{
                                title = _("Restart?"),
                text  = _("Swipe to restart"),
                icon  = "quick_restart",
                on_confirm = function()
                    UIManager:broadcastEvent(Event:new("Restart"))
                end,
            })
        end,
    },
    exit = {
        icon  = "quick_exit",
        label = C_("Exit"),
        callback = function()
            local SlideConfirmBox = require("slideconfirmbox")
            UIManager:show(SlideConfirmBox:new{
                                title = _("Exit?"),
                text  = _("Swipe to exit"),
                icon  = "quick_exit",
                on_confirm = function()
                    UIManager:broadcastEvent(Event:new("Exit"))
                end,
            })
        end,
    },
    search = {
        icon  = "quick_search",
        label = C_("Search"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowFileSearch"))
        end,
    },
    screenshot = {
        icon  = "quick_screenshot",
        label = C_("Screenshot"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:scheduleIn(0.3, function()
                UIManager:broadcastEvent(Event:new("Screenshot"))
            end)
        end,
    },
    kosync = {
        icon  = "quick_sync",
        label = C_("Sync"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:broadcastEvent(Event:new("KOSyncPullProgress"))
            UIManager:scheduleIn(1, function()
                UIManager:broadcastEvent(Event:new("KOSyncPushProgress"))
            end)
        end,
    },
    filebrowserplus = {
        icon  = "quick_filebrowser_new",
        label = C_("FileBrowser+"),
        active_func = function()
            local ok, fb = pcall(require, "plugins/filebrowserplus.koplugin/main")
            return ok and fb and fb.isRunning and fb:isRunning() or false
        end,
        callback = function(touch_menu)
            UIManager:broadcastEvent(Event:new("ToggleFilebrowserPlusServer"))
            UIManager:scheduleIn(1.5, function()
                if touch_menu.item_table and touch_menu.item_table.panel then
                    touch_menu:updateItems(1)
                end
            end)
        end,
    },
    ssh = {
        icon  = "quick_connections_new",
        label = C_("SSH"),
        active_func = function()
            local ok, ssh = pcall(require, "plugins/ssh.koplugin/main")
            return ok and ssh and ssh.isRunning and ssh:isRunning() or false
        end,
        callback = function(touch_menu)
            UIManager:broadcastEvent(Event:new("ToggleSshServer"))
            UIManager:scheduleIn(1.5, function()
                if touch_menu.item_table and touch_menu.item_table.panel then
                    touch_menu:updateItems(1)
                end
            end)
        end,
    },
    bluetooth = {
        icon  = "quick_connections_new",
        label = C_("Bluetooth"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:broadcastEvent(Event:new("ToggleBluetooth"))
        end,
    },
    streak = {
        icon = "quick_streak_new",
        label = C_("Streak"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowReadingStreakCalendar"))
        end,
    },
    opds = {
        icon = "quick_opds_new",
        label = C_("OPDS"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowOPDSCatalog"))
        end,
    },
    stats_progress = {
        icon = "quick_stats_progress_new",
        label = C_("Progress"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:broadcastEvent(Event:new("ShowReaderProgress"))
        end,
    },
    stats_calendar = {
        icon = "quick_stats_calendar_new",
        label = C_("Calendar"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:broadcastEvent(Event:new("ShowCalendarView"))
        end,
    },
    battery_stats = {
        icon = "quick_battery_new",
        label = C_("Battery"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            UIManager:broadcastEvent(Event:new("ShowBatteryStatistics"))
        end,
    },
    localsend = {
        icon = "quick_localsend_new",
        label = C_("LocalSend"),
        callback = function(touch_menu)
            UIManager:broadcastEvent(Event:new("ToggleLocalSend"))
            UIManager:scheduleIn(1.5, function()
                if touch_menu.item_table and touch_menu.item_table.panel then
                    touch_menu:updateItems(1)
                end
            end)
        end,
    },
    bookfusion = {
        icon = "quick_bookfusion_new",
        label = C_("BookFusion"),
        callback = function(touch_menu)
            touch_menu:closeMenu()
            local ui = getMainUI()
            if ui and ui.bookfusion then
                if ui.bookfusion.bf_settings and ui.bookfusion.bf_settings.isLoggedIn and ui.bookfusion.bf_settings:isLoggedIn() then
                    ui.bookfusion:onSearchBooks()
                else
                    ui.bookfusion:onLinkDevice()
                end
                return
            end
            showPluginMissingMessage(C_("BookFusion plugin is not installed."))
        end,
    },
    focus = {
        icon = "quick_focus_new",
        label = C_("Focus"),
        callback = function()
            showPluginMissingMessage(C_("Focus mode control is available in the quicksettings plugin build."))
        end,
    },
}

local buildSettingsMenuItems

local function createQuickSettingsPanel(touch_menu)
    if touch_menu._neo_just_toggled_group then
        touch_menu._neo_just_toggled_group = false
    else
        touch_menu.neo_active_favorite_group = nil
    end

    local panel_width = touch_menu.item_width
    local padding     = Screen:scaleBySize(10)
    local inner_width = panel_width - padding * 2
    local powerd      = Device:getPowerDevice()
    local refs        = { buttons = {}, sliders = {}, button_layout_row = {} }

    -- Rebuild custom button_defs only when config has changed (dirty flag)
    if _button_defs_dirty then
        _button_defs_dirty = false
        -- Clear previous custom/userbuiltin/favorite entries from button_defs
        for k in pairs(button_defs) do
            if type(k) == "string" and (k:sub(1, 3) == "cb_" or k:sub(1, 3) == "fg_" or k:sub(1, 4) == "ubi_") then
                button_defs[k] = nil
            end
        end
        -- Wipe icon path cache too since icons may have changed
        _icon_path_cache = {}
    end

    for idx, arr in ipairs({config.custom_buttons, config.user_builtin_buttons}) do
        for idx, cb in ipairs(arr) do
            local cb_action    = cb.action
            local cb_iconstyle = cb.icon_style  -- "default"/nil, "gray", "invert"
            button_defs[cb.id] = {
                icon       = cb.icon or ("button"),
                icon_style = cb_iconstyle,
                label = (cb.label and cb.label ~= "") and cb.label
                    or (cb_action and next(cb_action) and Dispatcher:menuTextFunc(cb_action))
                    or C_("Custom"),
                callback = function(tm)
                    tm:closeMenu()
                    if type(cb_action) == "table" and next(cb_action) then
                        if cb_action.neo_menu_path then
                            -- Try reader UI first (plugin items like Readest only live there),
                            -- then fall back to FileManager UI
                            local main_ui = _cached_reader_ui or _cached_fm_ui
                            local reader_menu = main_ui and main_ui.menu
                            if not reader_menu then
                                local InfoMessage = require("ui/widget/infomessage")
                                UIManager:show(InfoMessage:new{ text = _("Could not find KOReader menu. Please open a book first."), timeout = 4 })
                                return
                            end
                            if not reader_menu.tab_item_table then
                                reader_menu:setUpdateItemTable()
                            end
                            -- Flatten all tabs into a searchable list.
                            -- Standard KOReader tabs are plain arrays; our neo tab is an object with sub_item_table_func.
                            local current_table = {}
                            for _, tab in ipairs(reader_menu.tab_item_table) do
                                if type(tab) == "table" then
                                    if tab.sub_item_table then
                                        for _, item in ipairs(tab.sub_item_table) do
                                            table.insert(current_table, item)
                                        end
                                    elseif tab.sub_item_table_func then
                                        -- skip our own neo tab to avoid polluting the search
                                        if tab.id ~= "neo_quicksettings" then
                                            local ok, items = pcall(tab.sub_item_table_func)
                                            if ok and type(items) == "table" then
                                                for _, item in ipairs(items) do
                                                    table.insert(current_table, item)
                                                end
                                            end
                                        end
                                    else
                                        -- plain array of items (standard KOReader tabs)
                                        for _, item in ipairs(tab) do
                                            if type(item) == "table" then
                                                table.insert(current_table, item)
                                            end
                                        end
                                    end
                                end
                            end
                            -- Walk the path
                            -- Determine whether the final item should open a sub-menu
                            local function showNativeMenu(title, items)
                                local Menu   = require("ui/widget/menu")
                                local Size   = require("ui/size")
                                local SCR    = require("device").screen
                                local scr_w  = SCR:getWidth()
                                local scr_h  = SCR:getHeight()
                                local menu_items = {}
                                for _, it in ipairs(items) do
                                    local it_text = it.text or (it.text_func and it.text_func()) or ""
                                    if it_text ~= "" then
                                        local has_sub = it.sub_item_table or it.sub_item_table_func
                                        table.insert(menu_items, {
                                            text      = it_text .. (has_sub and " ▶" or ""),
                                            _neo_item = it,
                                        })
                                    end
                                end
                                if #menu_items == 0 then return end
                                local m
                                m = Menu:new{
                                    title          = title,
                                    item_table     = menu_items,
                                    width          = math.floor(scr_w * 0.85),
                                    height         = math.floor(scr_h * 0.85),
                                    items_per_page = 12,
                                    onMenuChoice   = function(_mi, choice)
                                        UIManager:close(m)
                                        local orig = choice._neo_item
                                        if not orig then return end
                                        if orig.sub_item_table or orig.sub_item_table_func then
                                            local sub = orig.sub_item_table or orig.sub_item_table_func()
                                            local sub_title = orig.text or (orig.text_func and orig.text_func()) or ""
                                            showNativeMenu(sub_title, sub)
                                        else
                                            local exec_cb = (orig.callback_func and orig.callback_func()) or orig.callback
                                            if exec_cb then
                                                local dummy = { closeMenu = function() end, updateItems = function() end }
                                                exec_cb(dummy)
                                            end
                                        end
                                    end,
                                }
                                if m[1] then m[1].radius = Size.radius.window end
                                local mx = math.floor((scr_w - m.dimen.w) / 2)
                                local my = math.floor((scr_h - m.dimen.h) / 2)
                                UIManager:show(m, nil, nil, mx, my)
                            end

                            for i, p_text in ipairs(cb_action.neo_menu_path) do
                                local found = nil
                                for _, item in ipairs(current_table) do
                                    local itext = item.text or (item.text_func and item.text_func())
                                    if itext == p_text then found = item; break end
                                end
                                if found then
                                    if i == #cb_action.neo_menu_path then
                                        -- Final item: open sub-menu OR execute callback
                                        if cb_action.neo_is_submenu then
                                            local sub = found.sub_item_table
                                                     or (found.sub_item_table_func and found.sub_item_table_func())
                                            if sub then
                                                local label = found.text or (found.text_func and found.text_func()) or p_text
                                                showNativeMenu(label, sub)
                                            end
                                        else
                                            local exec_cb = (found.callback_func and found.callback_func()) or found.callback
                                            if exec_cb then
                                                local dummy_menu = { closeMenu = function() end, updateItems = function() end }
                                                exec_cb(dummy_menu)
                                            end
                                        end
                                        break
                                    else
                                        -- Descend into sub-menu
                                        if found.sub_item_table then
                                            current_table = found.sub_item_table
                                        elseif found.sub_item_table_func then
                                            current_table = found.sub_item_table_func()
                                        else
                                            break
                                        end
                                    end
                                else
                                    local InfoMessage = require("ui/widget/infomessage")
                                    UIManager:show(InfoMessage:new{ text = _("Menu item not found: ") .. tostring(p_text), timeout = 3 })
                                    break
                                end
                            end
                        else
                            Dispatcher:execute(cb_action)
                        end
                    end
                end,
            }
        end
    end

    for idx, fg in ipairs(config.favorite_groups or {}) do
        button_defs[fg.id] = {
            icon = fg.icon or ("button"),
            label = fg.label or C_("Favorite"),
            active_func = function() return touch_menu.neo_active_favorite_group == fg.id end,
            callback = function(tm)
                tm._neo_just_toggled_group = true
                if tm.neo_active_favorite_group == fg.id then
                    tm.neo_active_favorite_group = nil
                else
                    tm.neo_active_favorite_group = fg.id
                end
                tm:updateItems(1)
            end,
        }
    end

    do
        local _bsmi = buildSettingsMenuItems
        button_defs["settings"] = {
            icon  = "settings",
            label = C_("Settings"),
            callback = function(tm)
                if not _bsmi then return end
                local settings_items = _bsmi()
                if tm.item_table_stack and tm.updateItems then
                    table.insert(tm.item_table_stack, tm.item_table)
                    tm.item_table = settings_items
                    tm:updateItems(1)
                end
            end,
        }
    end
    
    local visible_buttons = {}
    for idx, id in ipairs(config.button_order) do
        if config.show_buttons[id] and button_defs[id] then
            table.insert(visible_buttons, { id = id, def = button_defs[id] })
        end
    end

    local num_buttons     = #visible_buttons
    local action_btn_size = Screen:scaleBySize(64)
    local scale_map       = { [1] = 0.5, [2] = 0.65, [3] = 0.8 }
    local icon_scale      = scale_map[config.icon_scale_level or 1] or 0.5
    local icon_size       = math.floor(action_btn_size * icon_scale)
    local base_label_size = Font.sizemap and Font.sizemap["xx_smallinfofont"] or 18
    local user_level = config.label_size
    if user_level == "normal" or user_level == nil then user_level = 5 end
    if user_level == "small" then user_level = 3 end
    if user_level == "large" then user_level = 7 end
    if type(user_level) == "number" then
        base_label_size = base_label_size + (user_level - 5) * 2
    end
    local label_font = library_font.getFace(math.max(8, base_label_size))
    local normal_border   = 1

    local function makeActionButton(icon_name, label_text, active, dim)
        local icon_path = resolveIconCached(icon_name)
        local icon_w = IconWidget:new{
            file   = icon_path or nil,
            icon   = (not icon_path) and icon_name or nil,
            width  = icon_size,
            height = icon_size,
            alpha  = not active,
            dim    = dim or nil,
        }
        if active then
            icon_w:_render()
            if icon_w._bb then
                local bb_copy = icon_w._bb:copy()
                bb_copy:invertRect(0, 0, bb_copy:getWidth(), bb_copy:getHeight())
                icon_w._bb = bb_copy
            end
        end
        
        local border = active and 0 or normal_border
        local bg = active and Blitbuffer.COLOR_BLACK
            or dim  and Blitbuffer.COLOR_LIGHT_GRAY
            or       Blitbuffer.COLOR_WHITE
        local corner_r = math.floor(action_btn_size / 2)

        if config.button_style == "rounded_square" then
            corner_r = math.floor(action_btn_size / 4)
        elseif config.button_style == "borderless" then
            border = 0
            if not active then bg = nil end
        end

        local circle = FrameContainer:new{
            width      = action_btn_size,
            height     = action_btn_size,
            radius     = corner_r,
            bordersize = border,
            bordercolor= Blitbuffer.COLOR_DARK_GRAY,
            background = bg,
            padding    = 0,
            CenterContainer:new{
                dimen = Geom:new{
                    w = action_btn_size - border * 2,
                    h = action_btn_size - border * 2,
                },
                icon_w,
            },
        }
        local label_w = nil
        if config.label_size ~= "hidden" then
            label_w = TextWidget:new{
                text      = label_text,
                face      = label_font,
                max_width = action_btn_size + Screen:scaleBySize(4),
            }
        end
        local group = VerticalGroup:new{
            align = "center",
            circle,
            label_w and VerticalSpan:new{ width = Screen:scaleBySize(2) } or nil,
            label_w,
        }
        return group, circle
    end

    local function makeRowGroup(row_entries)
        local row_group = HorizontalGroup:new{ align = "center" }
        local n = #row_entries
        if n > 0 then
            local btn_gap = math.floor(
                (inner_width - n * action_btn_size) / math.max(n - 1, 1)
            )
            for i, entry in ipairs(row_entries) do
                local def        = entry.def
                local label_text = (config.custom_builtin_labels and config.custom_builtin_labels[entry.id]) or (def.label_func and def.label_func()) or def.label
                local active     = def.active_func   and def.active_func()   or false
                local disabled   = def.disabled_func and def.disabled_func() or false
                local icon_name   = (config.custom_builtin_icons and config.custom_builtin_icons[entry.id]) or def.icon
                local icon_style  = def.icon_style
                local btn_widget, btn_circle = makeActionButton(
                    icon_name, label_text, active and not disabled, disabled
                )
                table.insert(refs.buttons, {
                    widget       = btn_circle,
                    callback     = not disabled and function() def.callback(touch_menu) end or nil,
                    hold_callback= def.hold_callback and function() def.hold_callback(touch_menu) end or nil,
                })
                table.insert(refs.button_layout_row, btn_circle)
                table.insert(row_group, btn_widget)
                if i < n then
                    table.insert(row_group, HorizontalSpan:new{ width = btn_gap })
                end
            end
        end
        return row_group
    end

    local row_entries = {}
    local current_entries = {}
    for i, entry in ipairs(visible_buttons) do
        table.insert(current_entries, entry)
        if #current_entries == (config.button_items_per_row or 8) then
            table.insert(row_entries, current_entries)
            current_entries = {}
        end
    end
    if #current_entries > 0 then
        table.insert(row_entries, current_entries)
    end
    
    local row_groups = {}
    for idx, entries in ipairs(row_entries) do
        table.insert(row_groups, makeRowGroup(entries))
    end

    local medium_size     = Font.sizemap and Font.sizemap["ffont"] or 24
    local medium_font     = library_font.getFace(medium_size)
    local small_btn_size  = Screen:scaleBySize(14)
    local small_btn_width = Screen:scaleBySize(56)
    local slider_gap      = Screen:scaleBySize(4)
    local cap_label_w     = Screen:scaleBySize(28)   -- matches cap_font text
    local slider_width    = inner_width
                            - 2 * small_btn_width   -- minus/plus buttons
                            - 2 * slider_gap        -- gaps beside slider
                            - 2 * cap_label_w       -- min/max label columns
                            - 2 * Screen:scaleBySize(2)  -- inner spans
    local show_parent     = touch_menu.show_parent

    local slider_opts = {
        inner_width     = inner_width,
        slider_width    = slider_width,
        small_btn_width = small_btn_width,
        slider_gap      = slider_gap,
        medium_font     = medium_font,
        small_btn_size  = small_btn_size,
        cap_label_w     = cap_label_w,
        powerd          = powerd,
        slider_style    = config.slider_style or "neo",
        refs            = refs,
    }

    local build_brightness_slider = require("modules/menu/patches/brightness_slider")
    local build_warmth_slider     = require("modules/menu/patches/warmth_slider")

    local fl_group = VerticalGroup:new{ align = "center" }
    if config.show_frontlight and Device:hasFrontlight() then
        fl_group = build_brightness_slider(touch_menu, slider_opts)
    end

    local warmth_group = VerticalGroup:new{ align = "center" }
    if config.show_warmth and Device:hasNaturalLight() then
        warmth_group = build_warmth_slider(touch_menu, slider_opts)
    end

    local fav_row_groups = {}
    local active_fg_id = touch_menu.neo_active_favorite_group
    if active_fg_id then
        local fg = nil
        for idx, group in ipairs(config.favorite_groups or {}) do
            if group.id == active_fg_id then
                fg = group
                break
            end
        end
        if fg and fg.buttons then
            local fav_visible = {}
            for idx, id in ipairs(fg.buttons) do
                if button_defs[id] then
                    table.insert(fav_visible, { id = id, def = button_defs[id] })
                end
            end
            
            local fav_row_entries = {}
            local current_entries = {}
            for i, entry in ipairs(fav_visible) do
                table.insert(current_entries, entry)
                if #current_entries == (config.fav_button_items_per_row or 8) then
                    table.insert(fav_row_entries, current_entries)
                    current_entries = {}
                end
            end
            if #current_entries > 0 then
                table.insert(fav_row_entries, current_entries)
            end
            for idx, entries in ipairs(fav_row_entries) do
                table.insert(fav_row_groups, makeRowGroup(entries))
            end
        end
    end

    local panel = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
    }


    for idx, r_group in ipairs(row_groups) do
        table.insert(panel, CenterContainer:new{
            dimen = Geom:new{ w = panel_width, h = r_group:getSize().h },
            r_group,
        })
        table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(8) })
    end
    
    if #fav_row_groups > 0 then
        table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        
        local inner_v_group = VerticalGroup:new{ align = "center" }
        table.insert(inner_v_group, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        
        for idx, r_group in ipairs(fav_row_groups) do
            table.insert(inner_v_group, CenterContainer:new{
                dimen = Geom:new{ w = panel_width - Screen:scaleBySize(24), h = r_group:getSize().h },
                r_group,
            })
            table.insert(inner_v_group, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        end
        
        local frame = FrameContainer:new{
            radius = Screen:scaleBySize(10),
            bordersize = Screen:scaleBySize(2),
            padding = Screen:scaleBySize(10),
            background = Blitbuffer.COLOR_GRAY_E,
            inner_v_group
        }
        
        table.insert(panel, frame)
    else
        if #fl_group > 0 then table.insert(panel, fl_group) end
        if #warmth_group > 0 then table.insert(panel, warmth_group) end
    end

    touch_menu._qs_refs = refs
    return panel
end

local function handlePanelGesture(touch_menu, ges, is_hold)
    local refs = touch_menu._qs_refs
    if not refs then return false end

    if not is_hold then
        for idx, sr in ipairs(refs.sliders or {}) do
            if sr.slider:handleTap(ges) then return true end
        end
    end



    for idx, btn_ref in ipairs(refs.buttons) do
        if btn_ref.widget.dimen and ges.pos:intersectWith(btn_ref.widget.dimen) then
            if is_hold and btn_ref.hold_callback then
                btn_ref.hold_callback()
                return true
            elseif not is_hold and btn_ref.callback then
                btn_ref.callback(touch_menu)
                return true
            end
            return true  -- swallow
        end
    end
    return false
end


local function getMaxButtons()
    return (config.row_count or 1) * (config.button_items_per_row or 8)
end

local function countEnabledButtons()
    local n = 0
    for idx, v in pairs(config.show_buttons) do
        if v then n = n + 1 end
    end
    return n
end

local function iconShortName(name)
    if not name then return "" end
    return name:gsub("^quick_", ""):gsub("^tab_", ""):gsub("^lookup_", "")
end

local function scanDispatcherActions()
    local ok_d, Dispatcher = pcall(require, "dispatcher")
    if not ok_d or not Dispatcher then return {} end
    pcall(function() Dispatcher:init() end)
    local settingsList, dispatcher_menu_order
    pcall(function()
        local fn_idx = 1
        while true do
            local name, val = debug.getupvalue(Dispatcher.registerAction, fn_idx)
            if not name then break end
            if name == "settingsList"          then settingsList          = val end
            if name == "dispatcher_menu_order" then dispatcher_menu_order = val end
            fn_idx = fn_idx + 1
        end
    end)
    if type(settingsList) ~= "table" then return {} end
    local order = (type(dispatcher_menu_order) == "table" and dispatcher_menu_order)
        or (function()
            local t = {}
            for k in pairs(settingsList) do t[#t+1] = k end
            table.sort(t)
            return t
        end)()
    local results = {}
    for _i, action_id in ipairs(order) do
        local def = settingsList[action_id]
        if type(def) == "table" and def.title and def.category == "none"
                and (def.condition == nil or def.condition == true) then
            results[#results + 1] = { id = action_id, title = tostring(def.title) }
        end
    end
    table.sort(results, function(a, b) return a.title < b.title end)
    return results
end


local function saveConfigAndRefresh()
    saveConfig()
end

local buildCustomButtonsList

local function buildCustomButtonSubItems(cb)
    if not config_backup then config_backup = deepcopy(config) end
    local T = require("ffi/util").template
    local InfoMessage = require("ui/widget/infomessage")
    local items = {}

    table.insert(items, {
        text = C_("✓ Save changes"),
        separator = true,
        callback = function()
            config_backup = nil
            saveConfig()
            UIManager:show(InfoMessage:new{
                text    = C_("Saved!"),
                timeout = 1.2,
            })
        end,
    })
    table.insert(items, {
        text = C_("← Discard"),
        separator = true,
        callback = function(tm)
            if config_backup then
                config = deepcopy(config_backup)
                _settings.data.config = config
                config_backup = nil
            end
            if tm and tm.item_table_stack and #tm.item_table_stack > 0 then
                table.remove(tm.item_table_stack)
                tm.item_table = buildCustomButtonsList()
                tm:updateItems(1)
            end
        end,
    })

    local ok_disp, Disp = pcall(require, "dispatcher")
    if ok_disp and Disp then
        local dispatch_items = {}
        local caller = setmetatable({}, {
            __newindex = function(t, k, v)
                if k == "updated" and v then
                    saveConfig()
                else
                    rawset(t, k, v)
                end
            end,
            __index = function() return nil end,
        })
        Disp:addSubMenu(caller, dispatch_items, cb, "action")
        table.insert(items, {
            text_func = function()
                local txt = C_("Action: None")
                if cb.action and next(cb.action) then
                    if cb.action.neo_menu_path then
                        -- Show the last element of the captured path as action name
                        local path = cb.action.neo_menu_path
                        local label = path[#path] or "?"
                        local arrow = cb.action.neo_is_submenu and " ▶" or ""
                        txt = T(C_("Action: %1"), _("Menu: ") .. label .. arrow)
                    else
                        txt = T(C_("Action: %1"), Disp:menuTextFunc(cb.action))
                    end
                end
                return txt
            end,
            sub_item_table_func = function()
                local sub = {}
                
                table.insert(sub, {
                    text = _("Select from KOReader menu (Capture Mode)"),
                    callback = function(tm)
                        NeoCaptureState.cb = cb
                        NeoCaptureState.path = {}
                        NeoCaptureState.active = true
                        tm:closeMenu()
                        if NeoQuickSettings and NeoQuickSettings.closeMenu then
                            NeoQuickSettings:closeMenu()
                        end
                        local main_ui = getMainUI()
                        if main_ui and main_ui.menu and main_ui.menu.onShowMenu then
                            UIManager:scheduleIn(0.5, function()
                                main_ui.menu:onShowMenu()
                            end)
                        end
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{ text = _("Navigate to your desired option and Long Press it!"), timeout = 4 })
                    end,
                })

                table.insert(sub, {
                    text = C_("Categorized (KOReader native)"),
                    sub_item_table = dispatch_items,
                    keep_menu_open = true,
                })
                
                local sys_actions = scanDispatcherActions()
                if #sys_actions > 0 then
                    local sys_items = {}
                    for idx, a in ipairs(sys_actions) do
                        table.insert(sys_items, {
                            text = a.title,
                            checked_func = function()
                                return cb.action and cb.action[a.id] == true
                            end,
                            callback = function()
                                cb.action = { [a.id] = true }
                                local InfoMessage = require("ui/widget/infomessage")
                                UIManager:show(InfoMessage:new{ text = C_("Saved!"), timeout = 1 })
                            end,
                        })
                    end
                    table.insert(sub, {
                        text = C_("System Actions (SimpleUI style)"),
                        sub_item_table = sys_items,
                        keep_menu_open = true,
                    })
                end
                
                table.insert(sub, {
                    text = C_("Clear action"),
                    separator = true,
                    callback = function()
                        cb.action = nil
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{ text = C_("Action cleared!"), timeout = 1 })
                    end,
                })
                
                return sub
            end,
            keep_menu_open = true,
        })
    end

    table.insert(items, {
        text_func = function()
            return T(C_("Icon: %1"), iconShortName(cb.icon or ("button")))
        end,
        keep_menu_open = true,
        callback = function(tm)
            if showIconPickerDialog and _plugin_root then
                local icon_list = utils.getIconPickerList(_plugin_root)
                if #icon_list > 0 then
                    showIconPickerDialog(_plugin_root, icon_list, cb.icon, function(name)
                        cb.icon = name
                        if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
                    end)
                    return
                end
            end
            UIManager:show(require("ui/widget/infomessage"):new{
                text = (icon_picker_err ~= "") and ("Error: " .. icon_picker_err) or C_("No icons found."), timeout = 5,
            })
        end,
    })
    table.insert(items, {
        text_func = function()
            local lbl = (cb.label and cb.label ~= "") and cb.label or C_("(auto)")
            return T(C_("Label: %1"), lbl)
        end,
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local dialog
            dialog = InputDialog:new{
                title       = C_("Button label"),
                input       = cb.label or "",
                input_hint  = C_("Leave empty to use action title"),
                buttons = {{
                    { text = C_("Cancel"), callback = function() UIManager:close(dialog) end },
                    {
                        text = C_("Set"),
                        is_enter_default = true,
                        callback = function()
                            local txt = dialog:getInputText()
                            cb.label = (txt and txt ~= "") and txt or nil
                            UIManager:close(dialog)
                        end,
                    },
                }},
            }
            UIManager:show(dialog)
        end,
    })

    table.insert(items, {
        text = _("Visible in Quick Settings"),
        checked_func = function() return config.show_buttons[cb.id] == true end,
        ios_toggle = true,
        keep_menu_open = true,
        callback = function(tm)
            config.show_buttons[cb.id] = not config.show_buttons[cb.id]
            saveConfigAndRefresh()
            if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
        end,
    })

    table.insert(items, {
        text = C_("Export to SimpleUI"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            local ok, SUIConfig = pcall(require, "infra/sui_config")
            if not ok then ok, SUIConfig = pcall(require, "sui_config") end
            if ok and SUIConfig then
                local InfoMessage = require("ui/widget/infomessage")
                local new_id = SUIConfig.nextCustomQAId()
                local list = SUIConfig.getCustomQAList()
                table.insert(list, new_id)
                SUIConfig.saveCustomQAList(list)
                
                local da_action = nil
                if cb.action then
                    for k, v in pairs(cb.action) do
                        if v then da_action = k; break end
                    end
                end
                
                local final_label = cb.label
                if not final_label or final_label == "" then
                    if cb.action and next(cb.action) then
                        local ok_d, Disp = pcall(require, "dispatcher")
                        if ok_d then final_label = Disp:menuTextFunc(cb.action) end
                    end
                end
                if not final_label or final_label == "" then final_label = C_("Exported Action") end
                
                local final_icon = cb.icon
                if final_icon then
                    local ok_qa, QA = pcall(require, "features/sui_quickactions")
                    if not ok_qa then ok_qa, QA = pcall(require, "sui_quickactions") end
                    if ok_qa and QA and QA.getIconsDir then
                        local dest_dir = QA.getIconsDir()
                        local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
                        if ok_lfs and lfs and lfs.attributes(dest_dir, "mode") == "directory" then
                            local src_path = final_icon
                            if not string.find(src_path, "/") then
                                src_path = utils.resolveIcon(_icons_dir, final_icon)
                            end
                            if src_path and lfs.attributes(src_path, "mode") == "file" then
                                local fname = src_path:match("([^/]+)$") or final_icon
                                if not fname:match("%.svg$") and not fname:match("%.png$") then
                                    fname = fname .. ".svg"
                                end
                                local dest_path = dest_dir .. "/" .. fname
                                local f_in = io.open(src_path, "rb")
                                if f_in then
                                    local content = f_in:read("*a")
                                    f_in:close()
                                    local f_out = io.open(dest_path, "wb")
                                    if f_out then
                                        f_out:write(content)
                                        f_out:close()
                                        final_icon = dest_path
                                    end
                                end
                            end
                        end
                    end
                end
                
                SUIConfig.saveCustomQAConfig(new_id, final_label, nil, nil, final_icon, nil, nil, da_action)
                
                local ok_qa, QA = pcall(require, "features/sui_quickactions")
                if not ok_qa then ok_qa, QA = pcall(require, "sui_quickactions") end
                if ok_qa and QA and QA.invalidateCustomQACache then QA.invalidateCustomQACache() end
                
                local plugin = package.loaded["simpleui"]
                if plugin and plugin._rebuildAllNavbars then plugin:_rebuildAllNavbars() end
                
                local ok_hs, HS = pcall(require, "screens/sui_homescreen")
                if not ok_hs then ok_hs, HS = pcall(require, "sui_homescreen") end
                if ok_hs and HS and HS._instance and type(HS._instance._refreshImmediate) == "function" then HS._instance:_refreshImmediate(false) end

                UIManager:show(InfoMessage:new{ text = C_("Successfully exported to SimpleUI!"), timeout = 2 })
            else
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = C_("SimpleUI plugin not found or not active."), timeout = 2 })
            end
        end,
    })

    table.insert(items, {
        text = _("Convert to Fixed Button"),
        separator = true,
        callback = function(tm)
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                            text = _("Are you sure you want to convert this custom button to a fixed button?\n\nIt will be moved from the custom buttons menu to the fixed buttons list."),
                ok_text = C_("Yes"),
                cancel_text = C_("Cancel"),
                ok_callback = function()
                    table.insert(config.user_builtin_buttons, cb)
                    local new_customs = {}
                    for idx, cbtn in ipairs(config.custom_buttons) do
                        if cbtn.id ~= cb.id then table.insert(new_customs, cbtn) end
                    end
                    config.custom_buttons = new_customs
                    
                    local new_order = {}
                    for idx, id in ipairs(config.button_order) do
                        if id ~= cb.id then table.insert(new_order, id) end
                    end
                    table.insert(new_order, cb.id)
                    config.button_order = new_order
                    
                    saveConfigAndRefresh()
                end,
            })
        end,
    })

    table.insert(items, {
        text      = C_("Remove this button"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            for i = #config.custom_buttons, 1, -1 do
                if config.custom_buttons[i].id == cb.id then
                    table.remove(config.custom_buttons, i)
                    break
                end
            end
            config.show_buttons[cb.id] = nil
            button_defs[cb.id]         = nil
            local new_order = {}
            for idx, id in ipairs(config.button_order) do
                if id ~= cb.id then table.insert(new_order, id) end
            end
            config.button_order = new_order
            saveConfig()
            UIManager:show(require("ui/widget/infomessage"):new{
                text = C_("Button removed."), timeout = 2,
            })
            if tm and tm.item_table_stack and #tm.item_table_stack > 0 then
                tm.item_table_stack[#tm.item_table_stack] = buildCustomButtonsList()
            end
            if tm and tm.backToUpperMenu then tm:backToUpperMenu() end
        end,
    })

    return items
end

local buildFavoriteGroupEditor
local buildFavoriteGroupsManager

buildFavoriteGroupEditor = function(fg)
    if not config_backup then config_backup = deepcopy(config) end
    local items = {}
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")
    table.insert(items, {
        text = _("✓ Save changes"),
        separator = true,
        callback = function()
            config_backup = nil
            saveConfigAndRefresh()
            UIManager:show(InfoMessage:new{
                text    = _("Saved!"),
                timeout = 1.2,
            })
        end,
    })
    table.insert(items, {
        text = _("← Discard"),
        separator = true,
        callback = function(tm)
            if config_backup then
                config = deepcopy(config_backup)
                _settings.data.config = config
                config_backup = nil
            end
            if tm and tm.item_table_stack and #tm.item_table_stack > 0 then
                table.remove(tm.item_table_stack)
                tm.item_table = buildFavoriteGroupsManager()
                tm:updateItems(1)
            end
        end,
    })

    
    table.insert(items, {
        text_func = function() return _("Name: ") .. (fg.label or C_("Favorite")) end,
        keep_menu_open = true,
        callback = function(tm)
            local dialog
            dialog = InputDialog:new{
                title = _("Enter Button Name"),
                input = fg.label or "",
                buttons = {{
                    {
                        text = C_("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dialog) end,
                    },
                    {
                        text = C_("Save"),
                        callback = function()
                            fg.label = dialog:getInputText()
                            if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
                            UIManager:close(dialog)
                        end,
                    },
                }},
            }
            UIManager:show(dialog)
        end,
    })



    table.insert(items, {
        text_func = function() return _("Icon: ") .. (fg.icon or ("button")) end,
        keep_menu_open = true,
        callback = function(tm)
            if showIconPickerDialog and _plugin_root then
                local icon_list = utils.getIconPickerList(_plugin_root)
                if #icon_list > 0 then
                    showIconPickerDialog(_plugin_root, icon_list, fg.icon, function(icon_name)
                        fg.icon = icon_name
                        if config.custom_builtin_icons then config.custom_builtin_icons[fg.id] = nil end
                        if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
                    end)
                    return
                end
            end
            UIManager:show(InfoMessage:new{ text = (icon_picker_err ~= "") and ("Error: " .. icon_picker_err) or "Icon manager not found.", timeout = 2 })
        end,
    })

    table.insert(items, {
        text = _("Visible in Quick Settings"),
        checked_func = function() return config.show_buttons[fg.id] == true end,
        ios_toggle = true,
        keep_menu_open = true,
        callback = function(tm)
            config.show_buttons[fg.id] = not config.show_buttons[fg.id]
            saveConfigAndRefresh()
            if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
        end,
    })

    table.insert(items, {
        text = _("Add/Remove Buttons"),
        separator = true,
        sub_item_table_func = function()
            local btn_items = {}
            if not fg.buttons then fg.buttons = {} end
            
            local function hasButton(id)
                for idx, b in ipairs(fg.buttons) do
                    if b == id then return true end
                end
                return false
            end
            
            local function toggleButton(id)
                if hasButton(id) then
                    for i, b in ipairs(fg.buttons) do
                        if b == id then table.remove(fg.buttons, i); break end
                    end
                else
                    table.insert(fg.buttons, id)
                end
            end
            
            local all_available = {}
            for k, def in pairs(button_defs) do
                if k ~= "settings" and not k:match("^favgrp_") then
                    table.insert(all_available, { id = k, label = def.label or k })
                end
            end
            table.sort(all_available, function(a, b) return a.label < b.label end)
            
            for idx, btn in ipairs(all_available) do
                table.insert(btn_items, {
                    text = btn.label,
            checked_func = function() return hasButton(btn.id) end,
        ios_toggle = true,
        keep_menu_open = true,
                    callback = function(tm)
                        toggleButton(btn.id)
                        if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
                    end,
                })
            end
            return btn_items
        end,
    })

    table.insert(items, {
        text = _("Change Order (Drag & Drop)"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            if not fg.buttons or #fg.buttons == 0 then
                UIManager:show(require("ui/widget/infomessage"):new{ text = _("No buttons added yet."), timeout = 2 })
                return
            end
            local SortWidget = require("ui/widget/sortwidget")
            local sort_items = {}
            for idx, id in ipairs(fg.buttons) do
                local label = id
                if button_defs[id] and button_defs[id].label then
                    label = button_defs[id].label
                end
                table.insert(sort_items, { text = label, key = id })
            end
            UIManager:show(SortWidget:new{
                title = C_("Arrange buttons"),
                item_table = sort_items,
                callback = function()
                    local new_order = {}
                    for idx, v in ipairs(sort_items) do
                        table.insert(new_order, v.key)
                    end
                    fg.buttons = new_order
                    saveConfigAndRefresh()
                end
            })
        end,
    })

    table.insert(items, {
        text = _("Delete this Favorite Button"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to delete this favorite button?"),
                ok_text = _("Yes, Delete"),
                cancel_text = C_("Cancel"),
                ok_callback = function()
                    for i, grp in ipairs(config.favorite_groups) do
                        if grp.id == fg.id then
                            table.remove(config.favorite_groups, i)
                            break
                        end
                    end
                    config.show_buttons[fg.id] = nil
                    button_defs[fg.id] = nil
                    local new_order = {}
                    for idx, id in ipairs(config.button_order) do
                        if id ~= fg.id then table.insert(new_order, id) end
                    end
                    config.button_order = new_order
                    
                    saveConfigAndRefresh()
                    
                    if tm and tm.item_table_stack and #tm.item_table_stack > 0 then
                        tm.item_table_stack[#tm.item_table_stack] = buildFavoriteGroupsManager()
                    end
                    if tm and tm.backToUpperMenu then tm:backToUpperMenu() end
                end,
            })
        end,
    })

    return items
end

buildFavoriteGroupsManager = function()
    local items = {}

    table.insert(items, {
        text = _("Buttons Per Row for Favorites"),
        sub_item_table_func = function()
            local inner_items = {}
            for i = 4, 10 do
                table.insert(inner_items, {
                    text = tostring(i) .. " Buttons",
                    checked_func = function() return (config.fav_button_items_per_row or 8) == i end,
                    callback = function()
                        config.fav_button_items_per_row = i
                        saveConfigAndRefresh()
                    end,
                })
            end
            return inner_items
        end,
    })


    table.insert(items, {
        text = _("Create New Favorite Menu"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            config.next_fav_id = (config.next_fav_id or 0) + 1
            local new_fg = {
                id = "favgrp_" .. tostring(config.next_fav_id),
                label = "New Favorite " .. tostring(config.next_fav_id),
                title = _("Favorite Buttons"),
                icon = "button",
                buttons = {},
            }
            if not config.favorite_groups then config.favorite_groups = {} end
            table.insert(config.favorite_groups, new_fg)
            table.insert(config.button_order, new_fg.id)
            config.show_buttons[new_fg.id] = true
            
            if tm and tm.item_table_stack then
                table.insert(tm.item_table_stack, tm.item_table)
                tm.item_table = buildFavoriteGroupEditor(new_fg)
                tm:updateItems(1)
            end
        end,
    })

    if config.favorite_groups then
        for idx, fg in ipairs(config.favorite_groups) do
            table.insert(items, {
                text_func = function()
                    return fg.label or fg.id
                end,
                sub_item_table_func = function()
                    return buildFavoriteGroupEditor(fg)
                end,
            })
        end
    end

    return items
end


buildCustomButtonsList = function()
    local items = {}

    table.insert(items, {
        text = C_("Add custom button"),
        keep_menu_open = true,
        callback = function(tm)
            if not config_backup then config_backup = deepcopy(config) end
            config.next_custom_id = (config.next_custom_id or 0) + 1
            local btn_id = "cb_" .. tostring(config.next_custom_id)
            local new_cb = {
                id     = btn_id,
                label  = nil,
                icon   = "button",
                action = {},
            }
            table.insert(config.custom_buttons, new_cb)
            config.show_buttons[btn_id] = true
            table.insert(config.button_order, btn_id)
            if tm then
                tm.item_table = buildCustomButtonsList()
                local sub = buildCustomButtonSubItems(new_cb)
                if #sub > 0 then
                    table.insert(tm.item_table_stack, tm.item_table)
                    tm.item_table = sub
                    tm:updateItems(1)
                end
            end
        end,
    })

    for idx, cb in ipairs(config.custom_buttons) do
        local cb_ref = cb
        table.insert(items, {
            text_func = function()
                if cb_ref.label and cb_ref.label ~= "" then return cb_ref.label end
                if cb_ref.action and next(cb_ref.action) then
                    local ok_d, D = pcall(require, "dispatcher")
                    if ok_d then return D:menuTextFunc(cb_ref.action) end
                end
                return C_("Custom button")
            end,
            keep_menu_open = true,
            sub_item_table_func = function()
                return buildCustomButtonSubItems(cb_ref)
            end,
        })
    end

    return items
end

buildSettingsMenuItems = function()
    local T = require("ffi/util").template  -- luacheck: ignore

    local builtin_buttons = {
        { key = "wifi",       label = C_("Wi-Fi") },
        { key = "night",      label = C_("Night Mode") },
        { key = "rotate",     label = C_("Rotate") },
        { key = "sleep",      label = C_("Sleep") },
        { key = "restart",    label = C_("Restart") },
        { key = "exit",       label = C_("Exit") },
        { key = "search",     label = C_("Search") },
        { key = "screenshot", label = C_("Screenshot") },
        { key = "kosync",     label = C_("KOSync") },
        { key = "bluetooth",  label = C_("Bluetooth") },
        { key = "filebrowserplus", label = C_("FileBrowser+") },
        { key = "ssh",        label = C_("SSH") },
        { key = "streak",     label = C_("Streak") },
        { key = "opds",       label = C_("OPDS") },
        { key = "stats_progress", label = C_("Progress") },
        { key = "stats_calendar", label = C_("Calendar") },
        { key = "battery_stats",  label = C_("Battery") },
        { key = "localsend",  label = C_("LocalSend") },
        { key = "bookfusion", label = C_("BookFusion") },
        { key = "focus",      label = C_("Focus") },
        { key = "read_goal_time",  label = C_("Time Goal") },
        { key = "read_goal_pages", label = C_("Page Goal") },
        { key = "settings",   label = C_("Settings") },
    }
    if config.user_builtin_buttons then
        for idx, ub in ipairs(config.user_builtin_buttons) do
            table.insert(builtin_buttons, { key = ub.id, label = ub.label or C_("Custom"), is_user_builtin = true })
        end
    end
    if config.favorite_groups then
        for idx, fg in ipairs(config.favorite_groups) do
            table.insert(builtin_buttons, { key = fg.id, label = fg.label or C_("Favorite"), is_favorite_group = true })
        end
    end

    local function getButtonLabel(id)
        if config.custom_builtin_labels and config.custom_builtin_labels[id] and config.custom_builtin_labels[id] ~= "" then
            return config.custom_builtin_labels[id]
        end
        if button_defs and button_defs[id] then
            local def = button_defs[id]
            if def.label_func then return def.label_func() end
            if def.label then return def.label end
        end
        for idx, cb in ipairs(config.custom_buttons) do
            if cb.id == id then
                if cb.label and cb.label ~= "" then return cb.label end
                if cb.action and next(cb.action) then
                    local ok, D = pcall(require, "dispatcher")
                    if ok then return D:menuTextFunc(cb.action) end
                end
                return C_("Custom button")
            end
        end
        return id
    end

    local button_toggle_items = {}
    for idx, btn in ipairs(builtin_buttons) do
        local key = btn.key
        table.insert(button_toggle_items, {
            text = btn.label,
            checked_func = function() return config.show_buttons[key] == true end,
            enabled_func = function()
                return config.show_buttons[key] == true
                    or countEnabledButtons() < getMaxButtons()
            end,
            ios_toggle = true,
            keep_menu_open = true,
            callback = function()
                config.show_buttons[key] = not config.show_buttons[key]
                saveConfigAndRefresh()
            end,
        })
    end

    for idx, cb in ipairs(config.custom_buttons) do
        local key = cb.id
        table.insert(button_toggle_items, {
            text_func = function()
                return getButtonLabel(key)
            end,
            checked_func = function() return config.show_buttons[key] == true end,
            enabled_func = function()
                return config.show_buttons[key] == true
                    or countEnabledButtons() < getMaxButtons()
            end,
            ios_toggle = true,
            keep_menu_open = true,
            callback = function()
                config.show_buttons[key] = not config.show_buttons[key]
                saveConfigAndRefresh()
            end,
        })
    end

    local function iconShortName(name)
        if not name then return "" end
        return name:match("([^/]+)$") or name
    end

    local function buildBuiltinButtonEditor()
        local T = require("ffi/util").template
        local items = {}
        for idx, btn in ipairs(builtin_buttons) do
            local key = btn.key
            table.insert(items, {
                text_func = function()
                    local clabel = (config.custom_builtin_labels and config.custom_builtin_labels[key]) or btn.label
                    local cicon = (config.custom_builtin_icons and config.custom_builtin_icons[key]) or key
                    return T(_("%1 (Icon: %2)"), clabel, iconShortName(cicon))
                end,
                keep_menu_open = true,
                sub_item_table_func = function()
                    local sub = {}
                    table.insert(sub, {
                        text = _("Change Name"),
                        callback = function(tm)
                            local InputDialog = require("ui/widget/inputdialog")
                            local current_label = (config.custom_builtin_labels and config.custom_builtin_labels[key]) or btn.label
                            local dialog
                            dialog = InputDialog:new{
                                title = T(_("Rename: %1"), btn.label),
                                input = current_label,
                                buttons = {{
                                    { text = C_("Cancel"), callback = function() UIManager:close(dialog) end },
                                    {
                                        text = C_("Reset"),
                                        callback = function()
                                            if config.custom_builtin_labels then config.custom_builtin_labels[key] = nil end
                                            saveConfigAndRefresh()
                                            UIManager:close(dialog)
                                        end,
                                    },
                                    {
                                        text = C_("Save"),
                                        is_enter_default = true,
                                        callback = function()
                                            local text = dialog:getInputText()
                                            if text and text ~= "" then
                                                if not config.custom_builtin_labels then config.custom_builtin_labels = {} end
                                                config.custom_builtin_labels[key] = text
                                            else
                                                if config.custom_builtin_labels then config.custom_builtin_labels[key] = nil end
                                            end
                                            saveConfigAndRefresh()
                                            UIManager:close(dialog)
                                        end,
                                    },
                                }},
                            }
                            UIManager:show(dialog)
                            dialog:onShowKeyboard()
                        end
                    })
                    table.insert(sub, {
                        text = _("Change Icon"),
                        keep_menu_open = true,
                        callback = function(tm)
                            if showIconPickerDialog and _plugin_root then
                                local icon_list = utils.getIconPickerList(_plugin_root)
                                if #icon_list > 0 then
                                    local current_icon = (config.custom_builtin_icons and config.custom_builtin_icons[key]) or key
                                    showIconPickerDialog(_plugin_root, icon_list, current_icon, function(new_icon)
                                        if not config.custom_builtin_icons then config.custom_builtin_icons = {} end
                                        config.custom_builtin_icons[key] = new_icon
                                        saveConfigAndRefresh()
                                    end)
                                    return
                                end
                            end
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = (icon_picker_err ~= "") and ("Error: " .. icon_picker_err) or C_("No icons found."), timeout = 5,
                            })
                        end
                    })
                    if btn.is_user_builtin then
                        table.insert(sub, {
                    text = _("Delete this Built-in Button"),
                            separator = true,
                            callback = function(tm)
                                local ConfirmBox = require("ui/widget/confirmbox")
                                UIManager:show(ConfirmBox:new{
                                    text = _("Are you sure you want to completely delete this built-in button?"),
                                    ok_text = _("Yes, Delete"),
                                    cancel_text = C_("Cancel"),
                                    ok_callback = function()
                                        local new_user_builtin = {}
                                        for idx, ub in ipairs(config.user_builtin_buttons or {}) do
                                            if ub.id ~= key then table.insert(new_user_builtin, ub) end
                                        end
                                        config.user_builtin_buttons = new_user_builtin
                                        
                                        config.show_buttons[key] = nil
                                        
                                        local new_order = {}
                                        for idx, id in ipairs(config.button_order) do
                                            if id ~= key then table.insert(new_order, id) end
                                        end
                                        config.button_order = new_order
                                        
                                        if config.custom_builtin_labels then config.custom_builtin_labels[key] = nil end
                                        if config.custom_builtin_icons then config.custom_builtin_icons[key] = nil end
                                        
                                        saveConfigAndRefresh()
                                        if tm and tm.item_table_stack and #tm.item_table_stack > 0 then
                                            tm.item_table_stack[#tm.item_table_stack] = buildBuiltinButtonEditor()
                                        end
                                        if tm and tm.backToUpperMenu then tm:backToUpperMenu() end
                                    end,
                                })
                            end
                        })
                    end
                    return sub
                end
            })
        end
        table.insert(items, {
            text = _("Reset All Names and Icons"),
            separator = true,
            callback = function(tm)
                config.custom_builtin_labels = {}
                config.custom_builtin_icons = {}
                saveConfigAndRefresh()
            end,
        })
        return items
    end

        local buttons_section = {
        { text = _("Edit"), is_label = true, separator = true, enabled = false },
        {
            text = _("Add/Remove Buttons"),
            sub_item_table_func = function()
            return {
                
                
                    {
                        text = _("Show / Hide Buttons"),
                        sub_item_table_func = function()
                            return button_toggle_items
                        end
                    },
                    {
                        text = _("Show Min/Max Buttons (Brightness/Warmth)"), 
                        checked_func = function() return config.show_minmax_buttons ~= false end, 
                        ios_toggle = true, 
                        callback = function() config.show_minmax_buttons = (config.show_minmax_buttons == false) saveConfigAndRefresh() end 
                    },
                    {
                        text = _("Change Order (Drag & Drop)"),
                        callback = function(tm)
                            local SortWidget = require("ui/widget/sortwidget")
                            local items = {}
                            for idx, id in ipairs(config.button_order) do
                                if config.show_buttons[id] then
                                    table.insert(items, { text = getButtonLabel(id), key = id })
                                end
                            end
                            UIManager:show(SortWidget:new{
                                title = C_("Arrange buttons"),
                                item_table = items,
                                callback = function()
                                    local new_order = {}
                                    local seen = {}
                                    for idx, v in ipairs(items) do
                                        table.insert(new_order, v.key)
                                        seen[v.key] = true
                                    end
                                    for idx, id in ipairs(config.button_order) do
                                        if not seen[id] then table.insert(new_order, id) end
                                    end
                                    config.button_order = new_order
                                    saveConfig()
                                end
                            })
                        end
                    }
                }
            end
        },
        {
            text = _("Edit Built-in Buttons"),
            sub_item_table_func = function()
                return buildBuiltinButtonEditor()
            end
        },
        { text = _("Add / Remove"), is_label = true, separator = true, enabled = false },
        {
            text = _("Add / Manage Custom Buttons"),
            sub_item_table_func = function()
                return buildCustomButtonsList()
            end
        },
        {
            text = _("Add / Manage Favorite Buttons"),
            sub_item_table_func = function()
                return buildFavoriteGroupsManager()
            end
        },
        { text = _("Appearance Options"), is_label = true, separator = true, enabled = false },
        {
            text = _("Button Appearance Options"),
            sub_item_table_func = function()
            return {
                
                
                    {
                        text = _("Buttons Per Row"),
                        sub_item_table_func = function()
                            local items = {}
                            for i = 4, 10 do
                                table.insert(items, {
                                    text = tostring(i) .. " Buttons",
                                    checked_func = function() return (config.button_items_per_row or 8) == i end,
                                    callback = function()
                                        config.button_items_per_row = i
                                        saveConfigAndRefresh()
                                    end,
                                })
                            end
                            return items
                        end,
                    },
                    {
                        text = _("Button Rows"),
                        sub_item_table_func = function()
                            local items = {}
                            for i = 1, 4 do
                                table.insert(items, {
                                    text = tostring(i) .. " Rows",
                                    checked_func = function() return (config.row_count or 1) == i end,
                                    callback = function()
                                        if i < (config.row_count or 1) then
                                            local max_allowed_buttons = i * (config.button_items_per_row or 8)
                                            if countEnabledButtons() > max_allowed_buttons then
                                                local InfoMessage = require("ui/widget/infomessage")
                                                UIManager:show(InfoMessage:new{ text = "You must hide some buttons first to switch to this row count (Max " .. max_allowed_buttons .. " buttons)." })
                                                return
                                            end
                                        end
                                        config.row_count = i
                                        saveConfigAndRefresh()
                                    end,
                                })
                            end
                            return items
                        end,
                    },
                    {
                        text = C_("Icon size"),
                        sub_item_table_func = function()
            return {
                
                
                                { text = C_("1 (Small)"), checked_func = function() return (config.icon_scale_level or 1) == 1 end, callback = function() config.icon_scale_level = 1; saveConfig() end },
                                { text = C_("2 (Medium)"), checked_func = function() return config.icon_scale_level == 2 end, callback = function() config.icon_scale_level = 2; saveConfig() end },
                                { text = C_("3 (Large)"), checked_func = function() return config.icon_scale_level == 3 end, callback = function() config.icon_scale_level = 3; saveConfig() end },
                            }
                        end,
                    },
                    {
                        text = C_("Button style"),
                        sub_item_table_func = function()
            return {
                
                
                                { text = C_("Circle"), checked_func = function() return config.button_style == "circle" end, callback = function() config.button_style = "circle"; saveConfig() end },
                                { text = C_("Rounded square"), checked_func = function() return config.button_style == "rounded_square" end, callback = function() config.button_style = "rounded_square"; saveConfig() end },
                                { text = C_("Borderless"), checked_func = function() return config.button_style == "borderless" end, callback = function() config.button_style = "borderless"; saveConfig() end },
                            }
                        end,
                    },
                    {
                        text = C_("Label size"),
                        sub_item_table_func = function()
                            local items = {}
                            for i = 1, 7 do
                                local label = tostring(i)
                                if i == 5 then label = label .. " (" .. C_("Default") .. ")" end
                                table.insert(items, {
                                    text = label,
                                    checked_func = function()
                                        local val = config.label_size
                                        if val == "normal" or val == nil then val = 5 end
                                        if val == "small" then val = 3 end
                                        if val == "large" then val = 7 end
                                        return val == i
                                    end,
                                    callback = function() config.label_size = i; saveConfig() end,
                                })
                            end
                            table.insert(items, { text = C_("Hidden"), checked_func = function() return config.label_size == "hidden" end, callback = function() config.label_size = "hidden"; saveConfig() end })

                            return items
                        end,
                    },
                }
            end,
        },
                {
            text = _("Icon Manager"),
            keep_menu_open = true,
            callback = function(tm)
                local showIconPickerDialog = require("common/neo_icon_picker")
                local utils = require("common/utils")
                if showIconPickerDialog and _plugin_root then
                    local icon_list = utils.getIconPickerList(_plugin_root)
                    showIconPickerDialog(_plugin_root, icon_list, nil, function(icon_path)
                        local assign_items = {}
                        local InfoMessage = require("ui/widget/infomessage")
                        local Menu = require("ui/widget/menu")
                        
                        -- Custom Buttons
                        for idx, cb in ipairs(config.custom_buttons or {}) do
                            table.insert(assign_items, {
                                text = _("Custom: ") .. getButtonLabel(cb.id),
                                callback = function()
                                    cb.icon = icon_path
                                    saveConfigAndRefresh()
                                    UIManager:show(InfoMessage:new{ text = _("Icon applied!"), timeout = 2 })
                                end,
                            })
                        end
                        -- Favorite Groups
                        for idx, fg in ipairs(config.favorite_groups or {}) do
                            table.insert(assign_items, {
                                text = _("Favorite: ") .. getButtonLabel(fg.id),
                                callback = function()
                                    fg.icon = icon_path
                                    if config.custom_builtin_icons then
                                        config.custom_builtin_icons[fg.id] = nil
                                    end
                                    saveConfigAndRefresh()
                                    UIManager:show(InfoMessage:new{ text = _("Icon applied!"), timeout = 2 })
                                end,
                            })
                        end
                        -- Built-in
                        for idx, btn in ipairs(builtin_buttons or {}) do
                            if not btn.is_favorite_group then
                                table.insert(assign_items, {
                                    text = _("Built-in: ") .. getButtonLabel(btn.key),
                                    callback = function()
                                        if not config.custom_builtin_icons then config.custom_builtin_icons = {} end
                                        config.custom_builtin_icons[btn.key] = icon_path
                                        saveConfigAndRefresh()
                                        UIManager:show(InfoMessage:new{ text = _("Icon applied!"), timeout = 2 })
                                    end,
                                })
                            end
                        end
                        
                        if #assign_items == 0 then
                            UIManager:show(InfoMessage:new{ text = _("No buttons available."), timeout = 2 })
                            return
                        end
                        
                        local Screen = require("device").screen
                        local sw, sh = Screen:getWidth(), Screen:getHeight()
                        local assign_menu
                        assign_menu = Menu:new{
                            title = _("Assign Icon To:"),
                            width = math.floor(sw * 0.7),
                            height = math.floor(sh * 0.7),
                            is_popout = true,
                            item_table = assign_items,
                            onMenuChoice = function(_menu_inst, item)
                                UIManager:close(assign_menu.wrapper)
                                if item.callback then item.callback() end
                            end,
                        }
                        
                        local CenterContainer = require("ui/widget/container/centercontainer")
                        local MovableContainer = require("ui/widget/container/movablecontainer")
                        
                        local movable = MovableContainer:new{
                            unmovable = true,
                            assign_menu
                        }
                        
                        local wrapper = CenterContainer:new{
                            dimen = Geom:new{ w = sw, h = sh },
                            movable
                        }
                        assign_menu.wrapper = wrapper
                        assign_menu.show_parent = wrapper -- Required for pagination redraws
                        
                        -- Close wrapper instead of menu when tapping outside or pressing X
                        assign_menu.onTapCloseAllMenus = function(self, arg, ges_ev)
                            if ges_ev.pos:notIntersectWith(self.dimen) then
                                UIManager:close(self.wrapper)
                                return true
                            end
                        end
                        assign_menu.onClose = function(self)
                            UIManager:close(self.wrapper)
                        end
                        
                        local Size = require("ui/size")
                        if assign_menu[1] then assign_menu[1].radius = Size.radius.window end
                        UIManager:show(wrapper)
                    end)
                end
            end,
        },
    }

    local slider_items = {}
    table.insert(slider_items, {
        text = _("Slider Style"),
        sub_item_table_func = function()
            return {
                
                
                { text = _("Neo (Rounded Knob)"), checked_func = function() return (config.slider_style or "neo") == "neo" end, callback = function() config.slider_style = "neo"; saveConfigAndRefresh() end },
                { text = _("Progress Bar"), checked_func = function() return config.slider_style == "progress_bar" end, callback = function() config.slider_style = "progress_bar"; saveConfigAndRefresh() end },
                { text = _("Notched Bar"), checked_func = function() return config.slider_style == "notched" end, callback = function() config.slider_style = "notched"; saveConfigAndRefresh() end },
                            { text = _("Square Notched"), checked_func = function() return config.slider_style == "square_notched" end, callback = function() config.slider_style = "square_notched"; saveConfigAndRefresh() end },
                            { text = _("Outline"), checked_func = function() return config.slider_style == "outline" end, callback = function() config.slider_style = "outline"; saveConfigAndRefresh() end },
                            { text = _("Fader"), checked_func = function() return config.slider_style == "fader" end, callback = function() config.slider_style = "fader"; saveConfigAndRefresh() end },
                            { text = _("Dots"), checked_func = function() return config.slider_style == "dots" end, callback = function() config.slider_style = "dots"; saveConfigAndRefresh() end },
                            { text = _("Cyber Bar"), checked_func = function() return config.slider_style == "cyber" end, callback = function() config.slider_style = "cyber"; saveConfigAndRefresh() end },
                            { text = _("Retro Switch"), checked_func = function() return config.slider_style == "retro" end, callback = function() config.slider_style = "retro"; saveConfigAndRefresh() end },
                            { text = _("Split Rail"), checked_func = function() return config.slider_style == "split_rail" end, callback = function() config.slider_style = "split_rail"; saveConfigAndRefresh() end },
                            { text = _("Stepped Bars"), checked_func = function() return config.slider_style == "stepped_bars" end, callback = function() config.slider_style = "stepped_bars"; saveConfigAndRefresh() end },
                            { text = _("Fluid Pill"), checked_func = function() return config.slider_style == "fluid_pill" end, callback = function() config.slider_style = "fluid_pill"; saveConfigAndRefresh() end },
                            { text = _("Battery Indicator"), checked_func = function() return config.slider_style == "battery" end, callback = function() config.slider_style = "battery"; saveConfigAndRefresh() end },
                            { text = _("Pearls"), checked_func = function() return config.slider_style == "pearls" end, callback = function() config.slider_style = "pearls"; saveConfigAndRefresh() end },
                            { text = _("Piano Keys"), checked_func = function() return config.slider_style == "piano" end, callback = function() config.slider_style = "piano"; saveConfigAndRefresh() end },
            }
        end,
    })

        table.insert(slider_items, {
        text = _("Language"),
        sub_item_table_func = function()
            local items = {
                { text = _("System Language"), checked_func = function() return (not config.plugin_language or config.plugin_language == "system") end, callback = function() config.plugin_language = "system"; saveConfigAndRefresh(); require("ui/uimanager"):show(require("ui/widget/infomessage"):new{text=_("Please restart KOReader to apply language changes"), timeout=3}) end }
            }
            local langs = {
                {"en", "English"}, {"tr", "Türkçe"}, {"es", "Español"}, {"fr", "Français"}, {"de", "Deutsch"},
                {"it", "Italiano"}, {"ru", "Русский"}, {"ja", "日本語"}, {"zh_CN", "简体中文"}, {"pt_BR", "Português (Brasil)"},
                {"ko", "한국어"}, {"ar", "العربية"}, {"hi", "हिन्दी"}
            }
            for idx, lang in ipairs(langs) do
                table.insert(items, { text = lang[2], checked_func = function() return config.plugin_language == lang[1] end, callback = function() config.plugin_language = lang[1]; saveConfigAndRefresh(); require("ui/uimanager"):show(require("ui/widget/infomessage"):new{text=_("Please restart KOReader to apply language changes"), timeout=3}) end })
            end
            return items
        end
    })

    table.insert(slider_items, {
        text = C_("Reading Reminders"),
        sub_item_table_func = function()
            return {
                {
                    text = _("Toast Position"),
                    sub_item_table_func = function()
                        local items = {}
                        local positions = {
                            { id = "top", label = _("Top") },
                            { id = "center", label = _("Center") },
                            { id = "bottom", label = _("Bottom") },
                            { id = "top_left", label = _("Top Left") },
                            { id = "top_right", label = _("Top Right") },
                            { id = "bottom_left", label = _("Bottom Left") },
                            { id = "bottom_right", label = _("Bottom Right") },
                        }
                        for _, p in ipairs(positions) do
                            table.insert(items, {
                                text = p.label,
                                checked_func = function() return (config.toast_position or "center") == p.id end,
                                callback = function()
                                    config.toast_position = p.id
                                    saveConfigAndRefresh()
                                end
                            })
                        end
                        return items
                    end
                },
                
                
                                {
                    text = _("Progress Reminders (Time)"),
                    sub_item_table_func = function()
                        local build_func; build_func = function()
                          local items = {}
                        local predefined = {60, 50, 40, 30, 20, 10}
                        for idx, v in ipairs(predefined) do
                            table.insert(items, { 
                                text = v .. _(" minutes"), 
                                checked_func = function() return config.progress_time[tostring(v)] end, 
                                ios_toggle = true, 
                                keep_menu_open = true, 
                                callback = function() 
                                    config.progress_time[tostring(v)] = not config.progress_time[tostring(v)]
                                    saveConfigAndRefresh() 
                                end 
                            })
                        end
                        for k, v in pairs(config.progress_time) do
                            local num = tonumber(k)
                            if num and not (num == 60 or num == 50 or num == 40 or num == 30 or num == 20 or num == 10) then
                                table.insert(items, { 
                                    text = num .. _(" minutes"), 
                                    checked_func = function() return config.progress_time[k] end, 
                                    ios_toggle = true, 
                                    keep_menu_open = true, 
                                    callback = function() 
                                        config.progress_time[k] = not config.progress_time[k]
                                        saveConfigAndRefresh() 
                                    end 
                                })
                            end
                        end
                        table.insert(items, { text = "", is_separator = true })
                        table.insert(items, {
                            text = _("Add Custom..."),
                            keep_menu_open = true,
                            callback = function(tm)
                                local InputDialog = require("ui/widget/inputdialog")
                                local dialog
                                dialog = InputDialog:new{
                                    title = _("Add Custom Progress Time (minutes)"),
                                    type = "number",
                                    buttons = {{
                                        { text = C_("Cancel"), id = "close", callback = function() require("ui/uimanager"):close(dialog) end },
                                        { text = C_("Add"), callback = function()
                                            local val = tonumber(dialog:getInputText())
                                            if val and val > 0 then
                                                config.progress_time[tostring(val)] = true
                                                saveConfigAndRefresh()
                                                  if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                                            end
                                            require("ui/uimanager"):close(dialog)
                                        end }
                                    }}
                                }
                                require("ui/uimanager"):show(dialog)
                            end
                        })
                        table.insert(items, {
                            text = _("Clear Custom"),
                            keep_menu_open = true,
                            callback = function(tm)
                                for k, v in pairs(config.progress_time) do
                                    local num = tonumber(k)
                                    if num and not (num == 60 or num == 50 or num == 40 or num == 30 or num == 20 or num == 10) then
                                        config.progress_time[k] = nil
                                    end
                                end
                                saveConfigAndRefresh()
                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                            end
                        })
                        return items
                          end
                          return build_func()
                      end
                },
                {
                    text = _("Progress Reminders (Pages)"),
                    sub_item_table_func = function()
                        local build_func; build_func = function()
                          local items = {}
                        local predefined = {50, 40, 30, 20, 10}
                        for idx, v in ipairs(predefined) do
                            table.insert(items, { 
                                text = v .. _(" pages"), 
                                checked_func = function() return config.progress_pages[tostring(v)] end, 
                                ios_toggle = true, 
                                keep_menu_open = true, 
                                callback = function() 
                                    config.progress_pages[tostring(v)] = not config.progress_pages[tostring(v)]
                                    saveConfigAndRefresh() 
                                end 
                            })
                        end
                        for k, v in pairs(config.progress_pages) do
                            local num = tonumber(k)
                            if num and not (num == 50 or num == 40 or num == 30 or num == 20 or num == 10) then
                                table.insert(items, { 
                                    text = num .. _(" pages"), 
                                    checked_func = function() return config.progress_pages[k] end, 
                                    ios_toggle = true, 
                                    keep_menu_open = true, 
                                    callback = function() 
                                        config.progress_pages[k] = not config.progress_pages[k]
                                        saveConfigAndRefresh() 
                                    end 
                                })
                            end
                        end
                        table.insert(items, { text = "", is_separator = true })
                        table.insert(items, {
                            text = _("Add Custom..."),
                            keep_menu_open = true,
                            callback = function(tm)
                                local InputDialog = require("ui/widget/inputdialog")
                                local dialog
                                dialog = InputDialog:new{
                                    title = _("Add Custom Progress Pages"),
                                    type = "number",
                                    buttons = {{
                                        { text = C_("Cancel"), id = "close", callback = function() require("ui/uimanager"):close(dialog) end },
                                        { text = C_("Add"), callback = function()
                                            local val = tonumber(dialog:getInputText())
                                            if val and val > 0 then
                                                config.progress_pages[tostring(val)] = true
                                                saveConfigAndRefresh()
                                                  if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                                            end
                                            require("ui/uimanager"):close(dialog)
                                        end }
                                    }}
                                }
                                require("ui/uimanager"):show(dialog)
                            end
                        })
                        table.insert(items, {
                            text = _("Clear Custom"),
                            keep_menu_open = true,
                            callback = function(tm)
                                for k, v in pairs(config.progress_pages) do
                                    local num = tonumber(k)
                                    if num and not (num == 50 or num == 40 or num == 30 or num == 20 or num == 10) then
                                        config.progress_pages[k] = nil
                                    end
                                end
                                saveConfigAndRefresh()
                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                            end
                        })
                        return items
                          end
                          return build_func()
                      end
                },
                {
                    text = _("Time Reminders"),
                    sub_item_table_func = function()
                        local build_func; build_func = function()
                        local items = {}
                        local predefined = {15, 10, 5, 3}
                        for idx, v in ipairs(predefined) do
                            table.insert(items, { 
                                text = v .. _(" minutes"), 
                                checked_func = function() return config.reminders_time[tostring(v)] end, 
                                ios_toggle = true, 
                                keep_menu_open = true, 
                                callback = function() 
                                    config.reminders_time[tostring(v)] = not config.reminders_time[tostring(v)]
                                    saveConfigAndRefresh() 
                                end 
                            })
                        end
                        for k, v in pairs(config.reminders_time) do
                            local num = tonumber(k)
                            if num and not (num == 15 or num == 10 or num == 5 or num == 3) then
                                table.insert(items, { 
                                    text = num .. _(" minutes"), 
                                    checked_func = function() return config.reminders_time[k] end, 
                                    ios_toggle = true, 
                                    keep_menu_open = true, 
                                    callback = function() 
                                        config.reminders_time[k] = not config.reminders_time[k]
                                        saveConfigAndRefresh() 
                                    end 
                                })
                            end
                        end
                        table.insert(items, { text = "", is_separator = true })
                        table.insert(items, {
                            text = _("Add Custom..."),
                            keep_menu_open = true,
                            callback = function(tm)
                                local InputDialog = require("ui/widget/inputdialog")
                                local dialog
                                dialog = InputDialog:new{
                                    title = _("Add Custom Time Reminder (minutes)"),
                                    type = "number",
                                    buttons = {{
                                        { text = C_("Cancel"), id = "close", callback = function() require("ui/uimanager"):close(dialog) end },
                                        { text = C_("Add"), callback = function()
                                            local val = tonumber(dialog:getInputText())
                                            if val and val > 0 then
                                                config.reminders_time[tostring(val)] = true
                                                saveConfigAndRefresh()
                                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                                            end
                                            require("ui/uimanager"):close(dialog)
                                        end }
                                    }}
                                }
                                require("ui/uimanager"):show(dialog)
                            end
                        })
                        table.insert(items, {
                            text = _("Clear Custom"),
                            keep_menu_open = true,
                            callback = function(tm)
                                for k, v in pairs(config.reminders_time) do
                                    local num = tonumber(k)
                                    if num and not (num == 15 or num == 10 or num == 5 or num == 3) then
                                        config.reminders_time[k] = nil
                                    end
                                end
                                saveConfigAndRefresh()
                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                            end
                        })
                        return items
                          end
                          return build_func()
                      end
                },
                {
                    text = _("Page Reminders"),
                    sub_item_table_func = function()
                        local build_func; build_func = function()
                        local items = {}
                        local predefined = {10, 5, 3, 1}
                        for idx, v in ipairs(predefined) do
                            table.insert(items, { 
                                text = v .. _(" pages"), 
                                checked_func = function() return config.reminders_pages[tostring(v)] end, 
                                ios_toggle = true, 
                                keep_menu_open = true, 
                                callback = function() 
                                    config.reminders_pages[tostring(v)] = not config.reminders_pages[tostring(v)]
                                    saveConfigAndRefresh() 
                                end 
                            })
                        end
                        for k, v in pairs(config.reminders_pages) do
                            local num = tonumber(k)
                            if num and not (num == 10 or num == 5 or num == 3 or num == 1) then
                                table.insert(items, { 
                                    text = num .. _(" pages"), 
                                    checked_func = function() return config.reminders_pages[k] end, 
                                    ios_toggle = true, 
                                    keep_menu_open = true, 
                                    callback = function() 
                                        config.reminders_pages[k] = not config.reminders_pages[k]
                                        saveConfigAndRefresh() 
                                    end 
                                })
                            end
                        end
                        table.insert(items, { text = "", is_separator = true })
                        table.insert(items, {
                            text = _("Add Custom..."),
                            keep_menu_open = true,
                            callback = function(tm)
                                local InputDialog = require("ui/widget/inputdialog")
                                local dialog
                                dialog = InputDialog:new{
                                    title = _("Add Custom Page Reminder"),
                                    type = "number",
                                    buttons = {{
                                        { text = C_("Cancel"), id = "close", callback = function() require("ui/uimanager"):close(dialog) end },
                                        { text = C_("Add"), callback = function()
                                            local val = tonumber(dialog:getInputText())
                                            if val and val > 0 then
                                                config.reminders_pages[tostring(val)] = true
                                                saveConfigAndRefresh()
                                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                                            end
                                            require("ui/uimanager"):close(dialog)
                                        end }
                                    }}
                                }
                                require("ui/uimanager"):show(dialog)
                            end
                        })
                        table.insert(items, {
                            text = _("Clear Custom"),
                            keep_menu_open = true,
                            callback = function(tm)
                                for k, v in pairs(config.reminders_pages) do
                                    local num = tonumber(k)
                                    if num and not (num == 10 or num == 5 or num == 3 or num == 1) then
                                        config.reminders_pages[k] = nil
                                    end
                                end
                                saveConfigAndRefresh()
                                if tm and tm.updateItems then tm.item_table = build_func(); tm:updateItems(tm.page or 1) end
                            end
                        })
                        return items
                          end
                          return build_func()
                      end
                }
            }
        end
    })
    
    table.insert(slider_items, {
        text = C_("Show brightness slider"),
        checked_func = function() return config.show_frontlight == true end,
        ios_toggle = true,
        keep_menu_open = true,
        callback = function()
            config.show_frontlight = not config.show_frontlight
            saveConfigAndRefresh()
        end,
    })
    if Device:hasNaturalLight() then
        table.insert(slider_items, {
            text = C_("Show warmth slider"),
            checked_func = function() return config.show_warmth == true end,
        ios_toggle = true,
        keep_menu_open = true,
            callback = function()
                config.show_warmth = not config.show_warmth
                saveConfigAndRefresh()
            end,
        })
    end

    table.insert(slider_items, {
        text = C_(_("Show as default tab when menu opens")),
        checked_func = function() return config.open_by_default == true end,
        ios_toggle = true,
        keep_menu_open = true,
        callback = function()
            config.open_by_default = not config.open_by_default
            saveConfigAndRefresh()
        end,
    })

    local root = {
        {
            text = C_("Buttons"),
            sub_item_table = buttons_section,
        },
    }
    for idx, item in ipairs(slider_items) do
        table.insert(root, item)
    end
    

    

    
    return root
end

local function applyTouchMenuPatches()
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu.__neo_qs_patched then return end
    TouchMenu.__neo_qs_patched = true
    
    local TouchMenuItem = nil
    local function findTouchMenuItem(func, depth)
        if depth > 10 or not func then return end
        for i = 1, 100 do
            local name, value = debug.getupvalue(func, i)
            if name == nil then break end
            if name == "TouchMenuItem" and type(value) == "table" then
                TouchMenuItem = value
                return true
            elseif type(value) == "function" then
                if findTouchMenuItem(value, depth + 1) then return true end
            end
        end
    end
    findTouchMenuItem(TouchMenu.updateItems, 1)
    
    if TouchMenuItem and not TouchMenuItem.__neo_ios_toggle_patched then
        TouchMenuItem.__neo_ios_toggle_patched = true
        local orig_mi_init = TouchMenuItem.init
        function TouchMenuItem:init()
            orig_mi_init(self)
            if self.item and self.item.ios_toggle and self.item.checked_func then
                local ok, NeoToggle = pcall(require, "common/neo_toggle")
                if ok and NeoToggle then
                    local CenterContainer = require("ui/widget/container/centercontainer")
                    local HorizontalSpan = require("ui/widget/horizontalspan")
                    local Size = require("ui/size")
                    local Geom = require("ui/geometry")
                    
                    local toggle = NeoToggle:new{
                        value_func = function() return self.item.checked_func() == true end,
                    }
                    local toggle_size = toggle:getSize()
                    local text_w = self.item_frame[1][2]
                    local orig_left_w = self.item_frame[1][1] and self.item_frame[1][1]:getSize().w or Size.padding.default
                    
                    if text_w then
                        self.item_frame[1][1] = HorizontalSpan:new{ width = orig_left_w }
                        self.item_frame[1][2] = text_w
                        self.item_frame[1][3] = HorizontalSpan:new{ width = math.max(0, self.dimen.w - text_w:getSize().w - toggle_size.w - orig_left_w - Size.padding.default * 2) }
                        self.item_frame[1][4] = CenterContainer:new{
                            dimen = Geom:new{ w = toggle_size.w },
                            toggle,
                        }
                        self.item_frame[1]._size = nil
                        self.item_frame[1]:getSize()
                    end
                end
            end
        end

        local orig_mi_onTapSelect = TouchMenuItem.onTapSelect
        function TouchMenuItem:onTapSelect(arg, ges)
            if self.item and self.item.ios_toggle then
                if self.item_frame and self.item_frame[1] and self.item_frame[1][4] then
                    local toggle = self.item_frame[1][4][1]
                    if toggle and toggle.toggle then
                        toggle:toggle()
                        local UIManager = require("ui/uimanager")
                        local Device = require("device")
                        UIManager:setDirty(self, function()
                            self:paintTo(Device.screen.bb, self.dimen.x, self.dimen.y)
                        end)
                    end
                end
            end
            return orig_mi_onTapSelect(self, arg, ges)
        end
    end

    local orig_onMenuSelect = TouchMenu.onMenuSelect
    TouchMenu.onMenuSelect = function(self, item, tap_on_checkmark)
        if NeoCaptureState and NeoCaptureState.active then
            local text = item.text or (item.text_func and item.text_func())
            if text and (item.sub_item_table or item.sub_item_table_func) then
                table.insert(NeoCaptureState.path, text)
            end
        end
        return orig_onMenuSelect(self, item, tap_on_checkmark)
    end

    local orig_backToUpperMenu = TouchMenu.backToUpperMenu
    TouchMenu.backToUpperMenu = function(self, no_close)
        if NeoCaptureState and NeoCaptureState.active and #NeoCaptureState.path > 0 then
            table.remove(NeoCaptureState.path)
        end
        return orig_backToUpperMenu(self, no_close)
    end

    local orig_onMenuHold = TouchMenu.onMenuHold
    TouchMenu.onMenuHold = function(self, item, text_truncated)
        if NeoCaptureState and NeoCaptureState.active then
            local text = item.text or (item.text_func and item.text_func())
            if text then
                local full_path = {}
                for _, p in ipairs(NeoCaptureState.path) do table.insert(full_path, p) end
                table.insert(full_path, text)
                
                local is_submenu = (item.sub_item_table ~= nil) or (item.sub_item_table_func ~= nil)
                local cb = NeoCaptureState.cb
                if cb then
                    cb.action = {
                        neo_menu_path  = full_path,
                        neo_is_submenu = is_submenu or nil,
                    }
                    cb.label = text .. (is_submenu and " ▶" or "")
                    saveConfig()
                else
                    -- Create new button using config directly (same as manual button creation)
                    config.next_custom_id = (config.next_custom_id or 0) + 1
                    local btn_id = "cb_" .. tostring(config.next_custom_id)
                    local new_cb = {
                        id     = btn_id,
                        label  = text .. (is_submenu and " ▶" or ""),
                        icon   = "button",
                        action = {
                            type           = "koreader_menu",
                            neo_menu_path  = full_path,
                            neo_is_submenu = is_submenu or nil,
                        },
                    }
                    -- custom_buttons is an array (list) in this plugin
                    config.custom_buttons = config.custom_buttons or {}
                    table.insert(config.custom_buttons, new_cb)
                    -- add to button_order and show_buttons so it appears in the panel
                    config.button_order = config.button_order or {}
                    config.show_buttons = config.show_buttons or {}
                    table.insert(config.button_order, btn_id)
                    config.show_buttons[btn_id] = true
                    saveConfig()
                end
                
                NeoCaptureState.active = false
                NeoCaptureState.cb = nil
                NeoCaptureState.path = {}
                
                self:closeMenu()
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = _("Action captured successfully!"), timeout = 2 })
                return true
            end
        end
        return orig_onMenuHold(self, item, text_truncated)
    end

    local orig_onClose = TouchMenu.onClose
    TouchMenu.onClose = function(self)
        if NeoCaptureState and NeoCaptureState.active then
            NeoCaptureState.active = false
            NeoCaptureState.cb = nil
            NeoCaptureState.path = {}
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("Capture cancelled."), timeout = 2 })
        end
        if orig_onClose then return orig_onClose(self) end
    end

    local orig_init = TouchMenu.init
    function TouchMenu:init()
        if config.open_by_default then
            self.last_index = 1
        elseif not self.last_index or self.last_index == 1 then
            self.last_index = 2
        end
        orig_init(self)
        local sw = Screen:getWidth()
        local sh = Screen:getHeight()
        self.ges_events.HoldCloseAllMenus = {
            GestureRange:new{ ges = "hold",        range = Geom:new{ x=0, y=0, w=sw, h=sh } }
        }
        self.ges_events.PanCloseAllMenus = {
            GestureRange:new{ ges = "pan",         range = Geom:new{ x=0, y=0, w=sw, h=sh } }
        }
        self.ges_events.PanReleaseCloseAllMenus = {
            GestureRange:new{ ges = "pan_release", range = Geom:new{ x=0, y=0, w=sw, h=sh } }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{ ges = "multiswipe",  range = Geom:new{ x=0, y=0, w=sw, h=sh } }
        }
    end

    local orig_updateItems = TouchMenu.updateItems
    function TouchMenu:updateItems(target_page, target_item_id)
        if not self.item_table or not self.item_table.panel then
            self._qs_refs = nil
            return orig_updateItems(self, target_page, target_item_id)
        end

        if not self._qs_refs then
            self._qs_slider_locked = true
            UIManager:scheduleIn(0.35, function() self._qs_slider_locked = false end)
        end

        local old_selected
        if self.selected then
            old_selected = { x = self.selected.x, y = self.selected.y }
        end

        self.item_group:clear()
        self.layout = {}
        table.insert(self.item_group, self.bar)
        table.insert(self.layout, self.bar.icon_widgets)

        local panel_fn = self.item_table.panel
        local ok, panel = pcall(panel_fn, self)
        if ok and panel then
            table.insert(self.item_group, panel)
        else
            logger.err("Neo QS panel error:", panel)
            table.insert(self.item_group, TextWidget:new{
                text = "Panel error: " .. tostring(panel),
                face = Font:getFace("cfont", 16),
            })
        end

        local qs_refs = self._qs_refs
        if qs_refs and qs_refs.button_layout_row and #qs_refs.button_layout_row > 0 then
            table.insert(self.layout, qs_refs.button_layout_row)
        end

        table.insert(self.item_group, self.footer_top_margin)
        table.insert(self.item_group, self.footer)
        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)
        self.page_info_left_chev:enableDisable(false)
        self.page_info_right_chev:enableDisable(false)
        
        local BD = require("ui/bidi")
        local datetime = require("datetime")
        local time_info_txt = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        local powerd = Device:getPowerDevice()
        if Device:hasBattery() then
            local batt_lvl = powerd:getCapacity()
            local batt_symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), batt_lvl)
            time_info_txt = BD.wrap(time_info_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(batt_symbol) ..  BD.wrap(batt_lvl .. "%")
            if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
                local aux_batt_lvl = powerd:getAuxCapacity()
                local aux_batt_symbol = powerd:getBatterySymbol(powerd:isAuxCharged(), powerd:isAuxCharging(), aux_batt_lvl)
                time_info_txt = time_info_txt .. " " .. BD.wrap("+") .. BD.wrap(aux_batt_symbol) ..  BD.wrap(aux_batt_lvl .. "%")
            end
        end
        if self.time_info and self.time_info.setText then
            self.time_info:setText(time_info_txt)
        end

        local old_dimen = self.dimen:copy()
        self.dimen.w = self.width
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding

        if old_selected then
            local row = self.layout[old_selected.y]
            if row and row[old_selected.x] then
                self:moveFocusTo(old_selected.x, old_selected.y, 0)
            else
                self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
            end
        else
            self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
        end

        local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
        UIManager:setDirty((self.is_fresh or keep_bg) and self.show_parent or "all", function()
            local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
            local refresh_type = "ui"
            if self.is_fresh then
                refresh_type = "flashui"
                self.is_fresh = false
            end
            return refresh_type, refresh_dimen
        end)
    end

    local orig_onTap = TouchMenu.onTapCloseAllMenus
    function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
        if self._qs_refs and self.item_table and self.item_table.panel then
            if self._qs_slider_locked then return true end
            if handlePanelGesture(self, ges_ev, false) then return true end
        end
        return orig_onTap(self, arg, ges_ev)
    end

    function TouchMenu:onHoldCloseAllMenus(arg, ges_ev)
        if self._qs_refs and self.item_table and self.item_table.panel then
            if not self._qs_slider_locked then
                handlePanelGesture(self, ges_ev, true)
            end
        end
        return true
    end

    NeoSlider.installTouchMenuHooks(TouchMenu, {
        in_panel_mode = function(tm)
            return tm._qs_refs ~= nil
               and tm.item_table ~= nil
               and tm.item_table.panel ~= nil
        end,
        get_sliders = function(tm)
            local refs = tm._qs_refs
            if not refs then return {} end
            local sliders = {}
            for idx, sr in ipairs(refs.sliders or {}) do
                table.insert(sliders, sr.slider)
            end
            return sliders
        end,
        is_locked           = function(tm) return tm._qs_slider_locked end,
        swipe_fallback      = function(tm, ges) handlePanelGesture(tm, ges, false) end,
        multiswipe_fallback = function(tm, ges) handlePanelGesture(tm, ges, false) end,
    })

    local orig_switchMenuTab = TouchMenu.switchMenuTab
    function TouchMenu:switchMenuTab(tab_num)
        orig_switchMenuTab(self, tab_num)
        self.last_index = 1
    end

    local orig_onClose = TouchMenu.onCloseWidget
    function TouchMenu:onCloseWidget()
        self._qs_refs = nil
        self._qs_opening_pan = false
        if orig_onClose then orig_onClose(self) end
    end

    local orig_onPrevPage = TouchMenu.onPrevPage
    if orig_onPrevPage then
        function TouchMenu:onPrevPage()
            if self.item_table and self.item_table.panel then return true end
            return orig_onPrevPage(self)
        end
    end
    local orig_onNextPage = TouchMenu.onNextPage
    if orig_onNextPage then
        function TouchMenu:onNextPage()
            if self.item_table and self.item_table.panel then return true end
            return orig_onNextPage(self)
        end
    end
end

local quick_settings_tab = {
    id      = "neo_quicksettings",
    icon    = "neo",
    remember = false,
    panel   = createQuickSettingsPanel,
            sub_item_table_func = buildSettingsMenuItems,
}

local _plugin_folder = _src:match("([^/]+)%.koplugin/main%.lua$") or "neo_quicksetting"
NeoQuickSettings = WidgetContainer:extend{
    name    = _plugin_folder,
    version = 1,
}

function NeoQuickSettings:init()
    local Dispatcher = require("dispatcher")
    if self.onDispatcherRegisterActions then self:onDispatcherRegisterActions() end
    -- Cache UI reference: distinguish ReaderUI (has document) from FileManager
    if self.ui then
        if self.ui.document ~= nil then
            _cached_reader_ui = self.ui
        else
            _cached_fm_ui = self.ui
        end
    end
    applyTouchMenuPatches()

    -- Helper: check if this plugin is enabled in plugin manager
    local function isPluginEnabled()
        local ok_pm, PluginLoader = pcall(require, "pluginloader")
        if ok_pm and PluginLoader and PluginLoader.enabled_plugins then
            return PluginLoader.enabled_plugins[_plugin_folder] ~= false
        end
        -- Fallback: check the plugin settings file
        local ok_ds, DataStorage2 = pcall(require, "datastorage")
        if ok_ds then
            local ok_ls, LuaSettings2 = pcall(require, "luasettings")
            if ok_ls then
                local plugins_settings_path = DataStorage2:getSettingsDir() .. "/plugins.lua"
                local ok_open, ps = pcall(function() return LuaSettings2:open(plugins_settings_path) end)
                if ok_open and ps then
                    local disabled = ps:readSetting("disabled_plugins") or {}
                    return disabled[_plugin_folder] ~= true
                end
            end
        end
        return true -- assume enabled if can't check
    end

    local function injectTab(menu_class)
        if not menu_class or menu_class.__neo_qs_tab_injected then return end
        menu_class.__neo_qs_tab_injected = true
        local orig = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(m_self)
            orig(m_self)
            -- Remove any previously injected tab first
            if type(m_self.tab_item_table) == "table" then
                for i = #m_self.tab_item_table, 1, -1 do
                    if m_self.tab_item_table[i].id == "neo_quicksettings" then
                        table.remove(m_self.tab_item_table, i)
                        break
                    end
                end
                -- Only re-inject if plugin is still enabled
                if isPluginEnabled() then
                    table.insert(m_self.tab_item_table, 1, quick_settings_tab)
                end
            end
            
            if m_self.menu_items then
                local SlideConfirmBox = require("slideconfirmbox")
                local Event = require("ui/event")
                local UIManager = require("ui/uimanager")

                if m_self.menu_items.exit and type(m_self.menu_items.exit.callback) == "function" and not m_self.menu_items.exit.__neo_patched then
                    m_self.menu_items.exit.__neo_patched = true
                    m_self.menu_items.exit.callback = function()
                        UIManager:show(SlideConfirmBox:new{
                                            title = _("Exit?"),
                            text  = _("Swipe to exit"),
                            icon  = "quick_exit",
                            on_confirm = function() UIManager:broadcastEvent(Event:new("Exit")) end
                        })
                    end
                end

                if m_self.menu_items.restart_koreader and type(m_self.menu_items.restart_koreader.callback) == "function" and not m_self.menu_items.restart_koreader.__neo_patched then
                    m_self.menu_items.restart_koreader.__neo_patched = true
                    m_self.menu_items.restart_koreader.callback = function()
                        UIManager:show(SlideConfirmBox:new{
                                            title = _("Restart?"),
                            text  = _("Swipe to start"),
                            icon  = "quick_restart",
                            on_confirm = function() UIManager:broadcastEvent(Event:new("Restart")) end
                        })
                    end
                end

                if m_self.menu_items.poweroff and type(m_self.menu_items.poweroff.callback) == "function" and not m_self.menu_items.poweroff.__neo_patched then
                    m_self.menu_items.poweroff.__neo_patched = true
                    m_self.menu_items.poweroff.callback = function()
                        UIManager:show(SlideConfirmBox:new{
                                            title = _("Power off?"),
                            text  = _("Swipe to exit"),
                            icon  = "quick_poweroff",
                            on_confirm = function() UIManager:nextTick(UIManager.poweroff_action) end
                        })
                    end
                end

                if m_self.menu_items.reboot and type(m_self.menu_items.reboot.callback) == "function" and not m_self.menu_items.reboot.__neo_patched then
                    m_self.menu_items.reboot.__neo_patched = true
                    m_self.menu_items.reboot.callback = function()
                        UIManager:show(SlideConfirmBox:new{
                                            title = _("Reboot device?"),
                            text  = _("Swipe to start"),
                            icon  = "quick_restart",
                            on_confirm = function() UIManager:nextTick(UIManager.reboot_action) end
                        })
                    end
                end
            end
        end
    end

    local ok_fm, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm then injectTab(FileManagerMenu) end

    local ok_rm, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if ok_rm then injectTab(ReaderMenu) end

    -- Do NOT inject into menu_order tables - KOReader manages those via registerToMainMenu

    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function NeoQuickSettings:onFlushSettings()
    saveConfig()
end

function NeoQuickSettings:addToMainMenu(menu_items)
    -- Use the actual plugin folder name as key so disable works correctly
    menu_items[_plugin_folder] = {
        text = C_("Neo Quick Settings"),
        sub_item_table_func = function()
            return buildSettingsMenuItems()
        end,
    }
end


function NeoQuickSettings:onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("neo_capture_menu_action", { category="none", event="NeoCaptureMenuItem", title=_("Capture Menu Item (Neo)"), general=true })
end

function NeoQuickSettings:onNeoCaptureMenuItem()
    NeoCaptureState.active = true
    NeoCaptureState.path = {}
    NeoCaptureState.cb = nil -- flag to indicate creating a new button
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = _("Navigate to any KOReader menu and LONG PRESS an item!"), timeout = 4 })
    return true
end

function NeoQuickSettings:onPageUpdate(pageno)
    if not NeoQuickSettings.page_goal_remaining then return end

    local ui = self.ui or require("ui/uimanager"):getActiveWindow()
    local phys_page = pageno
    
    if ui and ui.document and ui.doc_settings then
        local doc_settings = ui.doc_settings
        local sync_enabled = doc_settings:readSetting("yanllsama_sync_enabled")
        if sync_enabled == nil then sync_enabled = true end
        
        if sync_enabled then
            local pagemap = ui.pagemap
            local use_pm = pagemap and pagemap.has_pagemap and pagemap.use_page_labels
            
            if use_pm then
                local lbl = pagemap:getCurrentPageLabel(true)
                local phys = lbl and tonumber(lbl)
                if phys then phys_page = phys end
            else
                local ratio = doc_settings:readSetting("yanllsama_screen_ratio") or 1.0
                if doc_settings:readSetting("pagemap_chars_per_synthetic_page") then ratio = 1.0 end
                local max_phys = doc_settings:readSetting("yanllsama_physical_pages") or math.huge
                
                if ratio < 1.0 then
                    phys_page = math.max(1, math.min(max_phys, math.floor((pageno - 1) / ratio + 1.5)))
                else
                    phys_page = math.max(1, math.min(max_phys, math.ceil(pageno / ratio)))
                end
            end
        end
    end

    local logger = require("logger")
    logger.info("NeoQuickSettings: onPageUpdate pageno=", pageno, "phys_page=", phys_page, "last_phys_page=", NeoQuickSettings.last_phys_page, "remaining=", NeoQuickSettings.page_goal_remaining)

    if NeoQuickSettings.last_phys_page ~= phys_page then
        if NeoQuickSettings.last_phys_page ~= nil then
            NeoQuickSettings.session_pages_read = (NeoQuickSettings.session_pages_read or 0) + 1
            
            if NeoQuickSettings.page_goal_remaining then
                NeoQuickSettings.page_goal_remaining = NeoQuickSettings.page_goal_remaining - 1
            end
            
            local r = NeoQuickSettings.page_goal_remaining
            local pr = NeoQuickSettings.session_pages_read
            local trigger_prog = false
            local trigger_goal = false
            
            if config and config.progress_pages and config.progress_pages[tostring(pr)] then
                trigger_prog = true
            end
            
            if r and config and config.reminders_pages and config.reminders_pages[tostring(r)] then
                trigger_goal = true
            end
            
            if trigger_prog or trigger_goal then
                local msg
                if trigger_prog and trigger_goal and r and r > 0 then
                    msg = _("Read pages: ") .. pr .. "\n" .. _("Pages to goal: ") .. r
                elseif trigger_prog then
                    msg = _("Read pages: ") .. pr
                elseif trigger_goal and r and r > 0 then
                    msg = _("Pages to goal: ") .. r
                end
                if msg then showTopRightToast(msg) end
            end

            if NeoQuickSettings.page_goal_remaining and NeoQuickSettings.page_goal_remaining <= 0 then
                NeoQuickSettings.page_goal_remaining = nil
                NeoQuickSettings.last_phys_page = nil
                local ButtonDialog = require("ui/widget/buttondialog")
                local dialog
                dialog = ButtonDialog:new{
                    
                    title = _("Page goal reached!\n\nDo you want to set a new goal?"),
                    title_align = "center",
                    use_info_style = false,
                    buttons = {
                        {
                            {
                                text = _("Yes"),
                                callback = function()
                                    UIManager:close(dialog)
                                    if button_defs and button_defs.read_goal_pages then
                                        button_defs.read_goal_pages.callback()
                                    end
                                end,
                            }
                        },
                        {
                            {
                                text = _("No"),
                                callback = function()
                                    UIManager:close(dialog)
                                end,
                            }
                        }
                    }
                }
                UIManager:show(dialog)
                return
            end
        end
        NeoQuickSettings.last_phys_page = phys_page
    end
end

function NeoQuickSettings:onReaderReady()
    NeoQuickSettings.session_pages_read = 0
    NeoQuickSettings.session_time_read = 0
    NeoQuickSettings._session_seconds = 0
    
    if self.progress_timer then
        require("ui/uimanager"):unschedule(self.progress_timer)
    end
    
    local startup = true
    local function progressTick()
        if startup then
            startup = false
            require("ui/uimanager"):scheduleIn(10, progressTick)
            return
        end
        
        require("ui/uimanager"):scheduleIn(10, progressTick)
        
        if NeoQuickSettings._is_suspended then return end
        if not isReadingActive() then return end
        
        NeoQuickSettings._session_seconds = (NeoQuickSettings._session_seconds or 0) + 10
        if NeoQuickSettings._session_seconds >= 60 then
            NeoQuickSettings._session_seconds = NeoQuickSettings._session_seconds - 60
            NeoQuickSettings.session_time_read = (NeoQuickSettings.session_time_read or 0) + 1
            
            if NeoQuickSettings.time_goal_remaining then
                NeoQuickSettings.time_goal_remaining = NeoQuickSettings.time_goal_remaining - 1
            end
            
            local r = NeoQuickSettings.time_goal_remaining
            local tr = NeoQuickSettings.session_time_read
            local trigger_prog = false
            local trigger_goal = false
            
            if config and config.progress_time and config.progress_time[tostring(tr)] then
                trigger_prog = true
            end
            if r and config and config.reminders_time and config.reminders_time[tostring(r)] then
                trigger_goal = true
            end
            
            if trigger_prog or trigger_goal then
                local msg
                if trigger_prog and trigger_goal and r and r > 0 then
                    msg = _("Read time: ") .. tr .. _(" min\nTime to goal: ") .. r .. _(" min")
                elseif trigger_prog then
                    msg = _("Read time: ") .. tr .. _(" min")
                elseif trigger_goal and r and r > 0 then
                    msg = _("Time to goal: ") .. r .. _(" min")
                end
                if msg then showTopRightToast(msg) end
            end
            
            if NeoQuickSettings.time_goal_remaining and NeoQuickSettings.time_goal_remaining <= 0 then
                NeoQuickSettings.time_goal_remaining = nil
                NeoQuickSettings.time_goal_id = nil
                local ButtonDialog = require("ui/widget/buttondialog")
                local d
                d = ButtonDialog:new{
                    title = _("Time goal reached!\n\nDo you want to set a new goal?"),
                    title_align = "center",
                    use_info_style = false,
                    buttons = {
                        {
                            {
                                text = _("Yes"),
                                callback = function()
                                    require("ui/uimanager"):close(d)
                                    if button_defs and button_defs.read_goal_time then
                                        button_defs.read_goal_time.callback()
                                    end
                                end,
                            }
                        },
                        {
                            {
                                text = _("No"),
                                callback = function()
                                    require("ui/uimanager"):close(d)
                                end,
                            }
                        }
                    }
                }
                require("ui/uimanager"):show(d)
            end
        end
    end
    self.progress_timer = progressTick
    -- Start 3 seconds after opening the book
    require("ui/uimanager"):scheduleIn(3, progressTick)
end

function NeoQuickSettings:onSuspend()
    NeoQuickSettings._is_suspended = true
end

function NeoQuickSettings:onResume()
    NeoQuickSettings._is_suspended = false
end
function NeoQuickSettings:onCloseDocument()
    if self.progress_timer then
        require("ui/uimanager"):unschedule(self.progress_timer)
        self.progress_timer = nil
    end
    NeoQuickSettings._session_seconds = 0
    NeoQuickSettings.time_goal_remaining = nil
    NeoQuickSettings.time_goal_id = nil
    NeoQuickSettings.page_goal_remaining = nil
    NeoQuickSettings.page_goal_id = nil
    NeoQuickSettings.session_pages_read = 0
    NeoQuickSettings.session_time_read = 0
    NeoQuickSettings.last_phys_page = nil
end

-- Clear common/ from package.loaded to prevent namespace collisions with subsequently loaded plugins (like Zenos)
for k in pairs(package.loaded) do if k:match("^common/") then package.loaded[k] = nil end end
return NeoQuickSettings








































