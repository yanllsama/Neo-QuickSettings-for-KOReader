
local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local Input          = require("device/input")
local TextBoxWidget  = require("ui/widget/textboxwidget")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local NeoButton      = require("common/neo_button")
local Screen         = Device.screen
local _              = require("gettext")
local ok_stw, ScrollTextWidget = pcall(require, "ui/widget/scrolltextwidget")

local logger           = require("logger")
local ok_iw, ImageWidget = pcall(require, "ui/widget/imagewidget")
if not ok_iw then ImageWidget = nil end

local _plugin_root = require("common/plugin_root") or ""

local NeoScreen = InputContainer:extend{
    title             = nil,   -- string shown in top bar; nil hides the title bar entirely
    title_icon        = false, -- force inline Neo icon to the left of title text
    subtitle          = nil,   -- string rendered above the icon (e.g. "Updated to v1.2.3")
    changelog         = nil,   -- array of strings; when set, logo shrinks to make room for a bullet list
    scroll_text       = nil,   -- long-form changelog text rendered in a scrollable view
    button            = nil,   -- button label string; nil -> "Get Started"; false -> no button
    later_button      = nil,   -- optional outlined secondary button to the left; tapping closes
    on_close          = nil,
    dismissable       = true,  -- when false, swipe/tap-outside won't close the screen
    _on_button_action = nil,   -- if set, button tap calls this instead of onClose
}

function NeoScreen:_computeLayout()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local PAD        = Screen:scaleBySize(20)
    local TITLE_H    = self.title and Screen:scaleBySize(60) or 0
    local SEP_H      = 0
    local SUBTITLE_H = self.subtitle and Screen:scaleBySize(44) or 0
    local BTN_H      = Screen:scaleBySize(80)
    self._L = {
        sw         = sw,
        sh         = sh,
        pad        = PAD,
        title_h    = TITLE_H,
        sep_h      = SEP_H,
        subtitle_h = SUBTITLE_H,
        btn_h      = BTN_H,
        content_y  = TITLE_H + SEP_H + SUBTITLE_H,
        content_h  = sh - TITLE_H - SEP_H - SUBTITLE_H - BTN_H,
        btn_y      = sh - BTN_H,
    }
end

function NeoScreen:init()
    logger.info("NeoScreen:init title=", self.title)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self:_computeLayout()
    self._btn_rect = nil
    self._scroll_text_w = nil
    self._scroll_rect = nil
    self._scroll_text_cache = nil
    self._scroll_w = nil
    self._scroll_h = nil
    self._scroll_top_line_num = nil

    self:registerTouchZones({
        {
            id          = "zs_swipe",
            ges         = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function(ges) return self:_onSwipe(ges) end,
        },
        {
            id          = "zs_tap",
            ges         = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function(ges) return self:_onTap(ges) end,
        },
    })

    if Device:hasKeys() then
        self.key_events = {
            ZsConfirm = {
                { "Press" },
                event = "ZsConfirm",
            },
            ZsConfirmPgFwd = {
                { Input.group.PgFwd },
                event = "ZsConfirm",
            },
            ZsDismiss = {
                { Input.group.PgBack },
                event = "ZsDismiss",
            },
        }
    end
end

function NeoScreen:_free_scroll_widget()
    if self._scroll_text_w and type(self._scroll_text_w.free) == "function" then
        pcall(self._scroll_text_w.free, self._scroll_text_w, false)
    end
    self._scroll_text_w = nil
    self._scroll_text_cache = nil
    self._scroll_w = nil
    self._scroll_h = nil
end

