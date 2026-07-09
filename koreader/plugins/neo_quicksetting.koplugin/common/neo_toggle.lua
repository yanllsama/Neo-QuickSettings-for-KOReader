
local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
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


local NeoToggle = {}
NeoToggle.__index = NeoToggle

function NeoToggle:new(o)
    local obj   = setmetatable(o or {}, self)
    obj.height  = obj.height or Screen:scaleBySize(28)
    obj.width   = obj.width  or Screen:scaleBySize(56)
    obj._border = Screen:scaleBySize(2)  -- border width for OFF state
    obj._pad    = Screen:scaleBySize(3)  -- gap between knob edge and pill edge
    obj._knob_r = math.max(1, math.floor(obj.height / 2) - obj._pad)
    obj._value  = obj.value and true or false
    obj.dimen   = Geom:new{ w = obj.width, h = obj.height }
    return obj
end

function NeoToggle:getValue()
    if self.value_func then return self.value_func() end
    return self._value
end

function NeoToggle:setValue(is_on)
    self._value = is_on and true or false
end

function NeoToggle:toggle()
    self._value = not self._value
    if self.on_change then self.on_change(self._value) end
end

function NeoToggle:hitTest(pos)
    return self.dimen ~= nil and pos:intersectWith(self.dimen)
end

function NeoToggle:getSize()
    return self.dimen
end


function NeoToggle:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local w   = self.width
    local h   = self.height
    local kr  = self._knob_r
    local pad = self._pad
    local bw  = self._border
    local cy  = y + math.floor(h / 2)

    local is_on = self.value_func and self.value_func() or self._value

    if is_on then
        paintPill(bb, x, y, w, h, Blitbuffer.COLOR_BLACK)
        paintCircle(bb, x + w - pad - kr, cy, kr, Blitbuffer.COLOR_WHITE)
    else
        paintPill(bb, x, y, w, h, Blitbuffer.COLOR_BLACK)
        paintPill(bb, x + bw, y + bw, w - 2 * bw, h - 2 * bw, Blitbuffer.COLOR_WHITE)
        paintCircle(bb, x + bw + pad + kr, cy, kr, Blitbuffer.COLOR_DARK_GRAY)
    end
end

function NeoToggle:handleEvent(_event)
    return false
end

return NeoToggle
