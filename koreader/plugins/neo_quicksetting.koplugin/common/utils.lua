local M = {}

function M.deepcopy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for k, v in pairs(value) do
        result[M.deepcopy(k)] = M.deepcopy(v)
    end
    return result
end

local function _is_array(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

function M.deepmerge(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return src
    end

    if _is_array(dst) then
        return dst
    end

    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            M.deepmerge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = M.deepcopy(v)
        end
    end

    return dst
end

function M.set_at_path(tbl, path, value)
    local node = tbl
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end
    node[path[#path]] = value
end

function M.resolveLocalIcon(icons_dir, name)
    if not icons_dir or not name then return nil end
    local lfs = require("libs/libkoreader-lfs")
    for _, ext in ipairs({ ".svg", ".png" }) do
        local p = icons_dir .. name .. ext
        if lfs.attributes(p, "mode") == "file" then return p end
    end
    return nil
end

function M.getUserIconsDir()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return nil end
    return DataStorage:getDataDir() .. "/icons/"
end

local _custom_icons_enabled
function M.isCustomIconsEnabled()
    if _custom_icons_enabled ~= nil then return _custom_icons_enabled end
    _custom_icons_enabled = false
    pcall(function()
        local ConfigManager = require("config/manager")
        local cfg = ConfigManager.load()
        if cfg and cfg.features and cfg.features.custom_icons_enabled == true then
            _custom_icons_enabled = true
        end
    end)
    return _custom_icons_enabled
end

function M.resolveIcon(plugin_icons_dir, name)
    if not name then return nil end
    if M.isCustomIconsEnabled() then
        local user_dir = M.getUserIconsDir()
        if user_dir then
            local p = M.resolveLocalIcon(user_dir, name)
            if p then return p end
        end
    end
    if plugin_icons_dir then
        local p = M.resolveLocalIcon(plugin_icons_dir, name)
        if p then return p end
        
        p = M.resolveLocalIcon(plugin_icons_dir .. "default_ico/", name)
        if p then return p end
    end
    
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then
        local builtin_dir = lfs.currentdir() .. "/resources/icons/mdlight/"
        local p = M.resolveLocalIcon(builtin_dir, name)
        if p then return p end
    end
    
    return nil
end

function M.registerPluginIcons(icons_dir, icons, copy_to_user_dir)
    if not icons_dir or type(icons) ~= "table" then return end
    pcall(function()
        local lfs = require("libs/libkoreader-lfs")
        local user_icons_dir = M.isCustomIconsEnabled() and M.getUserIconsDir() or nil

        if copy_to_user_dir then
            pcall(function()
                local DataStorage = require("datastorage")
                local ffiutil = require("ffi/util")
                local dest_icons_dir = DataStorage:getDataDir() .. "/icons"
                if lfs.attributes(dest_icons_dir, "mode") ~= "directory" then
                    lfs.mkdir(dest_icons_dir)
                end
                for name, filename in pairs(icons) do
                    local ext = filename:match("%.[^%.]+$") or ".svg"
                    local dst = dest_icons_dir .. "/" .. name .. ext
                    if lfs.attributes(dst, "mode") ~= "file" then
                        local src = icons_dir .. filename
                        if lfs.attributes(src, "mode") == "file" then
                            ffiutil.copyFile(src, dst)
                        end
                    end
                end
            end)
        end

        local iw = require("ui/widget/iconwidget")
        local iw_init = rawget(iw, "init")
        if type(iw_init) ~= "function" then return end
        local icons_path, icons_dirs
        for i = 1, 64 do
            local uname, uval = debug.getupvalue(iw_init, i)
            if uname == nil then break end
            if uname == "ICONS_PATH" and type(uval) == "table" then
                icons_path = uval
            elseif uname == "ICONS_DIRS" and type(uval) == "table" then
                icons_dirs = uval
            end
            if icons_path and icons_dirs then break end
        end
        if icons_dirs and copy_to_user_dir then
            pcall(function()
                local DataStorage = require("datastorage")
                local user_dir = DataStorage:getDataDir() .. "/icons"
                local found = false
                for _, d in ipairs(icons_dirs) do
                    if d == user_dir then found = true; break end
                end
                if not found then table.insert(icons_dirs, 1, user_dir) end
            end)
        end
        if not icons_path then return end
        for name, filename in pairs(icons) do
            if not icons_path[name] then
                local user_p = user_icons_dir and M.resolveLocalIcon(user_icons_dir, name) or nil
                if user_p then
                    icons_path[name] = user_p
                else
                    local p = icons_dir .. filename
                    if lfs.attributes(p, "mode") == "file" then
                        icons_path[name] = p
                    end
                end
            end
        end
    end)
end

function M.overrideIcons(overrides)
    local lfs = require("libs/libkoreader-lfs")
    local user_icons_dir = M.isCustomIconsEnabled() and M.getUserIconsDir() or nil
    local valid = {}
    for name, path in pairs(overrides) do
        local user_p = user_icons_dir and M.resolveLocalIcon(user_icons_dir, name) or nil
        local chosen = user_p or path
        if lfs.attributes(chosen, "mode") == "file" then
            valid[name] = chosen
        end
    end
    if not next(valid) then return end

    local iw = require("ui/widget/iconwidget")
    local orig_init = iw.init
    function iw:init()
        orig_init(self)
        if valid[self.icon] then
            self.file = valid[self.icon]
        end
    end
end

local _C_cache
local function _C(ctx, msgid)
    if not _C_cache then
        local _cg = rawget(_G, "C_")
        if type(_cg) == "function" then
            _C_cache = _cg
        else
            local ok_gt, gt = pcall(require, "gettext")
            if ok_gt and gt and type(gt.pgettext) == "function" then
                _C_cache = function(c, m) return gt.pgettext(c, m) end
            else
                _C_cache = function(_, m) return m end
            end
        end
    end
    return _C_cache(ctx, msgid)
end

function M.formatPageCount(pages, long)
    local ctx = long and "page_count_long" or "page_count"
    local msgid = long and "pages" or "p."
    return tostring(pages) .. "\u{00A0}" .. _C(ctx, msgid)
end

function M.getBadgeInset(r)
    return math.floor(r * 0.40)
end

function M.getBadgeScale(config)
    local sz = type(config) == "table"
        and type(config.browser_cover_badges) == "table"
        and config.browser_cover_badges.badge_size
    if sz == "extra_large" then return 1.50 end
    if sz == "large"       then return 1.20 end
    if sz == "normal"      then return 1.10 end
    return 1.0
end

function M.getBadgeColor(config)
    local Blitbuffer = require("ffi/blitbuffer")
    local c = type(config) == "table"
        and type(config.browser_cover_badges) == "table"
        and config.browser_cover_badges.badge_color
    if type(c) == "table" then
        local r = math.max(0, math.min(255, tonumber(c[1]) or 0))
        local g = math.max(0, math.min(255, tonumber(c[2]) or 0))
        local b = math.max(0, math.min(255, tonumber(c[3]) or 0))
        return Blitbuffer.ColorRGB32(r, g, b, 255)
    end
    return Blitbuffer.COLOR_BLACK
end

function M.getBadgeTextColor(config)
    local Blitbuffer = require("ffi/blitbuffer")
    local c = type(config) == "table"
        and type(config.browser_cover_badges) == "table"
        and config.browser_cover_badges.badge_color
    if c == nil or (type(c) == "table" and c[1] == 0 and c[2] == 0 and c[3] == 0) then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_BLACK
end

function M.getIconPickerList(plugin_root, excluded)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or not lfs then return {} end
    local seen = {}
    local all  = {}
    local function addDir(dir, filter)
        if not dir then return end
        dir = dir:match("^(.*[^/])/*$") or dir  -- strip trailing slash
        if lfs.attributes(dir, "mode") ~= "directory" then return end
        
        local function traverse(current_dir, rel_path)
            local entries = {}
            local subdirs = {}
            for f in lfs.dir(current_dir) do
                if f ~= "." and f ~= ".." then
                    local full_path = current_dir .. "/" .. f
                    local mode = lfs.attributes(full_path, "mode")
                    if mode == "directory" then
                        table.insert(subdirs, { path = full_path, rel = rel_path .. f .. "/" })
                    elseif mode == "file" and (f:match("%.svg$") or f:match("%.png$")) and not f:match("%.bak%.svg$") and not f:match("%.bak%.png$") then
                        local name = rel_path .. f:gsub("%.svg$", ""):gsub("%.png$", "")
                        if not seen[name] and (not filter or not filter[name]) then
                            table.insert(entries, { name = name, file = full_path })
                        end
                    end
                end
            end
            table.sort(entries, function(a, b) return a.name < b.name end)
            for _, item in ipairs(entries) do
                seen[item.name] = true
                table.insert(all, item)
            end
            table.sort(subdirs, function(a, b) return a.rel < b.rel end)
            for _, sd in ipairs(subdirs) do
                traverse(sd.path, sd.rel)
            end
        end
        
        traverse(dir, "")
    end
    addDir(plugin_root and plugin_root .. "/icons", excluded)
    addDir(M.getUserIconsDir(), nil)
    addDir(lfs.currentdir() .. "/resources/icons/mdlight", nil)
    return all
end

function M.closeWidgetsAbove(anchor_widget)
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    if not stack or not anchor_widget then return end
    local to_close = {}
    for i = #stack, 1, -1 do
        local entry = stack[i]
        if not entry or entry.widget == anchor_widget then break end
        table.insert(to_close, entry.widget)
    end
    for _, w in ipairs(to_close) do UIManager:close(w) end
end

return M
