--[[
  Info.lua — Plugin manifest for AI Keywords
  Registers the plugin with Lightroom Classic and declares menu items.
--]]

return {
    LrSdkVersion        = 6.0,
    LrSdkMinimumVersion = 6.0,

    LrToolkitIdentifier = 'com.sonoranstrategy.ai-keywords',
    LrPluginName        = 'AI Keywords',
    LrPluginInfoUrl     = 'https://github.com/gibbonsr4/ai-keywords-lightroom',

    -- Adds two items under Library > Plugin Extras
    LrLibraryMenuItems = {
        {
            title = 'Generate AI Keywords — Selected Photos',
            file  = 'GenerateKeywords.lua',
        },
        {
            title = 'Compare Models — Selected Photo',
            file  = 'CompareModels.lua',
        },
        {
            title = 'Settings\226\128\166',   -- "Settings…" with ellipsis
            file  = 'Config.lua',
        },
    },

    VERSION = { major = 3, minor = 0, revision = 0, build = 1 },
}
