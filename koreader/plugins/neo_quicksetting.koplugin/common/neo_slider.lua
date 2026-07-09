
local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
local Math       = require("optmath")
local UIManager  = require("ui/uimanager")
local Screen     = Device.screen


local function paintPill(bb, px, py, pw, ph, color)
    if pw <= 0 or ph <= 0 then return end
    local r = math.min(pw, ph) / 2.0
    for row = 0, ph - 1 do
        local dy    = (row + 0.5) - ph * 0.5
        local inset = 0
        if math.abs(dy) < r then
            inset = math.ceil(r - math.sqrt(r * r - dy * dy))
        end
        local rw = pw - 2 * inset
        if rw > 0 then
            bb:paintRect(px + inset, py + row, rw, 1, color)
        end
    end
end

local function paintCircle(bb, cx, cy, r, color)
    for row = -r, r do
        local half = math.floor(math.sqrt(r * r - row * row) + 0.5)
        if half > 0 then
            bb:paintRect(cx - half, cy + row, half * 2, 1, color)
        end
    end
end


local NeoSlider = {}
NeoSlider.__index = NeoSlider

function NeoSlider:new(o)
    local obj = setmetatable(o or {}, self)
    obj.style         = obj.style         or "neo"
    obj.track_height  = obj.track_height  or Screen:scaleBySize(1)
    obj.fill_height   = obj.fill_height   or Screen:scaleBySize(6)
    obj.knob_radius   = obj.knob_radius   or Screen:scaleBySize(16.5)
    obj.fill_color    = obj.fill_color    or Blitbuffer.COLOR_BLACK
    obj.track_color   = obj.track_color   or obj.fill_color
    obj.knob_color    = obj.knob_color    or Blitbuffer.COLOR_BLACK
    obj.knob_bg_color = obj.knob_bg_color or Blitbuffer.COLOR_WHITE
    local knob_d = obj.knob_radius * 2
    obj.height = knob_d + Screen:scaleBySize(6)
    obj.dimen = Geom:new{ w = obj.width or 0, h = obj.height }
    obj._value = math.max(obj.value_min,
        math.min(obj.value_max,
        Math.round(obj.value or obj.value_min)))
    return obj
end

function NeoSlider:_trackBounds()
    local r = self.knob_radius
    return r, (self.width or 0) - r
end

function NeoSlider:_valueToX(v)
    local x0, x1 = self:_trackBounds()
    local range = self.value_max - self.value_min
    if range == 0 then return x0 end
    return x0 + (v - self.value_min) / range * (x1 - x0)
end

function NeoSlider:_xToValue(local_x)
    local x0, x1 = self:_trackBounds()
    local frac = (local_x - x0) / math.max(1, x1 - x0)
    frac = math.max(0, math.min(1, frac))
    return math.max(self.value_min,
        math.min(self.value_max,
        Math.round(self.value_min + frac * (self.value_max - self.value_min))))
end

function NeoSlider:getValue()
    return self._value
end

function NeoSlider:setValue(v)
    self._value = math.max(self.value_min,
        math.min(self.value_max, Math.round(v)))
end

-- Completely sychronous positioning mirroring the fluid main.lua implementation
function NeoSlider:applyPosition(abs_x)
    local local_x = abs_x - (self.dimen and self.dimen.x or 0)
    local new_val = self:_xToValue(local_x)

    if new_val ~= self._value then
        self._value = new_val
        if self.on_change then
            -- Delayed execution component removed to prevent lag on fast panning gestures
            self.on_change(new_val)
        end
    end
end

function NeoSlider:dirtyDimen()
    return self.dimen
end

function NeoSlider:hitTest(pos)
    return self.dimen ~= nil and pos:intersectWith(self.dimen)
end

function NeoSlider:getSize()
    return self.dimen
end

function NeoSlider:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local w = self.width or 0
    local h = self.height

    if self.style == "progress_bar" or self.style == "notched" or self.style == "square_notched" then
        local r = math.max(0, math.floor(h / 2))
        local border_sz = Screen:scaleBySize(1)
        local range = self.value_max - self.value_min

        if self.style == "notched" or self.style == "square_notched" then
            local is_square = (self.style == "square_notched")
            local segments = 25
            if range > 0 and range <= 35 then segments = range end
            local gap = is_square and 0 or Screen:scaleBySize(3)
            local block_r = is_square and 0 or r

            local block_w = math.floor((w - gap * (segments - 1)) / segments)
            local perc = range > 0 and (self._value - self.value_min) / range or 0
            local active_segments = math.floor(perc * segments + 0.5)

            for i = 1, segments do
                local bx = x + (i - 1) * (block_w + gap)
                local is_active = (i <= active_segments)
                local color = is_active and self.fill_color or self.knob_bg_color

                bb:paintRoundedRect(math.floor(bx), math.floor(y), block_w, h, color, block_r)
                bb:paintBorder(math.floor(bx), math.floor(y), block_w, h, border_sz, Blitbuffer.COLOR_DARK_GRAY, block_r)
            end
            return
        end

        bb:paintRoundedRect(x, y, w, h, self.knob_bg_color, r)
        bb:paintBorder(x, y, w, h, border_sz, Blitbuffer.COLOR_DARK_GRAY, r)

        local m_h = Screen:scaleBySize(2)
        local m_v = Screen:scaleBySize(2)
        local fill_x = x + m_h + border_sz
        local fill_y = y + m_v + border_sz
        local fill_width = w - 2 * (m_h + border_sz)
        local fill_height = h - 2 * (m_v + border_sz)

        if fill_width > 0 and fill_height > 0 then
            local perc = range > 0 and (self._value - self.value_min) / range or 0
            local inner_w = math.ceil(fill_width * perc)
            if inner_w > 0 then
                local fill_r = math.max(0, math.floor(fill_height / 2))
                bb:paintRoundedRect(math.floor(fill_x), math.floor(fill_y), inner_w, fill_height, self.fill_color, fill_r)
            end
        end
        return
    end

    local th = self.track_height
    local r = self.knob_radius

    bb:paintRect(x, y, w, h, self.knob_bg_color)

    local track_cy = math.floor(y + h / 2)
    local track_y = track_cy - math.floor(th / 2)

    paintPill(bb, x, track_y, w, th, self.track_color)

    local fh = self.fill_height
    local fill_y = track_cy - math.floor(fh / 2)
    local knob_x = math.floor(x + self:_valueToX(self._value))
    local range = self.value_max - self.value_min
    local frac = range > 0 and (self._value - self.value_min) / range or 0
    local fill_w = Math.round(frac * w)
    if fill_w > 0 then
        paintPill(bb, x, fill_y, fill_w, fh, self.fill_color)
    end

    if not self.hide_knob then
        paintCircle(bb, knob_x, track_cy, r, self.knob_bg_color)
        paintCircle(bb, knob_x, track_cy, r - Screen:scaleBySize(2), self.knob_color)
    end
