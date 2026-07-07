local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local Screen = Device.screen
local _ = require("gettext")

local function paintPill(bb, px, py, pw, ph, color, border_color, border_width)
    local r = math.min(pw, ph) / 2.0
    for row = 0, ph - 1 do
        local dy = (row + 0.5) - ph * 0.5
        local inset = 0
        if math.abs(dy) < r then
            inset = math.ceil(r - math.sqrt(r * r - dy * dy))
        end
        local rw = pw - 2 * inset
        if rw > 0 then
            if border_width and border_width > 0 then
                if row < border_width or row >= ph - border_width then
                    bb:paintRect(px + inset, py + row, rw, 1, border_color)
                else
                    bb:paintRect(px + inset, py + row, border_width, 1, border_color)
                    bb:paintRect(px + inset + rw - border_width, py + row, border_width, 1, border_color)
                    bb:paintRect(px + inset + border_width, py + row, rw - 2*border_width, 1, color)
                end
            else
                bb:paintRect(px + inset, py + row, rw, 1, color)
            end
        end
    end
end

local function paintCircle(bb, cx, cy, r, color)
    for dy = -r, r do
        local w = math.floor(math.sqrt(r*r - dy*dy) + 0.5)
        bb:paintRect(cx - w, cy + dy, w * 2, 1, color)
    end
end

local SwipeTrack = Widget:extend{
    width = Screen:scaleBySize(224),
    height = Screen:scaleBySize(44),
    progress = 0,
    show_parent = nil,
    onConfirm = nil,
}

function SwipeTrack:init()
end

function SwipeTrack:onPan(arg, ges)
    if not self.dimen then return end
    local start_x = self.dimen.x + self.height/2
    local range = self.dimen.w - self.height
    local p = (ges.pos.x - start_x) / range
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    self.progress = p
    UIManager:setDirty(self.show_parent, "fast", self.dimen)
end

function SwipeTrack:onPanRelease(arg, ges)
    if not self.dimen then return end
    if self.progress >= 0.55 then
        if self.onConfirm then self.onConfirm() end
    else
        self.progress = 0
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function SwipeTrack:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function SwipeTrack:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    
    paintPill(bb, x, y, self.width, self.height, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY, Screen:scaleBySize(2))
    
    local range = self.width - self.height
    local knob_cx = x + self.height/2 + math.floor(self.progress * range)
    local fill_width = knob_cx - x
    if fill_width > self.height/2 then
        paintPill(bb, x, y, fill_width + self.height/2, self.height, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_GRAY, Screen:scaleBySize(2))
    end
    
    local knob_r = (self.height - Screen:scaleBySize(8)) / 2
    local knob_cy = y + self.height/2
    paintCircle(bb, knob_cx, knob_cy, knob_r, Blitbuffer.COLOR_BLACK)
    
    local arrow_tw = TextWidget:new{
        text = "»",
        face = Font:getFace("cfont", Screen:scaleBySize(12)),
        fgcolor = Blitbuffer.COLOR_WHITE,
    }
    local aw, ah = arrow_tw:getSize().w, arrow_tw:getSize().h
    arrow_tw:paintTo(bb, knob_cx - aw/2, knob_cy - ah/2)
end



local SlideConfirmBox = InputContainer:extend{
    modal = true,
    text = _("Swipe to exit"),
    title = "Emin misiniz?",
    icon = "notice-warning",
    margin = Size.margin.default,
    padding = Size.padding.default,
    on_confirm = function() end,
}

function SlideConfirmBox:init()
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
            }
        }
        self.ges_events.Pan = {
            GestureRange:new{
                ges = "pan",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
            }
        }
        self.ges_events.PanRelease = {
            GestureRange:new{
                ges = "pan_release",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
            }
        }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.track = SwipeTrack:new{
        show_parent = self,
        onConfirm = function()
            self.on_confirm()
            UIManager:close(self)
        end
    }

    local title_tw = TextWidget:new{
        text = self.title,
        face = Font:getFace("cfont", Screen:scaleBySize(12)),
        bold = true,
    }

    local sub_tw = TextWidget:new{
        text = self.text,
        face = Font:getFace("cfont", Screen:scaleBySize(8)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }

    local content = VerticalGroup:new{
        align = "center",
        HorizontalGroup:new{
            align = "center",
            IconWidget:new{ icon = self.icon, alpha = true },
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            title_tw,
        },
        VerticalSpan:new{ width = Size.padding.default },
        sub_tw,
        VerticalSpan:new{ width = Size.padding.large },
        self.track,
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window * 2,
        padding = self.padding * 2,
        content,
    }

    self.movable = MovableContainer:new{
        frame,
        unmovable = true,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }
end

function SlideConfirmBox:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function SlideConfirmBox:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function SlideConfirmBox:onClose()
    UIManager:close(self)
    return true
end

function SlideConfirmBox:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

function SlideConfirmBox:onPan(arg, ges)
    if self.track then self.track:onPan(arg, ges) end
    return true
end

function SlideConfirmBox:onPanRelease(arg, ges)
    if self.track then self.track:onPanRelease(arg, ges) end
    return true
end

return SlideConfirmBox
