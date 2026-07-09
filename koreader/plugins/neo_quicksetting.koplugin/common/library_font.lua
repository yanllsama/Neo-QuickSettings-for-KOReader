local Font = require("ui/font")

local M = {}

local DEFAULT_FACE = "cfont"
local DEFAULT_BASE_SIZE = 18

local function get_cfg()
    local cached = rawget(_G, "__NEO_UI_LIBRARY_FONT_CFG")
    if type(cached) == "table" then
        return cached
    end

    local p = rawget(_G, "__NEO_UI_PLUGIN")
    if p and type(p.config) == "table" and type(p.config.library_font) == "table" then
        return p.config.library_font
    end

    local g = rawget(_G, "G_reader_settings")
    if g and type(g.readSetting) == "function" then
        local cfg = g:readSetting("neo_ui_config")
        if type(cfg) == "table" and type(cfg.library_font) == "table" then
            return cfg.library_font
        end
    end

    return nil
end

function M.getBaseSize()
    local cfg = get_cfg()
    local sz = cfg and tonumber(cfg.font_size) or DEFAULT_BASE_SIZE
    if not sz then sz = DEFAULT_BASE_SIZE end
    sz = math.floor(sz + 0.5)
    if sz < 10 then sz = 10 end
    if sz > 40 then sz = 40 end
    return sz
end

function M.getScale(base_nominal)
    base_nominal = tonumber(base_nominal) or DEFAULT_BASE_SIZE
    if base_nominal <= 0 then base_nominal = DEFAULT_BASE_SIZE end
    return M.getBaseSize() / base_nominal
end

function M.scaleValue(value, base_nominal)
    if type(value) ~= "number" then return value end
    local scaled = value * M.getScale(base_nominal)
    return math.max(1, math.floor(scaled + 0.5))
end

function M.getFontName()
    local cfg = get_cfg()
    local face = cfg and cfg.font_face
    if not face or face == "" or face == "default" then
        return DEFAULT_FACE
    end
    return face
end

function M.getFace(size)
    return Font:getFace(M.getFontName(), math.max(1, math.floor(size)))
end

return M
