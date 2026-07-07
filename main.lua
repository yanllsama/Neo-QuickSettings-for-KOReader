
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
local _               = require("gettext")
local C_              = require("gettext")
local ok_sui, sui_i18n = pcall(require, "sui_i18n")
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
    open_by_default = true,
    button_order = { "wifi", "night", "rotate", "sleep", "restart", "exit", "search", "screenshot", "kosync", "bluetooth", "filebrowserplus", "ssh", "streak", "opds", "stats_progress", "stats_calendar", "battery_stats", "localsend", "bookfusion", "focus", "settings" },
    show_buttons = {
        wifi       = true,
        night      = true,
        rotate     = true,
        sleep      = true,
        restart    = true,
        exit       = true,
        search     = false,
        screenshot = false,
        kosync     = false,
        bluetooth  = false,
        filebrowserplus = false,
        ssh        = false,
        streak     = false,
        opds       = false,
        stats_progress = false,
        stats_calendar = false,
        battery_stats  = false,
        localsend  = false,
        bookfusion = false,
        focus      = false,
        settings   = true,
    },
    favorite_groups = {},
    show_frontlight = true,
    show_warmth     = true,
    row_count       = 1,
    button_style    = "circle",
    button_items_per_row = 8,
    slider_style    = "neo",
    show_info_header= false,
    label_size      = 5,
    icon_scale_level= 1,
    custom_buttons  = {},   -- { id, label, icon, action }
    custom_builtin_icons = {}, -- { id = icon_name }
    custom_builtin_labels = {}, -- { id = label_text }
    user_builtin_buttons = {}, -- user added built-in buttons
    next_custom_id  = 0,
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

local function saveConfig()
    _settings:saveSetting("config", config)
    _settings:flush()
    if createQuickSettingsPanel and UIManager and UIManager._window_stack then
        for i = #UIManager._window_stack, 1, -1 do
            local win = UIManager._window_stack[i]
            if win and type(win.updateItems) == "function" then
                if win.item_table_stack then
                    for idx, it in ipairs(win.item_table_stack) do
                        if it.panel then
                            it.panel = createQuickSettingsPanel(win)
                        end
                    end
                end
                if win.item_table and win.item_table.panel then
                    win.item_table.panel = createQuickSettingsPanel(win)
                    win:updateItems(1)
                end
            end
        end
    end
end

loadConfig()

local function hasPlugin(name)
    if G_reader_settings:isTrue("plugin_" .. name .. "_enabled") then return true end
    local ok_datastorage, DataStorage = pcall(require, "datastorage")
    local data_dir = ok_datastorage and DataStorage and DataStorage.getDataDir and DataStorage:getDataDir() or nil
    local candidates = { "plugins/" .. name .. ".koplugin/main.lua" }
    if data_dir then table.insert(candidates, data_dir .. "/plugins/" .. name .. ".koplugin/main.lua") end
    for idx, path in ipairs(candidates) do
        local file = io.open(path, "r")
        if file then file:close() return true end
    end
    return false
end

local function getMainUI()
    if UIManager and UIManager._window_stack then
        for idx, win in ipairs(UIManager._window_stack) do
            if win.id == "ReaderUI" or win.id == "FileManager" then return win end
        end
    end
    return nil
end

local function showPluginMissingMessage(text)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text })
end

