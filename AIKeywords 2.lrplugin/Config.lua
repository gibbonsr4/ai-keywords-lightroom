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
local Engine   = dofile(_PLUGIN.path .. '/AIEngine.lua')

-- Convenience aliases for Engine functions used throughout
local isOllamaInstalled = Engine.isOllamaInstalled
local getInstalledModels = Engine.getInstalledModels
local isModelInstalled  = Engine.isModelInstalled
local fetchRemoteModels = Engine.fetchRemoteModels
local VISION_MODELS     = Engine.VISION_MODELS

-- ── Query Ollama version ────────────────────────────────────────────────
local json = dofile(_PLUGIN.path .. '/dkjson.lua')

local function getOllamaVersion(ollamaUrl)
    local tmpCfg = "/tmp/ai_kw_ver_cfg.txt"
    local tmpOut = "/tmp/ai_kw_ver.json"

    local cfh = io.open(tmpCfg, "w")
    if not cfh then return nil end
    cfh:write("-s\n")
    cfh:write(string.format('url = "%s/api/version"\n', ollamaUrl))
    cfh:write("max-time = 3\n")
    cfh:close()

    local cmd = string.format("curl -K %s -o %s",
        Engine.shellEscape(tmpCfg), Engine.shellEscape(tmpOut))
    local exitCode = LrTasks.execute(cmd)

    if exitCode == 0 then
        local rf = io.open(tmpOut, "r")
        if rf then
            local raw = rf:read("*all")
            rf:close()
            pcall(function() LrFileUtils.delete(tmpCfg) end)
            pcall(function() LrFileUtils.delete(tmpOut) end)
            if raw and raw ~= "" then
                local ok, data = pcall(function() return json.decode(raw) end)
                if ok and type(data) == "table" and data.version then
                    return data.version
                end
            end
        end
    end

    pcall(function() LrFileUtils.delete(tmpCfg) end)
    pcall(function() LrFileUtils.delete(tmpOut) end)
    return nil
end

-- ── Build model dropdown items ────────────────────────────────────────────
local function buildModelItems(models, installed, isRunning)
    local items = {}
    -- Track which installed models are covered by the suggested list
    local covered = {}
    for _, m in ipairs(models) do
        local status
        if not isRunning then
            status = "  —  Ollama offline"
        elseif isModelInstalled(installed, m.value) then
            status = "  ✓"
            covered[m.value] = true
        else
            status = "  —  not installed"
        end
        table.insert(items, {
            title = m.label .. status,
            value = m.value,
        })
    end
    -- Append installed models not in the suggested list (e.g. removed models)
    if isRunning then
        for tag, _ in pairs(installed) do
            -- Only use fully-qualified tags (contain ":"), skip bare base names
            if tag:find(":") and not covered[tag] then
                table.insert(items, {
                    title = tag .. "  ✓",
                    value = tag,
                })
            end
        end
    end
    return items
end

