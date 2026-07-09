
local M = {}

function M.normPath(p)
    if not p then return p end
    return (p:gsub("^/sdcard/", "/storage/emulated/0/")
             :gsub("^/sdcard$",  "/storage/emulated/0"))
end

function M.getHomeDir()
    local g = rawget(_G, "G_reader_settings")
    local d = g and g:readSetting("home_dir")
    if d and d ~= "" then
        return M.normPath(d:gsub("/*$", ""))
    end
    return nil
end

function M.isHomeRoot(path)
    if not path then return false end
    local norm = M.normPath(path:gsub("/$", ""))

    local home = M.getHomeDir()
    if home and norm == home then return true end

    local g = rawget(_G, "G_reader_settings")
    local neo_cfg = g and g:readSetting("neo_ui_config")
    local extra = type(neo_cfg) == "table" and neo_cfg.additional_home_dirs
    if type(extra) == "table" then
        for _, dir in ipairs(extra) do
            local d = M.normPath(dir:gsub("/*$", ""))
            if d ~= "" and norm == d then return true end
        end
    end
    return false
end

function M.isInHomeDir(path)
    if not path then return false end
    local norm = M.normPath(path:gsub("/$", ""))

    local home = M.getHomeDir()
    if home and (norm == home or norm:sub(1, #home + 1) == home .. "/") then
        return true
    end

    local g = rawget(_G, "G_reader_settings")
    local neo_cfg = g and g:readSetting("neo_ui_config")
    local extra = type(neo_cfg) == "table" and neo_cfg.additional_home_dirs
    if type(extra) == "table" then
        for _, dir in ipairs(extra) do
            local d = M.normPath(dir:gsub("/*$", ""))
            if d ~= "" and (norm == d or norm:sub(1, #d + 1) == d .. "/") then
                return true
            end
        end
    end

    return false
end

return M