end

function NeoSlider:_knobAbsX()
    return math.floor((self.dimen and self.dimen.x or 0) + self:_valueToX(self._value))
end

function NeoSlider:_isNearKnob(abs_x)
    return math.abs(abs_x - self:_knobAbsX()) <= self.knob_radius * 4
end

function NeoSlider:handleTap(ges)
    if not self.dimen or not ges.pos:intersectWith(self.dimen) then return false end
    self:applyPosition(ges.pos.x)
    return true
end

function NeoSlider:handlePan(ges, show_parent)
    if self._dragging then
        self:applyPosition(ges.pos.x)
        if show_parent then
            UIManager:setDirty(show_parent, "ui", self:dirtyDimen())
        end
        return true
    end

    if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
    local dir = ges.direction
    if dir == "north" or dir == "south" then return false end

    if self.style == "neo" or self.style == "classic" then
        if not self:_isNearKnob(ges.pos.x) then return false end
    end

    self._dragging = true
    self.hide_knob = false
    self:applyPosition(ges.pos.x)
    if show_parent then
        UIManager:setDirty(show_parent, "ui", self:dirtyDimen())
    end
    return true
end

function NeoSlider:handlePanRelease(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    self:applyPosition(ges.pos.x)
    if show_parent then
        UIManager:setDirty(show_parent, "ui", self.dimen)
    end
    return true
end

local function isHorizontalish(dir)
    return dir == "east" or dir == "west"
        or dir == "northeast" or dir == "northwest"
        or dir == "southeast" or dir == "southwest"
end

local function hSign(dir)
    if dir == "east" or dir == "northeast" or dir == "southeast" then
        return 1
    end
    return -1
end

function NeoSlider:handleSwipe(ges, show_parent, dirty_dimen)
    if not isHorizontalish(ges.direction) then return false end
    if not self._dragging then
        if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
        if not self:_isNearKnob(ges.pos.x) then return false end
    end
    local was_dragging = self._dragging
    self._dragging = false
    self.hide_knob = false
    if not was_dragging then
        local dist = ges.distance or 0
        local end_x = ges.pos.x + hSign(ges.direction) * dist
        self:applyPosition(end_x)
    else
        if show_parent then
            UIManager:setDirty(show_parent, "ui", self.dimen)
        end
    end
    return true
end

function NeoSlider:handleMultiSwipe(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    if show_parent then
        UIManager:setDirty(show_parent, "ui", self.dimen)
    end
    return true
end

function NeoSlider.installTouchMenuHooks(TouchMenu, opts)
    local in_panel = opts.in_panel_mode
    local get_sl = opts.get_sliders
    local is_locked = opts.is_locked
    local swipe_fb = opts.swipe_fallback
    local mswipe_fb = opts.multiswipe_fallback

    function TouchMenu:onPanCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        if is_locked(self) then
            self._qs_opening_pan = true
            return
        end
        self._qs_opening_pan = false
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePan(ges_ev, self) then return true end
        end
    end

    function TouchMenu:onPanReleaseCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        if is_locked(self) or self._qs_opening_pan then
            self._qs_opening_pan = false
            return
        end
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePanRelease(ges_ev, self, self.dimen) then return true end
        end
    end

    local orig_onSwipe = TouchMenu.onSwipe
    function TouchMenu:onSwipe(arg, ges_ev)
        if in_panel(self) then
            if not is_locked(self) then
                for _, sl in ipairs(get_sl(self)) do
                    if sl:handleSwipe(ges_ev, self, self.dimen) then return true end
                end
                if swipe_fb then swipe_fb(self, ges_ev) end
            end
            return true
        end
        if orig_onSwipe then return orig_onSwipe(self, arg, ges_ev) end
    end

    local orig_onMultiSwipe = TouchMenu.onMultiSwipe
    function TouchMenu:onMultiSwipe(arg, ges_ev)
        if in_panel(self) then
            for _, sl in ipairs(get_sl(self)) do
                if sl:handleMultiSwipe(ges_ev, self, self.dimen) then return true end
            end
            if mswipe_fb then mswipe_fb(self, ges_ev) end
            return true
        end
        if orig_onMultiSwipe then return orig_onMultiSwipe(self, arg, ges_ev) end
    end
end

function NeoSlider:handleEvent(_event)
    return false
end

return NeoSlider
