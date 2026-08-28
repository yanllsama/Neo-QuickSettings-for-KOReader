local gettext = require("gettext")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local I18N = {}

-- Determine the selected language
local plugin_lang = "system"
local settings_path = DataStorage:getSettingsDir() .. "/neo_quicksettings.lua"
local ok, settings = pcall(LuaSettings.open, LuaSettings, settings_path)
if ok and settings and settings.data and settings.data.config and settings.data.config.plugin_language then
    plugin_lang = settings.data.config.plugin_language
end

local lang = ""
if plugin_lang == "system" then
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or ""
    end
    if lang == "" then
        lang = os.getenv("LANG") or ""
    end
    -- Normalize system lang
    if string.find(lang, "tr") then lang = "tr"
    elseif string.find(lang, "es") then lang = "es"
    elseif string.find(lang, "fr") then lang = "fr"
    elseif string.find(lang, "de") then lang = "de"
    elseif string.find(lang, "zh") then lang = "zh_CN"
    elseif string.find(lang, "ja") then lang = "ja"
    elseif string.find(lang, "ru") then lang = "ru"
    elseif string.find(lang, "it") then lang = "it"
    elseif string.find(lang, "pt") then lang = "pt_BR"
    elseif string.find(lang, "ko") then lang = "ko"
    elseif string.find(lang, "ar") then lang = "ar"
    elseif string.find(lang, "hi") then lang = "hi"
    else lang = "en" end
else
    lang = plugin_lang
end

local dict = {}
if lang ~= "en" then
    local loaded, data = pcall(require, "l10n/" .. lang)
    if loaded and type(data) == "table" then
        dict = data
    end
end

function I18N.gettext(text)
    if type(text) ~= "string" then return text end
    if dict[text] then
        return dict[text]
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
    if dict[text] then
        return dict[text]
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
