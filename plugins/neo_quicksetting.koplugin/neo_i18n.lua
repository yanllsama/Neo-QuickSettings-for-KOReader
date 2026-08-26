local gettext = require("gettext")

local I18N = {}

-- Load Turkish translations if they exist
local tr_dict = {}
local tr_loaded, tr_data = pcall(require, "l10n/tr")
if tr_loaded and type(tr_data) == "table" then
    tr_dict = tr_data
end

-- Determine if the system is running in Turkish
local function isTurkish()
    local lang = ""
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or ""
    end
    if lang == "" then
        lang = os.getenv("LANG") or ""
    end
    return string.find(lang, "tr") ~= nil
end

function I18N.gettext(text)
    if type(text) ~= "string" then return text end
    if isTurkish() and tr_dict[text] then
        return tr_dict[text]
    end
    -- gettext itself is callable
    if type(gettext) == "table" or type(gettext) == "function" then
        local ok, res = pcall(gettext, text)
        if ok and res then return res end
    end
    return text
end

function I18N.pgettext(ctx, text)
    -- In main.lua, C_ was just an alias for _, so it might be called with 1 argument!
    if text == nil then
        text = ctx
    end
    if type(text) ~= "string" then return text end

    if isTurkish() and tr_dict[text] then
        return tr_dict[text]
    end

    -- Fallback to standard gettext
    if type(gettext) == "table" or type(gettext) == "function" then
        local ok, res = pcall(gettext, text)
        if ok and res then return res end
    end
    return text
end

function I18N.ngettext(msgid, msgid_plural, n)
    if gettext.ngettext then
        return gettext.ngettext(msgid, msgid_plural, n)
    end
    return n == 1 and msgid or msgid_plural
end

return I18N
