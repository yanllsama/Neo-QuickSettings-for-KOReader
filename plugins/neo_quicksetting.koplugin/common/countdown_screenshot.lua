
local BD               = require("ui/bidi")
local Blitbuffer       = require("ffi/blitbuffer")
local ButtonDialog     = require("ui/widget/buttondialog")
local CenterContainer  = require("ui/widget/container/centercontainer")
local DataStorage      = require("datastorage")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local Screen           = require("device").screen
local util             = require("util")
local _                = require("gettext")
local icons            = require("common/inline_icon_map")

local M = {}

local function getLocalsendPlugin()
    local ok_f, FM = pcall(require, "apps/filemanager/filemanager")
    local ok_r, RU = pcall(require, "apps/reader/readerui")
    local ui = (ok_f and FM.instance) or (ok_r and RU.instance)
    return ui and ui.localsend or nil
end

local CountdownBar = WidgetContainer:extend{ toast = true }

function CountdownBar:init()
    local screen_w = Screen:getWidth()
    local bar_h    = Screen:scaleBySize(35)
    self.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = bar_h }
    self[1] = FrameContainer:new{
        width      = screen_w,
        height     = bar_h,
        background = Blitbuffer.COLOR_BLACK,
        bordersize = 0,
        padding    = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = bar_h },
            TextWidget:new{
                text    = self.count,
                face    = Font:getFace("infofont", Screen:scaleBySize(13)),
                fgcolor = Blitbuffer.COLOR_WHITE,
            },
        },
    }
end

local function show_save_dialog(screenshot_name)
    local dialog
    local buttons = {
        {
            {
                text     = icons.display .. "  " .. _("View"),
                align    = "left",
                callback = function()
                    local ImageViewer = require("ui/widget/imageviewer")
                    UIManager:show(ImageViewer:new{
                        file            = screenshot_name,
                        modal           = true,
                        with_title_bar  = false,
                        buttons_visible = true,
                    })
                end,
            },
        },
    }
    local ls = getLocalsendPlugin()
    if ls then
        table.insert(buttons, {
            {
                text     = icons.send .. "  " .. _("Send with LocalSend"),
                align    = "left",
                callback = function()
                    UIManager:close(dialog)
                    ls:openFirewall()
                    local lssender = package.loaded["localsend_sender"]
                    if lssender then
                        lssender.showFileSendFlow(ls, screenshot_name)
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text     = icons.delete .. "  " .. _("Delete"),
            align    = "left",
            callback = function()
                os.remove(screenshot_name)
                UIManager:close(dialog)
            end,
        },
    })
    dialog = ButtonDialog:new{
        title   = _("Screenshot saved to:") .. "\n\n" .. BD.filepath(screenshot_name) .. "\n",
        modal   = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
    UIManager:setDirty(nil, "full")
end

function M.run()
    local current_bar

    local function close_bar()
        if current_bar then
            UIManager:close(current_bar)
            UIManager:setDirty(nil, "ui")
            current_bar = nil
        end
    end

    local function do_shot()
        close_bar()
        UIManager:scheduleIn(0.05, function()
            local screenshot_dir = DataStorage:getFullDataDir() .. "/screenshots"
            util.makePath(screenshot_dir)
            local name = os.date(screenshot_dir .. "/Screenshot_%Y-%m-%d_%H%M%S.png")
            Screen:shot(name)
            show_save_dialog(name)
        end)
    end

    local function show_count(n, next_fn)
        close_bar()
        current_bar = CountdownBar:new{ count = tostring(n) }
        UIManager:show(current_bar)
        UIManager:setDirty(current_bar, "ui")
        UIManager:scheduleIn(1, next_fn)
    end

    show_count(3, function()
        show_count(2, function()
            show_count(1, do_shot)
        end)
    end)
end

return M