function NeoScreen:_ensure_scroll_widget(width, height)
    if not ok_stw then return end
    local text = type(self.scroll_text) == "string" and self.scroll_text or ""
    if text == "" then
        self:_free_scroll_widget()
        return
    end
    local needs_new = self._scroll_text_w == nil
        or self._scroll_text_cache ~= text
        or self._scroll_w ~= width
        or self._scroll_h ~= height
    if not needs_new then return end
    self:_free_scroll_widget()
    self._scroll_text_cache = text
    self._scroll_w = width
    self._scroll_h = height
    self._scroll_text_w = ScrollTextWidget:new{
        text      = text,
        top_line_num = self._scroll_top_line_num,
        face      = Font:getFace("cfont", 17),
        fgcolor   = Blitbuffer.COLOR_BLACK,
        width     = width,
        height    = height,
        dialog    = self,
        alignment = "left",
        justified = false,
    }
    self._scroll_top_line_num = nil
end

function NeoScreen:_point_in_rect(point, rect)
    return rect
        and point.x >= rect.x and point.x < rect.x + rect.w
        and point.y >= rect.y and point.y < rect.y + rect.h
end

function NeoScreen:onZsConfirm()
    if self.button ~= false then
        if self._on_button_action then
            self._on_button_action()
        else
            self:onClose()
        end
    elseif self.dismissable then
        self:onClose()
    end
    return true
end

function NeoScreen:onZsDismiss()
    if self.dismissable then
        self:onClose()
    end
    return true
end

