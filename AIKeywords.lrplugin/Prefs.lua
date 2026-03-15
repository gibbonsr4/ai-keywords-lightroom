--[[
  Prefs.lua
  ─────────────────────────────────────────────────────────────────────────────
  Pure preferences module — no UI, no side effects.
  Safe to dofile() from any module.

  The Settings dialog lives in Config.lua and is invoked via the LR menu.
--]]

local LrPrefs = import 'LrPrefs'

local DEFAULTS = {
    provider         = "ollama",
    ollamaUrl        = "http://localhost:11434",
    model            = "qwen2.5vl:7b",
    claudeApiKey     = "",
    claudeModel      = "claude-haiku-4-5-20251001",
    openaiApiKey     = "",
    openaiModel      = "gpt-4o-mini",
    geminiApiKey     = "",
    geminiModel      = "gemini-2.5-flash",
    maxKeywords      = 20,
    timeoutSecs      = 90,
    useGPS           = true,
    useFolderContext = true,
    skipKeyworded    = false,
    parentKeyword    = "",
    keywordCase      = "lowercase",
    enableLogging    = false,
    logFolder        = "",
    folderAliases    = "",
    prompt           = "",
}

-- Helper: Lua's `cond and valTrue or valFalse` breaks when valTrue is false.
-- Use explicit nil checks for booleans.
local function boolPref(prefs, key)
    if prefs[key] == nil then return DEFAULTS[key] end
    return prefs[key]
end

local function stringPref(prefs, key, allowEmpty)
    if allowEmpty then
        if prefs[key] == nil then return DEFAULTS[key] end
        return prefs[key]
    end
    if prefs[key] ~= nil and prefs[key] ~= "" then return prefs[key] end
    return DEFAULTS[key]
end

local function getPrefs()
    local prefs = LrPrefs.prefsForPlugin()
    return {
        provider         = stringPref(prefs, "provider"),
        ollamaUrl        = stringPref(prefs, "ollamaUrl"),
        model            = stringPref(prefs, "model"),
        claudeApiKey     = stringPref(prefs, "claudeApiKey", true),
        claudeModel      = stringPref(prefs, "claudeModel"),
        openaiApiKey     = stringPref(prefs, "openaiApiKey", true),
        openaiModel      = stringPref(prefs, "openaiModel"),
        geminiApiKey     = stringPref(prefs, "geminiApiKey", true),
        geminiModel      = stringPref(prefs, "geminiModel"),
        maxKeywords      = (prefs.maxKeywords  ~= nil) and prefs.maxKeywords  or DEFAULTS.maxKeywords,
        timeoutSecs      = (prefs.timeoutSecs  ~= nil) and prefs.timeoutSecs  or DEFAULTS.timeoutSecs,
        useGPS           = boolPref(prefs, "useGPS"),
        useFolderContext = boolPref(prefs, "useFolderContext"),
        skipKeyworded    = boolPref(prefs, "skipKeyworded"),
        parentKeyword    = stringPref(prefs, "parentKeyword", true),
        keywordCase      = stringPref(prefs, "keywordCase"),
        enableLogging    = boolPref(prefs, "enableLogging"),
        logFolder        = stringPref(prefs, "logFolder", true),
        folderAliases    = stringPref(prefs, "folderAliases", true),
        prompt           = stringPref(prefs, "prompt", true),
    }
end

return {
    getPrefs = getPrefs,
    DEFAULTS = DEFAULTS,
}
