--[[
  Prefs.lua
  ─────────────────────────────────────────────────────────────────────────────
  Pure preferences module — no UI, no side effects.
  Safe to dofile() from GenerateKeywords.lua.

  The Settings dialog lives in Config.lua and is invoked via the LR menu.
--]]

local LrPrefs = import 'LrPrefs'

local DEFAULTS = {
    provider         = "ollama",
    ollamaUrl        = "http://localhost:11434",
    model            = "llama3.2-vision:11b",
    claudeApiKey     = "",
    claudeModel      = "claude-haiku-4-5-20251001",
    maxKeywords      = 20,
    timeoutSecs      = 90,
    useFolderContext = true,
    skipKeyworded    = false,
    parentKeyword    = "",
    keywordCase      = "as_returned",
    enableLogging    = false,
    logFolder        = "",
    folderAliases    = "",
    prompt           = (
        "Analyze this photo and return keywords ordered by prominence. " ..
        "Only name specific landmarks, species, or crop varieties if you are highly confident. " ..
        "If unsure, use a broader category instead (e.g. 'fortress' not a specific fort name, " ..
        "'crop field' not a specific crop, 'songbird' not a specific species). " ..
        "Wrong specifics are worse than correct generics. " ..
        "For animals and plants you can confidently identify, use the most specific common name — " ..
        "no scientific/Latin names, no taxonomic categories (mammal, primate, reptile, amphibian). " ..
        "Include useful search synonyms where they differ meaningfully " ..
        "(e.g. both 'jungle' and 'rainforest', both 'ocean' and 'sea') " ..
        "but not near-duplicate descriptors (e.g. not both 'black fur' and 'dark fur'). " ..
        "Avoid generic filler: nature, outdoor, natural, beautiful, environment, scenic, wildlife, " ..
        "colorful, vibrant, small, large, tiny."
    ),
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
        maxKeywords      = (prefs.maxKeywords  ~= nil) and prefs.maxKeywords  or DEFAULTS.maxKeywords,
        timeoutSecs      = (prefs.timeoutSecs  ~= nil) and prefs.timeoutSecs  or DEFAULTS.timeoutSecs,
        useFolderContext = boolPref(prefs, "useFolderContext"),
        skipKeyworded    = boolPref(prefs, "skipKeyworded"),
        parentKeyword    = stringPref(prefs, "parentKeyword", true),
        keywordCase      = stringPref(prefs, "keywordCase"),
        enableLogging    = boolPref(prefs, "enableLogging"),
        logFolder        = stringPref(prefs, "logFolder", true),
        folderAliases    = stringPref(prefs, "folderAliases", true),
        prompt           = stringPref(prefs, "prompt"),
    }
end

return {
    getPrefs = getPrefs,
    DEFAULTS = DEFAULTS,
}