function NeoScreen:paintTo(bb, x, y)
    local L = self._L
    local use_scroll_text = type(self.scroll_text) == "string" and self.scroll_text ~= ""

    local content_y = y + L.content_y
    local content_h = L.content_h
    local cl_x      = x + L.pad
    local cl_w      = L.sw - L.pad * 2
    local SEP_PX    = Screen:scaleBySize(8)
    local HDR_GAP   = Screen:scaleBySize(6)
    local ITEM_GAP  = Screen:scaleBySize(4)

    local logo_h = use_scroll_text and 0 or content_h
    local item_widgets = {}
    local hdr_tw, hdr_h

    if not use_scroll_text and self.changelog and #self.changelog > 0 then
        hdr_tw = TextWidget:new{
            text    = _("What's New"),
            face    = Font:getFace("cfont", 18),
            bold    = true,
            padding = 0,
        }
        hdr_h = hdr_tw:getSize().h

        local items_h = 0
        for _i, item in ipairs(self.changelog) do
            local b_tw = TextBoxWidget:new{
                text      = "\u{2022} " .. item,
                face      = Font:getFace("cfont", 17),
                width     = cl_w,
                alignment = "left",
            }
            local bh = b_tw:getSize().h
            table.insert(item_widgets, { widget = b_tw, h = bh })
            items_h = items_h + bh + ITEM_GAP
        end

        local cl_total = 1 + SEP_PX + hdr_h + HDR_GAP + items_h + SEP_PX
        logo_h = math.max(0, content_h - cl_total)
    end

    local has_cl = hdr_tw ~= nil
    self._show_title_icon = false
    if has_cl then
        local min_logo_with_changelog = Screen:scaleBySize(140)
        local logo_candidate = math.floor(math.min(L.sw - L.pad * 2, logo_h - L.pad * 2))
        if logo_candidate < min_logo_with_changelog then
            logo_h = 0
            self._show_title_icon = true
        end
    end

    bb:paintRect(x, y, L.sw, L.sh, Blitbuffer.COLOR_WHITE)

    if self.title and L.title_h > 0 then
        local tw = TextWidget:new{
            text    = self.title,
            face    = Font:getFace("cfont", 26),
            bold    = true,
            padding = 0,
        }
        local tsz = tw:getSize()
        local show_inline_icon = self.title_icon == true or self._show_title_icon
        local icon_gap = Screen:scaleBySize(8)
        local icon_sz  = show_inline_icon and tsz.h or 0
        local total_w  = tsz.w + (show_inline_icon and (icon_sz + icon_gap) or 0)
        local base_x   = x + math.floor((L.sw - total_w) / 2)
        local text_y   = y + math.floor((L.title_h - tsz.h) / 2)

        if show_inline_icon and ImageWidget and _plugin_root ~= "" then
            pcall(function()
                local iw = ImageWidget:new{
                    file   = _plugin_root .. "/icons/neo_ui.svg",
                    width  = icon_sz,
                    height = icon_sz,
                    alpha  = true,
                }
                iw:paintTo(bb, base_x, text_y)
                iw:free()
                if Screen.night_mode then
                    bb:invertRect(base_x, text_y, icon_sz, icon_sz)
                end
            end)
        end

        tw:paintTo(bb, base_x + (show_inline_icon and (icon_sz + icon_gap) or 0), text_y)
        tw:free()
    end

    if self.subtitle and L.subtitle_h > 0 then
        local sub_y = y + L.title_h + L.sep_h
        local sw2 = TextWidget:new{
            text    = self.subtitle,
            face    = Font:getFace("cfont", 22),
            bold    = false,
            padding = 0,
        }
        local ssz = sw2:getSize()
        sw2:paintTo(bb,
            x + math.floor((L.sw - ssz.w) / 2),
            sub_y + math.floor((L.subtitle_h - ssz.h) / 2))
        sw2:free()
    end

    if not use_scroll_text and ImageWidget and _plugin_root ~= "" then
        local logo    = _plugin_root .. "/icons/neo_ui.svg"
        local logo_sz = has_cl
            and math.floor(math.min(L.sw - L.pad * 2, logo_h - L.pad * 2))
            or  math.floor(math.min(L.sw - L.pad * 4, logo_h - L.pad * 4) * 0.75)
        if logo_sz > 0 then
            pcall(function()
                local iw = ImageWidget:new{
                    file   = logo,
                    width  = logo_sz,
                    height = logo_sz,
                    alpha  = true,
                }
                local isz = iw:getSize()
                local lx = x + math.floor((L.sw - isz.w) / 2)
                local ly = content_y + math.floor((logo_h - isz.h) / 2)
                iw:paintTo(bb, lx, ly)
                iw:free()
                if Screen.night_mode then
                    bb:invertRect(lx, ly, isz.w, isz.h)
                end
            end)
        end
    end

    if hdr_tw then
        local cl_y = content_y + logo_h
        bb:paintRect(x + L.pad, cl_y, cl_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        cl_y = cl_y + 1 + SEP_PX
        hdr_tw:paintTo(bb, cl_x, cl_y)
        hdr_tw:free()
        cl_y = cl_y + hdr_h + HDR_GAP
        for _i, entry in ipairs(item_widgets) do
            entry.widget:paintTo(bb, cl_x, cl_y)
            entry.widget:free()
            cl_y = cl_y + entry.h + ITEM_GAP
        end
    else
        for _i, entry in ipairs(item_widgets) do entry.widget:free() end
    end

    self._scroll_rect = nil
    if use_scroll_text then
        local scroll_pad = Screen:scaleBySize(4)
        local scroll_x = x + L.pad
        local scroll_y = content_y + scroll_pad
        local scroll_w = cl_w
        local scroll_h = math.max(Screen:scaleBySize(40), content_h - scroll_pad * 2)
        self:_ensure_scroll_widget(scroll_w, scroll_h)
        if self._scroll_text_w then
            self._scroll_text_w:paintTo(bb, scroll_x, scroll_y)
            self._scroll_rect = {
                x = scroll_x,
                y = scroll_y,
                w = scroll_w,
                h = scroll_h,
            }
        end
    end

    self._btn_rect       = nil
    self._later_btn_rect = nil
    if self.button ~= false and L.btn_h > 0 then
        local btn_h    = Screen:scaleBySize(54)
        local corner_r = Screen:scaleBySize(10)
        local btn_y    = y + L.btn_y + math.floor((L.btn_h - btn_h) / 2)

        if self.later_button then
            local gap    = Screen:scaleBySize(16)
            local btn_w  = Screen:scaleBySize(200)
            local base_x = x + math.floor((L.sw - btn_w * 2 - gap) / 2)
            local bw     = Screen:scaleBySize(2)  -- outline border thickness

            local lbx       = base_x
            local later_lbl = (type(self.later_button) == "string" and self.later_button ~= "")
                and self.later_button or _("Later")
            self._later_btn_rect = NeoButton.paintOutlined(
                bb, lbx, btn_y, btn_w, btn_h, later_lbl, 22, corner_r, bw)

            local pbx      = base_x + btn_w + gap
            local prim_lbl = (type(self.button) == "string" and self.button ~= "")
                and self.button or _("Get Started")
            self._btn_rect = NeoButton.paintFilled(
                bb, pbx, btn_y, btn_w, btn_h, prim_lbl, 22, corner_r)
        else
            local lbl   = (type(self.button) == "string" and self.button ~= "")
                and self.button or _("Get Started")
            local btn_w = Screen:scaleBySize(240)
            local btn_x = x + math.floor((L.sw - btn_w) / 2)
            self._btn_rect = NeoButton.paintFilled(
                bb, btn_x, btn_y, btn_w, btn_h, lbl, 22, corner_r)
        end
    end
end

function NeoScreen:_onSwipe(ges)
    if self._scroll_text_w and self:_point_in_rect(ges.pos, self._scroll_rect) then
        self._scroll_text_w:onScrollText(nil, ges)
        return true
    end
    if self.dismissable then self:onClose() end
    return true
end

function NeoScreen:_onTap(ges)
    local p  = ges.pos
    local L  = self._L
    local br = self._btn_rect
    local lr = self._later_btn_rect

    if lr and p.x >= lr.x and p.x < lr.x + lr.w
           and p.y >= lr.y and p.y < lr.y + lr.h then
        self:onClose()
        return true
    end

    if br and p.x >= br.x and p.x < br.x + br.w
           and p.y >= br.y and p.y < br.y + br.h then
        if self._on_button_action then
            self._on_button_action()
        else
            self:onClose()
        end
        return true
    end

    if self._scroll_text_w and self:_point_in_rect(p, self._scroll_rect) then
        self._scroll_text_w:onTapScrollText(nil, ges)
        return true
    end

    if L.btn_h > 0 and p.y >= L.btn_y then
        if self.dismissable then self:onClose() end
        return true
    end

    return true
end

function NeoScreen:update(opts)
    local text_changed = false
    if opts.subtitle ~= nil then self.subtitle = opts.subtitle end
    if opts.title ~= nil then self.title = opts.title end
    if opts.changelog ~= nil then self.changelog = opts.changelog end
    if opts.scroll_text ~= nil then
        self.scroll_text = opts.scroll_text
        text_changed = true
    end
    if opts.button ~= nil then self.button = opts.button end
    if opts.later_button ~= nil then self.later_button = opts.later_button end
    if opts.dismissable ~= nil then self.dismissable = opts.dismissable end
    if opts.on_button ~= nil then self._on_button_action = opts.on_button end
    if text_changed then
        if opts.preserve_scroll and self._scroll_text_w
            and self._scroll_text_w.text_widget
            and self._scroll_text_w.text_widget.virtual_line_num then
            self._scroll_top_line_num = self._scroll_text_w.text_widget.virtual_line_num
        else
            self._scroll_top_line_num = nil
        end
        self:_free_scroll_widget()
    end
    self:_computeLayout()
    UIManager:setDirty(self, function()
        return "partial", self.dimen
    end)
end

function NeoScreen:onShow()
    logger.info("NeoScreen:onShow dimen=", self.dimen)
    UIManager:setDirty(self, function()
        return "flashui", self.dimen
    end)
end

function NeoScreen:onClose()
    self:_free_scroll_widget()
    UIManager:setDirty(nil, "full")
    UIManager:close(self)
    _G.__NEO_QUICKSTART_JUST_CLOSED = true
    UIManager:scheduleIn(1.5, function() _G.__NEO_QUICKSTART_JUST_CLOSED = nil end)
    package.loaded["common/neo_screen"] = nil
    if self.on_close then
        self.on_close()
    end
end

return NeoScreen
