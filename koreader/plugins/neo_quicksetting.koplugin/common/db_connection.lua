
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local M = {}


function M.getStatsDbPath()
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local primary = DataStorage:getDataDir() .. "/statistics.sqlite3"
    if lfs.attributes(primary, "mode") == "file" then return primary end
    local fallback = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(fallback, "mode") == "file" then return fallback end
    return primary
end


function M.isAvailable(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") == "file"
end

function M.open(path)
    if not M.isAvailable(path) then
        return nil, "file not found: " .. tostring(path)
    end
    local ok, conn = pcall(SQ3.open, path)
    if not ok then
        logger.warn("neo-ui db_connection: failed to open", path, ":", conn)
        return nil, tostring(conn)
    end
    return conn, nil
end

return M
