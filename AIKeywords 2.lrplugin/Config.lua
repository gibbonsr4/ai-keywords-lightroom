--[[
  Config.lua
  ─────────────────────────────────────────────────────────────────────────────
  Settings dialog — invoked via Library > Plugin Extras > Settings...
  Preferences (defaults + getPrefs) live in Prefs.lua.
--]]

local LrBinding         = import 'LrBinding'
local LrDialogs         = import 'LrDialogs'
local LrFileUtils       = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs           = import 'LrPrefs'
local LrTasks           = import 'LrTasks'
local LrView            = import 'LrView'

local Prefs    = dofile(_PLUGIN.path .. '/Prefs.lua')
local DEFAULTS = Prefs.DEFAULTS
local json     = dofile(_PLUGIN.path .. '/dkjson.lua')

-- ── Recommended vision models for Ollama ──────────────────────────────────
local VISION_MODELS = {
    { value = "qwen2.5vl:3b",        label = "Qwen2.5-VL 3B",          info = "~2GB RAM  |  Fastest, good quality  |  Requires Ollama 0.7+" },
    { value = "minicpm-v",            label = "MiniCPM-V 8B",           info = "~5GB RAM  |  Fast, strong detail recognition" },
    { value = "qwen2.5vl:7b",        label = "Qwen2.5-VL 7B",          info = "~5GB RAM  |  Best local quality, accurate IDs  |  Requires Ollama 0.7+" },
    { value = "llama3.2-vision:11b",  label = "Llama 3.2 Vision 11B",   info = "~8GB RAM  |  Solid all-rounder" },
    { value = "llava:13b",            label = "LLaVA 13B",              info = "~10GB RAM  |  High quality, slow" },
    { value = "moondream",            label = "Moondream 2",            info = "~1GB RAM  |  Tiny, fast, basic keywords only" },
}

-- ── Check if Ollama is installed on this Mac ─────────────────────────────
local function isOllamaInstalled()
    local appExists = LrFileUtils.exists("/Applications/Ollama.app")
    if appExists then return true end
    local exitCode = LrTasks.execute("which ollama >/dev/null 2>&1")
    return exitCode == 0
end

-- ── Query Ollama for installed models ─────────────────────────────────────
local function getInstalledModels(ollamaUrl)
    local installed = {}
    local tmpOut = "/tmp/ai_kw_tags.json"
    local cmd = string.format(
        'curl -s "%s/api/tags" -o "%s" --max-time 5',
        ollamaUrl, tmpOut
    )
    local exitCode = LrTasks.execute(cmd)

    if exitCode == 0 then
        local rf = io.open(tmpOut, "r")
        if rf then
            local response = rf:read("*all")
            rf:close()
            pcall(function() LrFileUtils.delete(tmpOut) end)
            if response and response ~= "" then
                local success, data = pcall(function() return json.decode(response) end)
                if success and data and data.models then
                    for _, m in ipairs(data.models) do
                        installed[m.name] = true
                        local base = m.name:match("^([^:]+)")
                        if base then installed[base] = true end
                        local withoutLatest = m.name:gsub(":latest$", "")
                        installed[withoutLatest] = true
                    end
                end
                return installed, true
            end
        end
    end

    pcall(function() LrFileUtils.delete(tmpOut) end)
    return installed, false
end

-- ── Check if a specific model is installed ────────────────────────────────
local function isModelInstalled(installed, modelValue)
    if installed[modelValue] then return true end
    local base = modelValue:match("^([^:]+)")
    if base and installed[base] then return true end
    return false
end

-- ── Build model dropdown items ────────────────────────────────────────────
local function buildModelItems(installed, isRunning)
    local items = {}
    for _, m in ipairs(VISION_MODELS) do
        local status
        if not isRunning then
            status = "  —  Ollama offline"
        elseif isModelInstalled(installed, m.value) then
            status = "  ✓"
        else
            status = "  —  not installed"
        end
        table.insert(items, {
            title = m.label .. status,
            value = m.value,
        })
    end
    return items
