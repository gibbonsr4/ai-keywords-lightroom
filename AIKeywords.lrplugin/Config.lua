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
local CLAUDE_MODELS     = Engine.CLAUDE_MODELS
local OPENAI_MODELS     = Engine.OPENAI_MODELS
local GEMINI_MODELS     = Engine.GEMINI_MODELS

-- Build popup_menu items from a cloud model list: "Label (~$0.00X/image)"
local function cloudModelItems(models)
    local items = {}
    for _, m in ipairs(models) do
        table.insert(items, {
            title = string.format("%s (%s/image)", m.label, m.cost),
            value = m.value,
        })
    end
    return items
end

-- ── Query Ollama version ────────────────────────────────────────────────
local LrDate = import 'LrDate'
local json   = dofile(_PLUGIN.path .. '/dkjson.lua')

local function getOllamaVersion(ollamaUrl)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000))
    local tmpCfg = Engine.TEMP_DIR .. "/ai_kw_ver_cfg_" .. ts .. ".txt"
    local tmpOut = Engine.TEMP_DIR .. "/ai_kw_ver_" .. ts .. ".json"

    local cfh = io.open(tmpCfg, "w")
    if not cfh then return nil end
    cfh:write("-s\n")
    cfh:write(string.format('url = "%s/api/version"\n', Engine.escapeCurlConfigValue(ollamaUrl)))
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

        -- Use bundled model list (no network call on open)
        local activeModels = VISION_MODELS

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
        props.openaiApiKey     = current.openaiApiKey
        props.openaiModel      = current.openaiModel
        props.geminiApiKey     = current.geminiApiKey
        props.geminiModel      = current.geminiModel
        props.maxKeywords      = tostring(current.maxKeywords)
        props.timeoutSecs      = tostring(current.timeoutSecs)
        props.useGPS           = current.useGPS
        props.useFolderContext = current.useFolderContext
        props.skipKeyworded    = current.skipKeyworded
        props.parentKeyword    = current.parentKeyword
        props.keywordCase      = current.keywordCase
        props.prompt           = current.prompt
        props.enableLogging    = current.enableLogging
        props.logFolder        = current.logFolder
        props.folderAliases    = current.folderAliases
        props.basePrompt       = current.basePrompt
        props.basePromptDisplay = (current.basePrompt ~= "" and current.basePrompt) or Engine.BASE_PROMPT

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

        -- Helper to fetch remote model list and merge into activeModels
        local function refreshModelList()
            local remote = fetchRemoteModels()
            if remote and #remote > 0 then
                activeModels = remote
                -- Rebuild info map
                for _, m in ipairs(activeModels) do
                    modelInfoMap[m.value] = m.info or ""
                end
            end
        end

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
            -- PROVIDER (tabbed)
            -- ═══════════════════════════════════════════════════════════
            f:tab_view {
                value           = LrView.bind("provider"),
                fill_horizontal = 1,

                -- ── Ollama tab ────────────────────────────────────────
                f:tab_view_item {
                    identifier = "ollama",
                    title      = "Ollama",

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
                                        props.ollamaStatus = "Starting Ollama…"
                                        -- Poll until Ollama responds (up to 15s)
                                        for _ = 1, 30 do
                                            LrTasks.sleep(0.5)
                                            local ver = getOllamaVersion(props.ollamaUrl)
                                            if ver then break end
                                        end
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
                            title  = "Check for New Models",
                            action = function()
                                LrTasks.startAsyncTask(function()
                                    refreshModelList()
                                    refreshOllamaState()
                                end)
                            end,
                        },
                        f:push_button {
                            title  = "Compare models on GitHub →",
                            action = function()
                                LrTasks.execute('open "https://github.com/gibbonsr4/ai-keywords-lightroom#ollama-models"')
                            end,
                        },
                    },
                },

                -- ── Claude tab ────────────────────────────────────────
                f:tab_view_item {
                    identifier = "claude",
                    title      = "Claude",

                    f:row {
                        f:static_text {
                            title     = "API Key:",
                            width     = LrView.share("label_width"),
                            alignment = "right",
                        },
                        f:edit_field {
                            value           = LrView.bind("claudeApiKey"),
                            width_in_chars  = 55,
                            height_in_lines = 2,
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
                            items = cloudModelItems(CLAUDE_MODELS),
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

                -- ── OpenAI tab ────────────────────────────────────────
                f:tab_view_item {
                    identifier = "openai",
                    title      = "OpenAI",

                    f:row {
                        f:static_text {
                            title     = "API Key:",
                            width     = LrView.share("label_width"),
                            alignment = "right",
                        },
                        f:edit_field {
                            value           = LrView.bind("openaiApiKey"),
                            width_in_chars  = 55,
                            height_in_lines = 2,
                        },
                    },
                    f:row {
                        f:static_text {
                            title     = "Model:",
                            width     = LrView.share("label_width"),
                            alignment = "right",
                        },
                        f:popup_menu {
                            value = LrView.bind("openaiModel"),
                            items = cloudModelItems(OPENAI_MODELS),
                        },
                    },
                    f:row {
                        f:static_text {
                            title = "",
                            width = LrView.share("label_width"),
                        },
                        f:static_text {
                            title      = "Get your API key at platform.openai.com",
                            text_color = LrView.kDisabledColor,
                        },
                    },
                },

                -- ── Gemini tab ────────────────────────────────────────
                f:tab_view_item {
                    identifier = "gemini",
                    title      = "Gemini",

                    f:row {
                        f:static_text {
                            title     = "API Key:",
                            width     = LrView.share("label_width"),
                            alignment = "right",
                        },
                        f:edit_field {
                            value           = LrView.bind("geminiApiKey"),
                            width_in_chars  = 55,
                            height_in_lines = 2,
                        },
                    },
                    f:row {
                        f:static_text {
                            title     = "Model:",
                            width     = LrView.share("label_width"),
                            alignment = "right",
                        },
                        f:popup_menu {
                            value = LrView.bind("geminiModel"),
                            items = cloudModelItems(GEMINI_MODELS),
                        },
                    },
                    f:row {
                        f:static_text {
                            title = "",
                            width = LrView.share("label_width"),
                        },
                        f:static_text {
                            title      = "Get your API key at aistudio.google.com",
                            text_color = LrView.kDisabledColor,
                        },
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
                        title     = "Parent keyword:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value          = LrView.bind("parentKeyword"),
                        width_in_chars = 25,
                    },
                    f:static_text {
                        title      = "Nests AI keywords under this parent. Leave blank for flat.",
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
            -- CONTEXT & INSTRUCTIONS
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Context & Instructions",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:checkbox {
                        title = "Use GPS coordinates from photo metadata",
                        value = LrView.bind("useGPS"),
                    },
                },
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
                        title     = "Folder aliases:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value           = LrView.bind("folderAliases"),
                        width_in_chars  = 45,
                        height_in_lines = 3,
                    },
                    f:static_text {
                        title      = "One per line or comma-separated:\nDR=Dominican Republic\nCR=Costa Rica",
                        text_color = LrView.kDisabledColor,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Custom instructions:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value           = LrView.bind("prompt"),
                        width_in_chars  = 55,
                        height_in_lines = 4,
                        placeholder_string = "Optional — e.g. Focus on architecture and design elements",
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Optional domain-specific guidance. Base prompt handles keyword style automatically.",
                        text_color = LrView.kDisabledColor,
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
            -- ADVANCED (editable base prompt)
            -- ═══════════════════════════════════════════════════════════
            f:group_box {
                title           = "Advanced",
                fill_horizontal = 1,
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:static_text {
                        title      = "Editing the base prompt changes the core instructions sent to every AI model.\nChanges may affect keyword style, quality, and consistency.",
                        text_color = LrView.kWarningColor,
                    },
                },
                f:row {
                    f:static_text {
                        title     = "Base prompt:",
                        width     = LrView.share("label_width"),
                        alignment = "right",
                    },
                    f:edit_field {
                        value           = LrView.bind("basePromptDisplay"),
                        width_in_chars  = 55,
                        height_in_lines = 12,
                    },
                },
                f:row {
                    f:static_text {
                        title = "",
                        width = LrView.share("label_width"),
                    },
                    f:push_button {
                        title  = "Reset to Default",
                        action = function()
                            props.basePromptDisplay = Engine.BASE_PROMPT
                        end,
                    },
                    f:static_text {
                        title      = "Restores the built-in keywording prompt",
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
            if values.provider == "openai" and (values.openaiApiKey == nil or values.openaiApiKey == "") then
                return false, "OpenAI selected — enter your OpenAI API key."
            end
            if values.provider == "gemini" and (values.geminiApiKey == nil or values.geminiApiKey == "") then
                return false, "Gemini selected — enter your Google AI API key."
            end
            local url = values.ollamaUrl or ""
            if values.provider == "ollama" then
                if not url:match("^https?://") then
                    return false, "Ollama URL must start with http:// or https://"
                end
                if url:match('["\\\n\r%c]') then
                    return false, "Ollama URL contains invalid characters."
                end
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
                    keys = { "maxKeywords", "timeoutSecs", "claudeApiKey", "openaiApiKey", "geminiApiKey", "provider", "ollamaUrl" },
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
            prefs.claudeModel      = props.claudeModel
            prefs.openaiModel      = props.openaiModel
            prefs.geminiModel      = props.geminiModel

            -- Store API keys in macOS Keychain, clear from plaintext prefs.
            -- Strip whitespace here (newlines from paste, leading/trailing
            -- spaces) so stored keys are always clean.
            local function cleanKey(k) return (k or ""):gsub("%s+", "") end
            Prefs.storeApiKey("claude_api_key", cleanKey(props.claudeApiKey))
            Prefs.storeApiKey("openai_api_key", cleanKey(props.openaiApiKey))
            Prefs.storeApiKey("gemini_api_key", cleanKey(props.geminiApiKey))
            prefs.claudeApiKey     = nil
            prefs.openaiApiKey     = nil
            prefs.geminiApiKey     = nil
            prefs.maxKeywords      = math.floor(maxKw)
            prefs.timeoutSecs      = math.floor(timeout)
            prefs.useGPS           = props.useGPS
            prefs.useFolderContext = props.useFolderContext
            prefs.skipKeyworded    = props.skipKeyworded
            prefs.parentKeyword    = props.parentKeyword
            prefs.keywordCase      = props.keywordCase
            prefs.prompt           = props.prompt
            prefs.enableLogging    = props.enableLogging
            prefs.logFolder        = props.logFolder
            prefs.folderAliases    = props.folderAliases

            -- Save basePrompt: empty = use default, so future plugin updates take effect
            local trimmedBase = Engine.trim(props.basePromptDisplay or "")
            if trimmedBase == "" or trimmedBase == Engine.BASE_PROMPT then
                prefs.basePrompt = ""
            else
                prefs.basePrompt = props.basePromptDisplay
            end
        end

    end)
end)