local button_defs = {
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

    for idx, arr in ipairs({config.custom_buttons, config.user_builtin_buttons}) do
        for idx, cb in ipairs(arr) do
            local cb_action = cb.action
            button_defs[cb.id] = {
                icon  = cb.icon or ("button"),
                label = (cb.label and cb.label ~= "") and cb.label
                    or (cb_action and next(cb_action) and Dispatcher:menuTextFunc(cb_action))
                    or C_("Custom"),
                callback = function(tm)
                    tm:closeMenu()
                    if type(cb_action) == "table" and next(cb_action) then
                        Dispatcher:execute(cb_action)
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
        local icon_path = _icons_dir and utils.resolveIcon(_icons_dir, icon_name)
        local icon_w = IconWidget:new{
            file   = icon_path or nil,
            icon   = icon_path and nil or icon_name,
            width  = icon_size,
            height = icon_size,
            alpha  = not active,
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
                local icon_name  = (config.custom_builtin_icons and config.custom_builtin_icons[entry.id]) or def.icon
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
                    txt = T(C_("Action: %1"), Disp:menuTextFunc(cb.action))
                end
                return txt
            end,
            sub_item_table_func = function()
                local sub = {}
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
        text_func = function()
            return config.show_buttons[cb.id]
                and C_("Visible ✓ (tap to hide)")
                or  C_("Hidden   (tap to show)")
        end,
        keep_menu_open = true,
        callback = function(tm)
            config.show_buttons[cb.id] = not config.show_buttons[cb.id]
            if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
        end,
    })

    table.insert(items, {
        text = C_("Export to SimpleUI"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            local ok, SUIConfig = pcall(require, "sui_config")
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
                    local ok_qa, QA = pcall(require, "sui_quickactions")
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
                
                local ok_qa, QA = pcall(require, "sui_quickactions")
                if ok_qa and QA and QA.invalidateCustomQACache then QA.invalidateCustomQACache() end
                
                local plugin = package.loaded["simpleui"]
                if plugin and plugin._rebuildAllNavbars then plugin:_rebuildAllNavbars() end
                
                local ok_hs, HS = pcall(require, "sui_homescreen")
                if ok_hs and HS and HS._instance then HS._instance:_refreshImmediate(false) end

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
        text_func = function() return "Name: " .. (fg.label or C_("Favorite")) end,
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
                        if tm and tm.updateItems then tm:updateItems(tm.page or 1) end
                    end)
                    return
                end
            end
            UIManager:show(InfoMessage:new{ text = (icon_picker_err ~= "") and ("Error: " .. icon_picker_err) or "Icon picker not found.", timeout = 2 })
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
        text = _("Delete this Favorite Button"),
        separator = true,
        keep_menu_open = true,
        callback = function(tm)
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to delete this favorite button?"),
                ok_text = "Yes, Delete",
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
        text = "Buttons Per Row for Favorites",
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
        text = "Create New Favorite Menu",
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
                        text = "Change Name",
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
                        text = "Change Icon",
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
                                    text = "Are you sure you want to completely delete this built-in button?",
                                    ok_text = "Yes, Delete",
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
            text = "Reset All Names and Icons",
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
        { text = "Edit", is_label = true, separator = true, enabled = false },
        {
            text = _("Add/Remove Buttons"),
            sub_item_table_func = function()
                return {
                    {
                        text = "Show / Hide Buttons",
                        sub_item_table_func = function()
                            return button_toggle_items
                        end
                    },
                    {
                        text = "Change Order (Drag & Drop)",
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
            text = "Edit Built-in Buttons",
            sub_item_table_func = function()
                return buildBuiltinButtonEditor()
            end
        },
        { text = "Add / Remove", is_label = true, separator = true, enabled = false },
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
        { text = "Appearance Options", is_label = true, separator = true, enabled = false },
        {
            text = _("Button Appearance Options"),
            sub_item_table_func = function()
                return {
                    {
                        text = "Buttons Per Row",
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
                        text = "Button Rows",
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
    }

    local slider_items = {}
    table.insert(slider_items, {
        text = "Slider Style",
        sub_item_table_func = function()
            return {
                { text = "Neo (Rounded Knob)", checked_func = function() return (config.slider_style or "neo") == "neo" end, callback = function() config.slider_style = "neo"; saveConfigAndRefresh() end },
                { text = "Progress Bar", checked_func = function() return config.slider_style == "progress_bar" end, callback = function() config.slider_style = "progress_bar"; saveConfigAndRefresh() end },
                { text = "Notched Bar", checked_func = function() return config.slider_style == "notched" end, callback = function() config.slider_style = "notched"; saveConfigAndRefresh() end },
                            { text = "Square Notched", checked_func = function() return config.slider_style == "square_notched" end, callback = function() config.slider_style = "square_notched"; saveConfigAndRefresh() end },
            }
        end,
    })
    
    table.insert(slider_items, {
        text = C_("Show brightness slider"),
        checked_func = function() return config.show_frontlight == true end,
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

local NeoQuickSettings = WidgetContainer:extend{
    name    = "neo_quicksettings",
    version = 1,
}

function NeoQuickSettings:init()
    applyTouchMenuPatches()

    local function injectTab(menu_class)
        if not menu_class or menu_class.__neo_qs_tab_injected then return end
        menu_class.__neo_qs_tab_injected = true
        local orig = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(m_self)
            orig(m_self)
            if type(m_self.tab_item_table) == "table" then
                for i = #m_self.tab_item_table, 1, -1 do
                    if m_self.tab_item_table[i].id == "neo_quicksettings" then
                        table.remove(m_self.tab_item_table, i)
                        break
                    end
                end
                table.insert(m_self.tab_item_table, 1, quick_settings_tab)
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

    local ok_order, reader_menu_order = pcall(require, "ui/elements/reader_menu_order")
    if ok_order and reader_menu_order and reader_menu_order.setting then
        local found = false
        for idx, v in ipairs(reader_menu_order.setting) do
            if v == "neo_quicksettings" then found = true; break end
        end
        if not found then table.insert(reader_menu_order.setting, "neo_quicksettings") end
    end

    local ok_fm_order, fm_menu_order = pcall(require, "ui/elements/filemanager_menu_order")
    if ok_fm_order and fm_menu_order and fm_menu_order.setting then
        local found = false
        for idx, v in ipairs(fm_menu_order.setting) do
            if v == "neo_quicksettings" then found = true; break end
        end
        if not found then table.insert(fm_menu_order.setting, "neo_quicksettings") end
    end

    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function NeoQuickSettings:onFlushSettings()
    saveConfig()
end

function NeoQuickSettings:addToMainMenu(menu_items)
    menu_items.neo_quicksettings = {
        text = C_("Neo Quick Settings"),
        sub_item_table_func = function()
            return buildSettingsMenuItems()
        end,
    }
end

return NeoQuickSettings