end

-- ── Build Ollama status text ──────────────────────────────────────────────
local function ollamaStatusText(isInstalled, isRunning)
    if not isInstalled then
        return "Ollama is not installed"
    elseif isRunning then
        return "Ollama is running  ✓"
    else
        return "Ollama is not running"
    end
end

-- ── Main dialog ──────────────────────────────────────────────────────────
LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("AIKeywordsSettings", function(context)

        local prefs   = LrPrefs.prefsForPlugin()
        local current = Prefs.getPrefs()
        local f       = LrView.osFactory()

        -- Check Ollama status
        local ollamaInstalled = isOllamaInstalled()
        local installed, ollamaRunning = getInstalledModels(current.ollamaUrl)

        -- Lookup model info by value
        local modelInfoMap = {}
        for _, m in ipairs(VISION_MODELS) do
            modelInfoMap[m.value] = m.info
        end

        local props = LrBinding.makePropertyTable(context)
        props.provider         = current.provider
        props.ollamaUrl        = current.ollamaUrl
        props.model            = current.model
        props.modelItems       = buildModelItems(installed, ollamaRunning)
        props.modelInfo        = modelInfoMap[current.model] or ""
        props.ollamaStatus     = ollamaStatusText(ollamaInstalled, ollamaRunning)
        props.claudeApiKey     = current.claudeApiKey
        props.claudeModel      = current.claudeModel
        props.maxKeywords      = tostring(current.maxKeywords)
        props.timeoutSecs      = tostring(current.timeoutSecs)
        props.useFolderContext = (current.useFolderContext == true)
        props.skipKeyworded    = (current.skipKeyworded == true)
        props.parentKeyword    = current.parentKeyword
        props.keywordCase      = current.keywordCase
        props.prompt           = current.prompt
        props.enableLogging    = (current.enableLogging == true)
        props.logFolder        = current.logFolder
        props.folderAliases    = current.folderAliases

        -- Internal state
        props._installed       = installed
        props._ollamaRunning   = ollamaRunning

        -- Dynamic button titles
        local function getOllamaActionTitle(instld, running)
            if not instld then return "Download Ollama"
            elseif not running then return "Start Ollama"
            else return "Refresh" end
        end

        local function getInstallBtnTitle(inst, modelValue)
            if isModelInstalled(inst, modelValue) then
                return "Model Installed  ✓"
            else
                return "Install in Terminal"
            end
        end

        props.ollamaActionTitle = getOllamaActionTitle(ollamaInstalled, ollamaRunning)
        props.installBtnTitle   = getInstallBtnTitle(installed, current.model)
        props.installBtnEnabled = not isModelInstalled(installed, current.model)

        -- Update model info + install button when selection changes
        props:addObserver("model", function(_, _, newValue)
            props.modelInfo = modelInfoMap[newValue] or ""
            props.installBtnTitle = getInstallBtnTitle(props._installed, newValue)
            props.installBtnEnabled = not isModelInstalled(props._installed, newValue)
        end)

        -- Helper to refresh Ollama state
        local function refreshOllamaState()
            local inst, running = getInstalledModels(props.ollamaUrl)
            local instld = isOllamaInstalled()
            props.modelItems          = buildModelItems(inst, running)
            props.ollamaStatus        = ollamaStatusText(instld, running)
            props.ollamaActionTitle   = getOllamaActionTitle(instld, running)
            props.installBtnTitle     = getInstallBtnTitle(inst, props.model)
            props.installBtnEnabled   = not isModelInstalled(inst, props.model)
            props._installed          = inst
            props._ollamaRunning      = running
        end

        local contents = f:column {
            spacing         = f:dialog_spacing(),
            fill_horizontal = 1,
            bind_to_object  = props,

            -- ═══════════════════════════════════════════════════════════
            -- PROVIDER SELECTOR
            -- ═══════════════════════════════════════════════════════════
            f:row {
                f:static_text {
                    title     = "AI Provider:",
                    width     = LrView.share("label_width"),
                    alignment = "right",
                },
                f:radio_button {
                    title         = "Ollama (local)",
                    value         = LrView.bind("provider"),
                    checked_value = "ollama",
                },
                f:radio_button {
                    title         = "Claude API (cloud)",
                    value         = LrView.bind("provider"),
                    checked_value = "claude",
                },
            },

            f:separator { fill_horizontal = 1 },

            -- ═══════════════════════════════════════════════════════════
            -- OLLAMA
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Ollama (local)",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title     = "Status:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:static_text {
                        title           = LrView.bind("ollamaStatus"),
                        fill_horizontal = 1,
                    },
                    f:push_button {
                        title   = LrView.bind("ollamaActionTitle"),
                        action  = function()
                            LrTasks.startAsyncTask(function()
                                if not isOllamaInstalled() then
                                    LrTasks.execute('open "https://ollama.com/download"')
                                elseif not props._ollamaRunning then
                                    LrTasks.execute('open -a Ollama')
                                    LrTasks.sleep(3.0)
                                end
                                refreshOllamaState()
                            end)
                        end,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "URL:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("ollamaUrl"),
                        width_in_chars = 30,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Model:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = LrView.bind("model"),
                        items = LrView.bind("modelItems"),
                    },
                    f:push_button {
                        title   = LrView.bind("installBtnTitle"),
                        enabled = LrView.bind("installBtnEnabled"),
                        action  = function()
                            LrTasks.startAsyncTask(function()
                                local cmd = string.format(
                                    'osascript -e \'tell application "Terminal" to do script "ollama pull %s"\'',
                                    props.model
                                )
                                LrTasks.execute(cmd)
                            end)
                        end,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title           = LrView.bind("modelInfo"),
                        text_color      = LrView.kDisabledColor,
                        fill_horizontal = 1,
                    },
                },
            },

            -- ═══════════════════════════════════════════════════════════
            -- CLAUDE API
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Claude API",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title     = "API Key:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("claudeApiKey"),
                        width_in_chars = 55,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Model:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = LrView.bind("claudeModel"),
                        items = {
                            { title = "Haiku 4.5 (~$0.002/image)",   value = "claude-haiku-4-5-20251001" },
                            { title = "Sonnet 4.6 (~$0.007/image)",  value = "claude-sonnet-4-6" },
                        },
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Get your API key at console.anthropic.com",
                        text_color = LrView.kDisabledColor,
                    },
                },
            },

            -- ═══════════════════════════════════════════════════════════
            -- KEYWORDS
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Keywords",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title     = "Max keywords:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("maxKeywords"),
                        width_in_chars = 5,
                    },
                    f:static_text { title = "per photo (1-50)" },
                },
                f:row {
                    f:static_text {
                        title     = "Keyword case:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:popup_menu {
                        value   = LrView.bind("keywordCase"),
                        items   = {
                            { title = "As returned by model",  value = "as_returned" },
                            { title = "lowercase",             value = "lowercase"   },
                            { title = "Title Case",            value = "title_case"  },
                        },
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Timeout:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("timeoutSecs"),
                        width_in_chars = 5,
                    },
                    f:static_text { title = "seconds per image" },
                },
                f:row {
                    f:static_text {
                        title     = "Parent keyword:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("parentKeyword"),
                        width_in_chars = 25,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Nests all AI keywords under this parent in the Keyword List.\n" ..
                                     "Leave blank for flat keywords. Example: \"AI Generated\"\n" ..
                                     "Useful for organizing, bulk-deleting, or distinguishing AI tags.",
                        text_color = LrView.kDisabledColor,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:checkbox {
                        title = "Skip photos that already have keywords",
                        value = LrView.bind("skipKeyworded"),
                    },
                },
            },

            -- ═══════════════════════════════════════════════════════════
            -- AI PROMPT
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "AI Prompt",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:checkbox {
                        title = "Use catalog folder names as location hints",
                        value = LrView.bind("useFolderContext"),
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "When enabled, folder names (e.g. Costa Rica > Monteverde)\n" ..
                                     "are prepended to the prompt as location/subject context.",
                        text_color = LrView.kDisabledColor,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Folder aliases:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("folderAliases"),
                        width_in_chars = 45,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Expand short folder names. Semicolon-separated:\n" ..
                                     "DR=Dominican Republic; CR=Costa Rica; PR=Puerto Rico",
                        text_color = LrView.kDisabledColor,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Prompt:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value           = LrView.bind("prompt"),
                        width_in_chars  = 55,
                        height_in_lines = 8,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:push_button {
                        title  = "Reset to default prompt",
                        action = function() props.prompt = DEFAULTS.prompt end,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Focus on what to identify — output format instruction is added automatically.",
                        text_color = LrView.kDisabledColor,
                    },
                },
            },

            -- ═══════════════════════════════════════════════════════════
            -- LOGGING
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Logging",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:checkbox {
                        title = "Enable logging",
                        value = LrView.bind("enableLogging"),
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Log folder:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("logFolder"),
                        width_in_chars = 35,
                    },
                    f:push_button {
                        title  = "Browse",
                        action = function()
                            LrTasks.startAsyncTask(function()
                                -- Use native macOS folder picker — LR's runOpenPanel
                                -- has issues with folder selection in some versions.
                                local tmpFile = "/tmp/ai_kw_folder_pick.txt"
                                local cmd = 'osascript -e \'POSIX path of (choose folder with prompt "Select Log Folder")\' > "' .. tmpFile .. '" 2>/dev/null'
                                local exitCode = LrTasks.execute(cmd)
                                if exitCode == 0 then
                                    local fh = io.open(tmpFile, "r")
                                    if fh then
                                        local path = fh:read("*line")
                                        fh:close()
                                        if path and path ~= "" then
                                            -- Remove trailing slash
                                            path = path:gsub("/$", "")
                                            props.logFolder = path
                                        end
                                    end
                                end
                                pcall(function() LrFileUtils.delete(tmpFile) end)
                            end)
                        end,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Leave blank for ~/Documents. One timestamped log file per run.",
                        text_color = LrView.kDisabledColor,
                    },
                },
            },
        }

        local result = LrDialogs.presentModalDialog {
            title      = "AI Keywords - Settings",
            contents   = contents,
            actionVerb = "Save",
        }

        if result == "ok" then
            local maxKw   = tonumber(props.maxKeywords)
            local timeout = tonumber(props.timeoutSecs)

            if not maxKw or maxKw < 1 or maxKw > 50 then
                LrDialogs.message("Invalid Value", "Max keywords must be a number between 1 and 50.", "warning")
                return
            end
            if not timeout or timeout < 5 then
                LrDialogs.message("Invalid Value", "Timeout must be at least 5 seconds.", "warning")
                return
            end
            if props.provider == "claude" and (props.claudeApiKey == nil or props.claudeApiKey == "") then
                LrDialogs.message("Missing API Key", "Please enter your Anthropic API key to use Claude.", "warning")
                return
            end

            prefs.provider         = props.provider
            prefs.ollamaUrl        = props.ollamaUrl
            prefs.model            = props.model
            prefs.claudeApiKey     = props.claudeApiKey
            prefs.claudeModel      = props.claudeModel
            prefs.maxKeywords      = math.floor(maxKw)
            prefs.timeoutSecs      = math.floor(timeout)
            prefs.useFolderContext = props.useFolderContext
            prefs.skipKeyworded    = props.skipKeyworded
            prefs.parentKeyword    = props.parentKeyword
            prefs.keywordCase      = props.keywordCase
            prefs.prompt           = props.prompt
            prefs.enableLogging    = props.enableLogging
            prefs.logFolder        = props.logFolder
            prefs.folderAliases    = props.folderAliases

            LrDialogs.message(
                "Settings Saved",
                "Settings saved. They will apply on the next keyword generation run.",
                "info"
            )
        end

    end)
end)
