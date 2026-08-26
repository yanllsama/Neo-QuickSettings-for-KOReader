
local logger = require("logger")
local paths = require("common/paths")

local LibraryDB = {}

local _cache = { book_counts = nil, cache_time = 0 }
local CACHE_TTL = 300  -- seconds

function LibraryDB.invalidateCache()
    _cache.book_counts = nil
    _cache.cache_time  = 0
end

function LibraryDB.getBookCounts()
    local now = os.time()
    if _cache.book_counts and (now - _cache.cache_time) < CACHE_TTL then
        logger.info("neo-ui db_library: returning cached book counts")
        return _cache.book_counts
    end

    local counts = { finished = 0, reading = 0, total = 0 }

    local ok, err = pcall(function()
        local ReadHistory = require("readhistory")
        local DocSettings = require("docsettings")

        if ReadHistory.reload then
            ReadHistory:reload(false)
        end

        local home_dir = paths.getHomeDir()

        local hist = ReadHistory.hist or {}
        for _, entry in ipairs(hist) do
            local file = entry.file
            if file and home_dir and not paths.isInHomeDir(file) then
                file = nil
            end
            if file and DocSettings:hasSidecarFile(file) then
                counts.total = counts.total + 1
                local doc_settings = DocSettings:open(file)
                local summary = doc_settings:readSetting("summary") or {}
                local status  = summary.status
                if status == "complete" then
                    counts.finished = counts.finished + 1
                elseif status == "reading" then
                    counts.reading = counts.reading + 1
                end
            end
        end
    end)

    if not ok then
        logger.warn("neo-ui db_library: finished count failed:", err)
    end

    logger.info("neo-ui db_library: finished=", counts.finished,
                "reading=", counts.reading,
                "total=", counts.total)
    _cache.book_counts = counts
    _cache.cache_time  = now
    return counts
end

return LibraryDB
