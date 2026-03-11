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

local function getPrefs()
    local prefs = LrPrefs.prefsForPlugin()
    return {
        provider         = (prefs.provider    ~= nil and prefs.provider    ~= "") and prefs.provider    or DEFAULTS.provider,
        ollamaUrl        = (prefs.ollamaUrl   ~= nil and prefs.ollamaUrl   ~= "") and prefs.ollamaUrl   or DEFAULTS.ollamaUrl,
        model            = (prefs.model        ~= nil and prefs.model        ~= "") and prefs.model       or DEFAULTS.model,
        claudeApiKey     = (prefs.claudeApiKey ~= nil)                              and prefs.claudeApiKey or DEFAULTS.claudeApiKey,
        claudeModel      = (prefs.claudeModel  ~= nil and prefs.claudeModel  ~= "") and prefs.claudeModel or DEFAULTS.claudeModel,
        maxKeywords      = (prefs.maxKeywords  ~= nil) and prefs.maxKeywords  or DEFAULTS.maxKeywords,
        timeoutSecs      = (prefs.timeoutSecs  ~= nil) and prefs.timeoutSecs  or DEFAULTS.timeoutSecs,
        useFolderContext = (prefs.useFolderContext == nil) and DEFAULTS.useFolderContext or prefs.useFolderContext,
        skipKeyworded    = (prefs.skipKeyworded == nil) and DEFAULTS.skipKeyworded or prefs.skipKeyworded,
        parentKeyword    = (prefs.parentKeyword ~= nil) and prefs.parentKeyword or DEFAULTS.parentKeyword,
        keywordCase      = (prefs.keywordCase  ~= nil and prefs.keywordCase  ~= "") and prefs.keywordCase or DEFAULTS.keywordCase,
        enableLogging    = (prefs.enableLogging == nil) and DEFAULTS.enableLogging or prefs.enableLogging,
        logFolder        = (prefs.logFolder    ~= nil) and prefs.logFolder    or DEFAULTS.logFolder,
        folderAliases    = (prefs.folderAliases ~= nil) and prefs.folderAliases or DEFAULTS.folderAliases,
        prompt           = (prefs.prompt       ~= nil and prefs.prompt       ~= "") and prefs.prompt      or DEFAULTS.prompt,
    }
end

return {
    getPrefs = getPrefs,
    DEFAULTS = DEFAULTS,
}
