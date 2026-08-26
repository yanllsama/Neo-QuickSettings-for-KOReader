
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
    obj.track_height  = obj.track_height  or Screen:scaleBySize(1)   -- very thin rail
    obj.fill_height   = obj.fill_height   or Screen:scaleBySize(6)   -- thicker filled bar
    obj.knob_radius   = obj.knob_radius   or Screen:scaleBySize(16.5)
    obj.fill_color    = obj.fill_color    or Blitbuffer.COLOR_BLACK
    obj.track_color   = obj.track_color   or obj.fill_color          -- same color: no flash on repaint
    obj.knob_color    = obj.knob_color    or Blitbuffer.COLOR_BLACK
    obj.knob_bg_color = obj.knob_bg_color or Blitbuffer.COLOR_WHITE
    local knob_d  = obj.knob_radius * 2
    obj.height    = knob_d + Screen:scaleBySize(6)
    obj.dimen     = Geom:new{ w = obj.width or 0, h = obj.height }
    obj._value    = math.max(obj.value_min,
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
    local range   = self.value_max - self.value_min
    if range == 0 then return x0 end
    return x0 + (v - self.value_min) / range * (x1 - x0)
end

function NeoSlider:_xToValue(local_x)
    local x0, x1 = self:_trackBounds()
    local frac    = (local_x - x0) / math.max(1, x1 - x0)
    frac          = math.max(0, math.min(1, frac))
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

function NeoSlider:applyPosition(abs_x)
    self._prev_knob_abs_x = self:_knobAbsX()
    local local_x = abs_x - (self.dimen and self.dimen.x or 0)
    local new_val = self:_xToValue(local_x)
    if new_val ~= self._value then
        self._value = new_val
        if self.on_change then self.on_change(new_val) end
    elseif self._dragging and self.on_change then
        self.on_change(new_val)
    end
end

function NeoSlider:dirtyDimen()
    if not self.dimen or not self._prev_knob_abs_x then return self.dimen end
    if self.style ~= "neo" and self.style ~= nil then
        return self.dimen
    end
    local cur_x  = self:_knobAbsX()
    local prev_x = self._prev_knob_abs_x
    local pad    = self.knob_radius + 1
    local x0 = math.max(self.dimen.x, math.min(cur_x, prev_x) - pad)
    local x1 = math.min(self.dimen.x + self.dimen.w, math.max(cur_x, prev_x) + pad)
    return Geom:new{
        x = x0,
        y = self.dimen.y,
        w = x1 - x0,
        h = self.dimen.h,
    }
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

    local w  = self.width or 0
    local h  = self.height
    
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
    local r  = self.knob_radius
    local track_cy = math.floor(y + h / 2)
    local track_y  = track_cy - math.floor(th / 2)
    local fh     = self.fill_height
    local fill_y = track_cy - math.floor(fh / 2)
    local knob_x = math.floor(x + self:_valueToX(self._value))
    local range  = self.value_max - self.value_min
    local frac   = range > 0 and (self._value - self.value_min) / range or 0
    local fill_w = Math.round(frac * w)

    if self.style == "outline" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local border_sz = Screen:scaleBySize(2)
        local track_h = Screen:scaleBySize(8)
        local track_r = math.floor(track_h / 2)
        local ty = track_cy - track_r
        bb:paintBorder(x, ty, w, track_h, border_sz, self.track_color, track_r)
        if fill_w > 0 then
            bb:paintRoundedRect(x, ty, fill_w, track_h, self.fill_color, track_r)
        end
        if not self.hide_knob then
            paintCircle(bb, knob_x, track_cy, r, self.track_color)
            paintCircle(bb, knob_x, track_cy, r - border_sz, self.knob_bg_color)
        end
        return
    end

    if self.style == "fader" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        paintPill(bb, x, track_y, w, th, self.track_color)
        if not self.hide_knob then
            local fader_w = Screen:scaleBySize(8)
            local fader_h = r * 2
            local fx = knob_x - math.floor(fader_w / 2)
            local fy = track_cy - r
            bb:paintRoundedRect(fx, fy, fader_w, fader_h, self.knob_color, math.floor(fader_w/2))
        end
        return
    end

    if self.style == "dots" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local dot_r = Screen:scaleBySize(2)
        local gap = Screen:scaleBySize(12)
        local segments = math.floor(w / gap)
        if segments < 1 then segments = 1 end
        local spacing = w / segments
        for i = 0, segments do
            local dx = math.floor(x + i * spacing)
            paintCircle(bb, dx, track_cy, dot_r, Blitbuffer.COLOR_DARK_GRAY)
        end
        if fill_w > 0 then
            paintPill(bb, x, fill_y, fill_w, fh, self.fill_color)
        end
        if not self.hide_knob then
            paintCircle(bb, knob_x, track_cy, r, self.knob_bg_color)
            paintCircle(bb, knob_x, track_cy, r - Screen:scaleBySize(2), self.knob_color)
        end
        return
    end

    if self.style == "cyber" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local dash_w = Screen:scaleBySize(2)
        local gap = Screen:scaleBySize(4)
        local segments = math.floor(w / (dash_w + gap))
        if segments < 1 then segments = 1 end
        
        local ty = track_cy - math.floor(th / 2)
        for i = 0, segments do
            local dx = math.floor(x + i * (dash_w + gap))
            bb:paintRect(dx, ty, dash_w, th, Blitbuffer.COLOR_DARK_GRAY)
        end
        if fill_w > 0 then
            local f_segments = math.floor(fill_w / (dash_w + gap))
            for i = 0, f_segments do
                local dx = math.floor(x + i * (dash_w + gap))
                bb:paintRect(dx, fill_y, dash_w, fh, self.fill_color)
            end
        end
        if not self.hide_knob then
            local kw = r
            local kh = r * 2
            local cx = knob_x - math.floor(kw/2)
            local cy = track_cy - math.floor(kh/2)
            bb:paintBorder(cx, cy, kw, kh, Screen:scaleBySize(2), self.knob_color, 0)
            bb:paintRect(cx + Screen:scaleBySize(2), cy + Screen:scaleBySize(2), kw - Screen:scaleBySize(4), kh - Screen:scaleBySize(4), self.knob_bg_color)
        end
        return
    end

    if self.style == "retro" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local th_retro = Screen:scaleBySize(10)
        local track_y_retro = track_cy - math.floor(th_retro / 2)
        
        bb:paintRect(x, track_y_retro, w, th_retro, Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(x, track_y_retro + Screen:scaleBySize(2), w, th_retro - Screen:scaleBySize(4), self.knob_bg_color)
        
        if fill_w > 0 then
            bb:paintRect(x, track_y_retro + Screen:scaleBySize(2), fill_w, th_retro - Screen:scaleBySize(4), self.fill_color)
        end
        
        if not self.hide_knob then
            local kw = Screen:scaleBySize(20)
            local kh = r * 2.2
            local cx = knob_x - math.floor(kw/2)
            local cy = track_cy - math.floor(kh/2)
            
            bb:paintRect(cx, cy, kw, kh, self.knob_bg_color)
            bb:paintBorder(cx, cy, kw, kh, Screen:scaleBySize(2), self.knob_color, 0)
            
            local grip_gap = Screen:scaleBySize(4)
            local grip_x = cx + math.floor(kw/2) - grip_gap
            local grip_y = cy + Screen:scaleBySize(5)
            local grip_h = kh - Screen:scaleBySize(10)
            local grip_w = Screen:scaleBySize(2)
            
            bb:paintRect(grip_x, grip_y, grip_w, grip_h, self.knob_color)
            bb:paintRect(grip_x + grip_gap, grip_y, grip_w, grip_h, self.knob_color)
            bb:paintRect(grip_x + grip_gap * 2, grip_y, grip_w, grip_h, self.knob_color)
        end
        return
    end

    if self.style == "split_rail" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local rail_gap = Screen:scaleBySize(8)
        local t1_y = track_cy - math.floor(rail_gap/2) - th
        local t2_y = track_cy + math.floor(rail_gap/2)
        paintPill(bb, x, t1_y, w, th, self.track_color)
        paintPill(bb, x, t2_y, w, th, self.track_color)
        
        if fill_w > 0 then
            local block_y = t1_y + th
            local block_h = t2_y - block_y
            bb:paintRect(x, block_y, fill_w, block_h, self.fill_color)
        end
        if not self.hide_knob then
            paintCircle(bb, knob_x, track_cy, r, self.track_color)
            paintCircle(bb, knob_x, track_cy, r - Screen:scaleBySize(2), self.knob_bg_color)
            paintCircle(bb, knob_x, track_cy, Screen:scaleBySize(3), self.knob_color)
        end
        return
    end

    if self.style == "stepped_bars" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local gap = Screen:scaleBySize(6)
        local min_h = Screen:scaleBySize(4)
        local max_h = h
        local num_bars = math.max(1, math.floor(w / gap))
        local step_w = Screen:scaleBySize(4)
        
        for i = 0, num_bars do
            local bx = math.floor(x + i * gap)
            local frac_bar = i / num_bars
            local bar_h = math.floor(min_h + frac_bar * (max_h - min_h))
            local by = track_cy + math.floor(max_h / 2) - bar_h
            
            local is_filled = (bx <= knob_x)
            local c = is_filled and self.fill_color or Blitbuffer.COLOR_DARK_GRAY
            bb:paintRect(bx, by, step_w, bar_h, c)
        end
        return
    end

    if self.style == "fluid_pill" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local pill_h = Screen:scaleBySize(24)
        local pill_r = math.floor(pill_h / 2)
        local py = track_cy - pill_r
        
        bb:paintRoundedRect(x, py, w, pill_h, Blitbuffer.COLOR_DARK_GRAY, pill_r)
        
        if fill_w > 0 then
            local fw = math.max(fill_w, pill_h)
            bb:paintRoundedRect(x, py, fw, pill_h, self.fill_color, pill_r)
        end
        return
    end

    if self.style == "battery" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local bw = w - Screen:scaleBySize(8)
        local bh = Screen:scaleBySize(20)
        local by = track_cy - math.floor(bh / 2)
        
        bb:paintBorder(x, by, bw, bh, Screen:scaleBySize(2), self.track_color, Screen:scaleBySize(2))
        
        local nw = Screen:scaleBySize(6)
        local nh = Screen:scaleBySize(10)
        bb:paintRect(x + bw, track_cy - math.floor(nh / 2), nw, nh, self.track_color)
        
        if fill_w > 0 then
            local cell_gap = Screen:scaleBySize(4)
            local cell_w = Screen:scaleBySize(8)
            local num_cells = math.floor(fill_w / (cell_w + cell_gap))
            for i = 0, num_cells do
                local cx = math.floor(x + Screen:scaleBySize(4) + i * (cell_w + cell_gap))
                if cx + cell_w <= x + bw - Screen:scaleBySize(2) then
                    bb:paintRect(cx, by + Screen:scaleBySize(3), cell_w, bh - Screen:scaleBySize(6), self.fill_color)
                end
            end
        end
        return
    end

    if self.style == "piano" then
        bb:paintRect(x, y, w, h, self.knob_bg_color)
        local key_w = Screen:scaleBySize(12)
        local key_h = Screen:scaleBySize(28)
        local black_key_w = Screen:scaleBySize(6)
        local black_key_h = Screen:scaleBySize(16)
        local py = track_cy - math.floor(key_h / 2)
        
        local num_keys = math.floor(w / key_w)
        
        for i = 0, num_keys do
            local kx = math.floor(x + i * key_w)
            local is_filled = (kx <= knob_x)
            
            local color = is_filled and Blitbuffer.COLOR_DARK_GRAY or self.knob_bg_color
            bb:paintRect(kx, py, key_w, key_h, color)
            bb:paintBorder(kx, py, key_w, key_h, Screen:scaleBySize(1), self.track_color, 0)
        end
        
        for i = 0, num_keys - 1 do
            local note = i % 7
            if note ~= 2 and note ~= 6 then
                local bkx = math.floor(x + i * key_w + key_w - black_key_w / 2)
                bb:paintRect(bkx, py, black_key_w, black_key_h, self.track_color)
            end
        end
        return
    end

    -- Default "neo" style
    bb:paintRect(x, y, w, h, self.knob_bg_color)
    paintPill(bb, x, track_y, w, th, self.track_color)
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
    return math.abs(abs_x - self:_knobAbsX()) <= self.knob_radius * 1.5
end


function NeoSlider:handleTap(ges)
    if not self.dimen or not ges.pos:intersectWith(self.dimen) then return false end
    if self:_isNearKnob(ges.pos.x) then return false end
    self:applyPosition(ges.pos.x)
    return true
end

function NeoSlider:handlePan(ges)
    if self._dragging then
        self:applyPosition(ges.pos.x)
        return true
    end
    if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
    local dir = ges.direction
    if dir == "north" or dir == "south" then return false end
    if not self:_isNearKnob(ges.pos.x) then return false end
    self._dragging = true
    self.hide_knob = true
    self:applyPosition(ges.pos.x)
    return true
end

function NeoSlider:handlePanRelease(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    self:applyPosition(ges.pos.x)
    UIManager:setDirty(show_parent, "ui", dirty_dimen)
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
        local dist  = ges.distance or 0
        local end_x = ges.pos.x + hSign(ges.direction) * dist
        self:applyPosition(end_x)
    else
        UIManager:setDirty(show_parent, "ui", dirty_dimen)
    end
    return true
end

function NeoSlider:handleMultiSwipe(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    UIManager:setDirty(show_parent, "ui", dirty_dimen)
    return true
end

function NeoSlider.installTouchMenuHooks(TouchMenu, opts)
    local in_panel  = opts.in_panel_mode
    local get_sl    = opts.get_sliders
    local is_locked = opts.is_locked
    local swipe_fb  = opts.swipe_fallback
    local mswipe_fb = opts.multiswipe_fallback

    function TouchMenu:onPanCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        if is_locked(self) then
            self._qs_opening_pan = true
            return
        end
        self._qs_opening_pan = false  -- clear stale flag once unlocked
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePan(ges_ev) then return true end
        end
    end

    function TouchMenu:onPanReleaseCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        if is_locked(self) or self._qs_opening_pan then
            self._qs_opening_pan = false
            return
        end
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePanRelease(ges_ev, self.show_parent, self.dimen) then return true end
        end
    end

    local orig_onSwipe = TouchMenu.onSwipe
    function TouchMenu:onSwipe(arg, ges_ev)
        if in_panel(self) then
            if not is_locked(self) then
                for _, sl in ipairs(get_sl(self)) do
                    if sl:handleSwipe(ges_ev, self.show_parent, self.dimen) then return true end
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
                if sl:handleMultiSwipe(ges_ev, self.show_parent, self.dimen) then return true end
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