-- ── Build Ollama status text ──────────────────────────────────────────────
local function ollamaStatusText(isInstalled, isRunning, version)
    if not isInstalled then
        return "Ollama is not installed"
    elseif isRunning then
        local ver = version and (" v" .. version) or ""
        return "Ollama" .. ver .. " is running  ✓"
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
        local ollamaVersion = ollamaRunning and getOllamaVersion(current.ollamaUrl) or nil

        -- Fetch up-to-date model list (falls back to hardcoded)
        local remoteModels = fetchRemoteModels()
        local activeModels = remoteModels or VISION_MODELS

        -- If the user's current model isn't in the active list, keep it
        local found = false
        for _, m in ipairs(activeModels) do
            if m.value == current.model then found = true; break end
        end
        if not found then
            table.insert(activeModels, {
                value = current.model,
                label = current.model,
                info  = "Custom / unlisted model",
            })
        end

        -- Lookup model info by value
        local modelInfoMap = {}
        for _, m in ipairs(activeModels) do
            modelInfoMap[m.value] = m.info
        end
        -- Add info for installed models not in the suggested list
        for tag, _ in pairs(installed) do
            if tag:find(":") and not modelInfoMap[tag] then
                modelInfoMap[tag] = "Installed but not in suggested model list — consider upgrading"
            end
        end

        local props = LrBinding.makePropertyTable(context)
        props.provider         = current.provider
        props.ollamaUrl        = current.ollamaUrl
        props.model            = current.model
        props.modelItems       = buildModelItems(activeModels, installed, ollamaRunning)
        props.modelInfo        = modelInfoMap[current.model] or ""
        props.ollamaStatus     = ollamaStatusText(ollamaInstalled, ollamaRunning, ollamaVersion)
        props.claudeApiKey     = current.claudeApiKey
        props.claudeModel      = current.claudeModel
        props.maxKeywords      = tostring(current.maxKeywords)
        props.timeoutSecs      = tostring(current.timeoutSecs)
        props.useFolderContext = current.useFolderContext
        props.skipKeyworded    = current.skipKeyworded
        props.parentKeyword    = current.parentKeyword
        props.keywordCase      = current.keywordCase
        props.prompt           = current.prompt
        props.enableLogging    = current.enableLogging
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
                return "Uninstall Model"
            else
                return "Install in Terminal"
            end
        end

        props.ollamaActionTitle = getOllamaActionTitle(ollamaInstalled, ollamaRunning)
        props.installBtnTitle   = getInstallBtnTitle(installed, current.model)

        -- Update model info + install button when selection changes
        props:addObserver("model", function(_, _, newValue)
            props.modelInfo = modelInfoMap[newValue] or ""
            props.installBtnTitle = getInstallBtnTitle(props._installed, newValue)
        end)

        -- Helper to refresh Ollama state
        local function refreshOllamaState()
            local inst, running = getInstalledModels(props.ollamaUrl)
            local instld = isOllamaInstalled()
            local ver = running and getOllamaVersion(props.ollamaUrl) or nil
            props.modelItems          = buildModelItems(activeModels, inst, running)
            props.ollamaStatus        = ollamaStatusText(instld, running, ver)
            props.ollamaActionTitle   = getOllamaActionTitle(instld, running)
            props.installBtnTitle     = getInstallBtnTitle(inst, props.model)
            props._installed          = inst
            props._ollamaRunning      = running
            -- Rebuild info map so newly-installed or unlisted models get entries
            for tag, _ in pairs(inst) do
                if tag:find(":") and not modelInfoMap[tag] then
                    modelInfoMap[tag] = "Installed but not in suggested model list — consider upgrading"
                end
            end
            props.modelInfo = modelInfoMap[props.model] or ""
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
                        action  = function()
                            LrTasks.startAsyncTask(function()
                                local safeModel = props.model:gsub("[^%w%.%-%:_]", "")
                                if isModelInstalled(props._installed, props.model) then
                                    -- Uninstall: use login shell so PATH includes /usr/local/bin
                                    local cmd = string.format(
                                        "/bin/zsh -lc 'ollama rm %s' >/dev/null 2>&1", safeModel
                                    )
                                    LrTasks.execute(cmd)
                                else
                                    -- Install: open Terminal so user can watch progress
                                    local cmd = string.format(
                                        "osascript"
                                        .. " -e 'tell application \"Terminal\"'"
                                        .. " -e 'activate'"
                                        .. " -e 'do script \"ollama pull %s\"'"
                                        .. " -e 'end tell'",
                                        safeModel
                                    )
                                    LrTasks.execute(cmd)
                                end
                                refreshOllamaState()
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
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:push_button {
                        title  = "Compare models on GitHub →",
                        action = function()
                            LrTasks.execute('open "https://github.com/gibbonsr4/ai-keywords-lightroom#ollama-models"')
                        end,
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

            -- ═══════════════════════════════════════════════════════════
            -- VALIDATION MESSAGE (shown when Save is disabled)
            -- ═══════════════════════════════════════════════════════════
            f:row {
                f:static_text {
                    title = "",
                    width = LrView.share("label_width"),
                },
                f:static_text {
                    title           = LrView.bind("validationMessage"),
                    text_color      = LrView.kWarningColor,
                    fill_horizontal = 1,
                },
            },
        }

        -- Validation function — returns (isValid, message)
        local function validateSettings(values)
            local maxKw = tonumber(values.maxKeywords)
            if not maxKw or maxKw < 1 or maxKw > 50 then
                return false, "Max keywords must be a number between 1 and 50."
            end
            local timeout = tonumber(values.timeoutSecs)
            if not timeout or timeout < 5 then
                return false, "Timeout must be at least 5 seconds."
            end
            if values.provider == "claude" and (values.claudeApiKey == nil or values.claudeApiKey == "") then
                return false, "Claude API selected — enter your Anthropic API key."
            end
            local url = values.ollamaUrl or ""
            if values.provider == "ollama" and not url:match("^https?://") then
                return false, "Ollama URL must start with http:// or https://"
            end
            return true, ""
        end

        -- Initialize validation state
        props.validationMessage = ""
        local valid, msg = validateSettings(props)
        props.validationMessage = msg

        local result = LrDialogs.presentModalDialog {
            title      = "AI Keywords - Settings",
            contents   = contents,
            actionVerb = "Save",
            actionBinding = {
                enabled = {
                    bind_to_object = props,
                    keys = { "maxKeywords", "timeoutSecs", "claudeApiKey", "provider", "ollamaUrl" },
                    operation = function(_, values)
                        local isValid, validMsg = validateSettings(values)
                        props.validationMessage = validMsg
                        return isValid
                    end,
                },
            },
        }

        if result == "ok" then
            local maxKw   = tonumber(props.maxKeywords)
            local timeout = tonumber(props.timeoutSecs)

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
        end

    end)
end)
