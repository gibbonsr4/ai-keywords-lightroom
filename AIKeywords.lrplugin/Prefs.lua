--[[
  Prefs.lua
  ─────────────────────────────────────────────────────────────────────────────
  Pure preferences module — no UI, no side effects.
  Safe to dofile() from any module.

  API keys are stored in the macOS Keychain via LrPasswords,
  with a fallback to LrPrefs for migration from older versions.

  The Settings dialog lives in Config.lua and is invoked via the LR menu.
--]]

local LrPrefs     = import 'LrPrefs'
local LrPasswords = import 'LrPasswords'

local DEFAULTS = {
    provider         = "ollama",
    ollamaUrl        = "http://localhost:11434",
    model            = "qwen2.5vl:7b",
    claudeApiKey     = "",
    claudeModel      = "claude-haiku-4-5-20251001",
    openaiApiKey     = "",
    openaiModel      = "gpt-5-mini-2025-08-07",
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
    basePrompt       = "",
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

-- Retrieve an API key: try Keychain first, fall back to prefs (migration).
-- If the keychain is empty but a plaintext pref exists from a pre-1.1 install,
-- auto-migrate it into the keychain on first read so legacy users don't need
-- to open Settings + click Save to upgrade. Plaintext is only cleared when
-- the keychain store actually succeeds.
local function apiKeyPref(prefs, keychainKey, prefsKey)
    local ok, key = pcall(LrPasswords.retrieve, keychainKey)
    if ok and key and key ~= "" then return key end

    local plaintext = stringPref(prefs, prefsKey, true)
    if plaintext and plaintext ~= "" then
        local stored = pcall(LrPasswords.store, keychainKey, plaintext)
        if stored then prefs[prefsKey] = nil end
    end
    return plaintext
end

-- Store an API key in the Keychain.
local function storeApiKey(keychainKey, value)
    pcall(LrPasswords.store, keychainKey, value or "")
end

local function getPrefs()
    local prefs = LrPrefs.prefsForPlugin()
    return {
        provider         = stringPref(prefs, "provider"),
        ollamaUrl        = stringPref(prefs, "ollamaUrl"),
        model            = stringPref(prefs, "model"),
        claudeApiKey     = apiKeyPref(prefs, "claude_api_key", "claudeApiKey"),
        claudeModel      = stringPref(prefs, "claudeModel"),
        openaiApiKey     = apiKeyPref(prefs, "openai_api_key", "openaiApiKey"),
        openaiModel      = stringPref(prefs, "openaiModel"),
        geminiApiKey     = apiKeyPref(prefs, "gemini_api_key", "geminiApiKey"),
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
        basePrompt       = stringPref(prefs, "basePrompt", true),
    }
end

return {
    getPrefs     = getPrefs,
    storeApiKey  = storeApiKey,
    DEFAULTS     = DEFAULTS,
}
