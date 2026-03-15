--[[
  CompareModels.lua
  ─────────────────────────────────────────────────────────────────────────────
  Compare keyword output across multiple models without saving to catalog.
  Select one photo, pick 2+ models, see side-by-side results.

  Invoked via Library > Plugin Extras > Compare Models — Selected Photo
--]]

local LrApplication     = import 'LrApplication'
local LrBinding         = import 'LrBinding'
local LrDate            = import 'LrDate'
local LrDialogs         = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils       = import 'LrPathUtils'
local LrProgressScope   = import 'LrProgressScope'
local LrTasks           = import 'LrTasks'
local LrView            = import 'LrView'

local Engine = dofile(_PLUGIN.path .. '/AIEngine.lua')
local Prefs  = dofile(_PLUGIN.path .. '/Prefs.lua')

-- Cloud model lists from shared AIEngine module
local CLAUDE_MODELS = Engine.CLAUDE_MODELS
local OPENAI_MODELS = Engine.OPENAI_MODELS
local GEMINI_MODELS = Engine.GEMINI_MODELS

-- ── Build the model selection dialog ──────────────────────────────────────
-- Returns a list of selected models [{provider, model, label}] or nil if canceled.
local function showSelectionDialog(photo, settings)
    local f       = LrView.osFactory()
    local catalog = LrApplication.activeCatalog()

    -- Check Ollama status
    local installed, ollamaRunning = Engine.getInstalledModels(settings.ollamaUrl)

    -- Get up-to-date model list
    local remoteModels = Engine.fetchRemoteModels()
    local activeModels = remoteModels or Engine.VISION_MODELS

    -- If user's current model isn't in the list, add it
    local found = false
    for _, m in ipairs(activeModels) do
        if m.value == settings.model then found = true; break end
    end
    if not found then
        table.insert(activeModels, {
            value = settings.model,
            label = settings.model,
            info  = "Current model (custom)",
        })
    end

    -- Build list of available models for comparison
    local availableModels = {}

    -- Ollama models (only installed ones)
    if ollamaRunning then
        for _, m in ipairs(activeModels) do
            if Engine.isModelInstalled(installed, m.value) then
                table.insert(availableModels, {
                    provider = "ollama",
                    model    = m.value,
                    label    = m.label,
                    detail   = m.info or "",
                })
            end
        end
    end

    -- Claude models (only if API key is configured)
    local hasClaudeKey = settings.claudeApiKey and settings.claudeApiKey ~= ""
    if hasClaudeKey then
        for _, cm in ipairs(CLAUDE_MODELS) do
            table.insert(availableModels, {
                provider = "claude",
                model    = cm.value,
                label    = cm.label,
                detail   = cm.cost .. "/image",
            })
        end
    end

    -- OpenAI models (only if API key is configured)
    local hasOpenaiKey = settings.openaiApiKey and settings.openaiApiKey ~= ""
    if hasOpenaiKey then
        for _, om in ipairs(OPENAI_MODELS) do
            table.insert(availableModels, {
                provider = "openai",
                model    = om.value,
                label    = om.label,
                detail   = om.cost .. "/image",
            })
        end
    end

    -- Gemini models (only if API key is configured)
    local hasGeminiKey = settings.geminiApiKey and settings.geminiApiKey ~= ""
    if hasGeminiKey then
        for _, gm in ipairs(GEMINI_MODELS) do
            table.insert(availableModels, {
                provider = "gemini",
                model    = gm.value,
                label    = gm.label,
                detail   = gm.cost .. "/image",
            })
        end
    end

    if #availableModels < 2 then
        local msg = "Need at least 2 models to compare.\n\n"
        if not ollamaRunning then
            msg = msg .. "• Ollama is not running — start it to compare local models.\n"
        else
            local installedCount = 0
            for _, m in ipairs(activeModels) do
                if Engine.isModelInstalled(installed, m.value) then
                    installedCount = installedCount + 1
                end
            end
            if installedCount < 1 then
                msg = msg .. "• No Ollama vision models installed — install one from Settings.\n"
            end
        end
        if not hasClaudeKey then
            msg = msg .. "• No Claude API key configured — add one in Settings.\n"
        end
        if not hasOpenaiKey then
            msg = msg .. "• No OpenAI API key configured — add one in Settings.\n"
        end
        if not hasGeminiKey then
            msg = msg .. "• No Gemini API key configured — add one in Settings.\n"
        end
        LrDialogs.message("Compare Models", msg, "warning")
        return nil
    end

    -- Create property table for dialog
    return LrFunctionContext.callWithContext("CompareSelection", function(context)
        local props = LrBinding.makePropertyTable(context)

        -- Create a checkbox property for each model
        -- Default: check user's current model + first Claude model
        for i, m in ipairs(availableModels) do
            local key = "sel_" .. i
            local isCurrentOllama = (m.provider == "ollama" and m.model == settings.model)
            local isCurrentClaude = (m.provider == "claude" and m.model == settings.claudeModel)
            local isCurrentOpenai = (m.provider == "openai" and m.model == settings.openaiModel)
            local isCurrentGemini = (m.provider == "gemini" and m.model == settings.geminiModel)
            props[key] = isCurrentOllama or isCurrentClaude or isCurrentOpenai or isCurrentGemini
        end

        -- Prompt override
        props.useCustomPrompt = false
        props.customPrompt    = settings.prompt

        -- Photo info
        local path     = photo:getRawMetadata('path')
        local filename = LrPathUtils.leafName(path)

        -- Build checkbox rows grouped by provider
        local ollamaRows = {}
        local claudeRows = {}
        local openaiRows = {}
        local geminiRows = {}

        for i, m in ipairs(availableModels) do
            local key = "sel_" .. i
            local row = f:row {
                f:checkbox {
                    title = m.label,
                    value = LrView.bind(key),
                    width = 200,
                },
                f:static_text {
                    title      = m.detail,
                    text_color = LrView.kDisabledColor,
                },
            }
            if m.provider == "ollama" then
                table.insert(ollamaRows, row)
            elseif m.provider == "claude" then
                table.insert(claudeRows, row)
            elseif m.provider == "openai" then
                table.insert(openaiRows, row)
            elseif m.provider == "gemini" then
                table.insert(geminiRows, row)
            end
        end

        -- Build the dialog contents
        local sections = {
            spacing         = f:dialog_spacing(),
            fill_horizontal = 1,
            bind_to_object  = props,

            -- Photo info
            f:row {
                f:static_text {
                    title     = "Photo:",
                    width     = 80,
                    alignment = "right",
                },
                f:static_text {
                    title           = filename,
                    font            = "<system/bold>",
                    fill_horizontal = 1,
                },
            },

            f:separator { fill_horizontal = 1 },
        }

        -- Ollama section
        if #ollamaRows > 0 then
            local ollamaGroup = {
                title           = "Ollama",
                fill_horizontal = 1,
            }
            for _, row in ipairs(ollamaRows) do
                table.insert(ollamaGroup, row)
            end
            table.insert(sections, f:group_box(ollamaGroup))
        end

        -- Claude section
        if #claudeRows > 0 then
            local claudeGroup = {
                title           = "Claude",
                fill_horizontal = 1,
            }
            for _, row in ipairs(claudeRows) do
                table.insert(claudeGroup, row)
            end
            table.insert(sections, f:group_box(claudeGroup))
        end

        -- OpenAI section
        if #openaiRows > 0 then
            local openaiGroup = {
                title           = "OpenAI",
                fill_horizontal = 1,
            }
            for _, row in ipairs(openaiRows) do
                table.insert(openaiGroup, row)
            end
            table.insert(sections, f:group_box(openaiGroup))
        end

        -- Gemini section
        if #geminiRows > 0 then
            local geminiGroup = {
                title           = "Gemini",
                fill_horizontal = 1,
            }
            for _, row in ipairs(geminiRows) do
                table.insert(geminiGroup, row)
            end
            table.insert(sections, f:group_box(geminiGroup))
        end

        -- Prompt override
        table.insert(sections, f:separator { fill_horizontal = 1 })
        table.insert(sections, f:row {
            f:static_text {
                title = "",
                width = 80,
            },
            f:checkbox {
                title = "Use different custom instructions for this comparison",
                value = LrView.bind("useCustomPrompt"),
            },
        })
        table.insert(sections, f:row {
            f:static_text {
                title     = "Instructions:",
                width     = 80,
                alignment = "right",
            },
            f:edit_field {
                value           = LrView.bind("customPrompt"),
                enabled         = LrView.bind("useCustomPrompt"),
                width_in_chars  = 55,
                height_in_lines = 5,
            },
        })

        -- Validation message
        table.insert(sections, f:row {
            f:static_text {
                title = "",
                width = 80,
            },
            f:static_text {
                title      = "Select 2–5 models, then click Compare.",
                text_color = LrView.kDisabledColor,
            },
        })

        local contents = f:column(sections)

        local result = LrDialogs.presentModalDialog {
            title      = "Compare Models",
            contents   = contents,
            actionVerb = "Compare",
            actionBinding = {
                enabled = {
                    bind_to_object = props,
                    keys = (function()
                        local keys = {}
                        for i = 1, #availableModels do
                            table.insert(keys, "sel_" .. i)
                        end
                        return keys
                    end)(),
                    operation = function()
                        local count = 0
                        for i = 1, #availableModels do
                            if props["sel_" .. i] then count = count + 1 end
                        end
                        return count >= 2 and count <= 5
                    end,
                },
            },
        }

        if result ~= "ok" then return nil end

        -- Build list of selected models
        local selected = {}
        for i, m in ipairs(availableModels) do
            if props["sel_" .. i] then
                table.insert(selected, {
                    provider = m.provider,
                    model    = m.model,
                    label    = m.label,
                })
            end
        end

        -- Apply custom prompt if enabled
        local promptOverride = nil
        if props.useCustomPrompt then
            promptOverride = props.customPrompt
        end

        return selected, promptOverride
    end)
end

-- ── Run comparison and collect results ────────────────────────────────────
local function runComparison(photo, selectedModels, settings, promptOverride, context)
    local catalog = LrApplication.activeCatalog()

    -- Build folder hint and GPS info (same as normal keyword generation)
    local folderAliases = Engine.parseAliases(settings.folderAliases)
    local folderHint = nil
    if settings.useFolderContext then
        local parts = Engine.getFolderContext(photo, catalog, folderAliases)
        if #parts > 0 then
            folderHint = table.concat(parts, " > ")
        end
    end

    local gpsInfo = nil
    if settings.useGPS then
        local gps = photo:getRawMetadata('gps')
        if gps and gps.latitude and gps.longitude then
            gpsInfo = { latitude = gps.latitude, longitude = gps.longitude }
        end
    end

    -- Build prompt (using override if provided)
    local promptSettings = {
        prompt      = promptOverride or settings.prompt,
        maxKeywords = settings.maxKeywords,
    }
    local prompt = Engine.buildPrompt(promptSettings, folderHint, gpsInfo)

    -- Pre-render images (once per render size to avoid redundant renders)
    local hasOllama, hasCloud = false, false
    for _, m in ipairs(selectedModels) do
        if m.provider == "ollama" then hasOllama = true end
        if m.provider == "claude" or m.provider == "openai" or m.provider == "gemini" then
            hasCloud = true
        end
    end

    local progress = LrProgressScope({
        title           = "Compare Models — rendering image…",
        functionContext = context,
    })

    local ollamaImg, cloudImg
    local ollamaImgErr, cloudImgErr

    if hasOllama then
        local ts = tostring(math.floor(LrDate.currentTime() * 1000)) .. "_cmp_oll"
        ollamaImg, ollamaImgErr = Engine.prepareImage(photo, ts, "ollama")
    end
    if hasCloud then
        local ts = tostring(math.floor(LrDate.currentTime() * 1000)) .. "_cmp_cld"
        cloudImg, cloudImgErr = Engine.prepareImage(photo, ts, "claude")
    end

    -- Run each model sequentially
    local results = {}
    for i, m in ipairs(selectedModels) do
        if progress:isCanceled() then break end

        progress:setPortionComplete(i - 1, #selectedModels)
        progress:setCaption(string.format("[%d/%d] %s…", i, #selectedModels, m.label))

        local img = (m.provider == "ollama") and ollamaImg or cloudImg
        local imgErr = (m.provider == "ollama") and ollamaImgErr or cloudImgErr

        local entry = {
            label    = m.label,
            provider = m.provider,
            model    = m.model,
            keywords = {},
            raw      = "",
            elapsed  = 0,
            error    = nil,
        }

        if not img then
            entry.error = imgErr or "Could not prepare image"
        else
            local queryStart = LrDate.currentTime()
            local raw, err

            if m.provider == "claude" then
                raw, err = Engine.queryClaude(
                    img, prompt, m.model, settings.claudeApiKey, settings.timeoutSecs
                )
            elseif m.provider == "openai" then
                raw, err = Engine.queryOpenAI(
                    img, prompt, m.model, settings.openaiApiKey, settings.timeoutSecs
                )
            elseif m.provider == "gemini" then
                raw, err = Engine.queryGemini(
                    img, prompt, m.model, settings.geminiApiKey, settings.timeoutSecs
                )
            else
                raw, err = Engine.queryOllama(
                    img, prompt, m.model, settings.ollamaUrl, settings.timeoutSecs
                )
            end

            entry.elapsed = LrDate.currentTime() - queryStart

            if raw then
                entry.raw = raw
                entry.keywords = Engine.parseKeywords(raw, settings)
                if #entry.keywords == 0 then
                    entry.error = "No parseable keywords"
                end
            else
                entry.error = err or "Unknown error"
            end
        end

        table.insert(results, entry)
        LrTasks.sleep(0.05)
    end

    progress:done()
    return results
end

-- ── Show results dialog ──────────────────────────────────────────────────
-- Returns true if the user wants to compare again, false otherwise.
local function showResults(photo, results, promptOverride)
    local f = LrView.osFactory()

    local path     = photo:getRawMetadata('path')
    local filename = LrPathUtils.leafName(path)

    -- Keyword overlap analysis — build before columns so we can mark unique
    local allKeywords = {}  -- keyword (lowercase) -> count of models that have it
    for _, r in ipairs(results) do
        if not r.error then
            for _, kw in ipairs(r.keywords) do
                local key = kw:lower()
                allKeywords[key] = (allKeywords[key] or 0) + 1
            end
        end
    end

    -- Build a column for each model's results
    local columns = {}
    for _, r in ipairs(results) do
        local kwText
        if r.error then
            kwText = "⚠ " .. r.error
        elseif #r.keywords > 0 then
            -- Mark unique keywords (only found by this model) with ★
            local lines = {}
            for _, kw in ipairs(r.keywords) do
                local key = kw:lower()
                if allKeywords[key] == 1 then
                    table.insert(lines, kw .. "  ★")
                else
                    table.insert(lines, kw)
                end
            end
            kwText = table.concat(lines, "\n")
        else
            kwText = "(no keywords)"
        end

        local headerColor = r.error and LrView.kWarningColor or nil
        local kwCount = r.error and "" or string.format("  (%d keywords)", #r.keywords)

        table.insert(columns, f:column {
            spacing = f:control_spacing(),
            width   = 200,

            f:static_text {
                title      = r.label,
                font       = "<system/bold>",
                text_color = headerColor,
            },
            f:static_text {
                title      = string.format("%.1fs%s", r.elapsed, kwCount),
                text_color = LrView.kDisabledColor,
            },
            f:separator { fill_horizontal = 1 },
            f:static_text {
                title       = kwText,
                height_in_lines = math.max(5, math.min(25, #r.keywords + 1)),
                width       = 190,
            },
        })
    end

    -- Find shared keywords (appear in 2+ models)
    local shared = {}
    for kw, count in pairs(allKeywords) do
        if count >= 2 then
            table.insert(shared, kw)
        end
    end
    table.sort(shared)

    local sharedText = #shared > 0
        and ("Shared across 2+ models: " .. table.concat(shared, ", "))
        or "No keywords shared between models."

    -- Build prompt info
    local promptInfo = promptOverride
        and "Custom prompt used for this comparison."
        or "Default prompt from Settings."

    local contents = f:column {
        spacing         = f:dialog_spacing(),
        fill_horizontal = 1,

        -- Photo info
        f:row {
            f:static_text {
                title = "Photo:  ",
            },
            f:static_text {
                title = filename,
                font  = "<system/bold>",
            },
        },
        f:static_text {
            title      = promptInfo,
            text_color = LrView.kDisabledColor,
        },

        f:separator { fill_horizontal = 1 },

        -- Model results side by side
        f:scrolled_view {
            horizontal_scroller = true,
            width               = math.min(210 * #results, 1050),
            height              = 400,
            f:row(columns),
        },

        f:separator { fill_horizontal = 1 },

        -- Overlap analysis
        f:static_text {
            title           = sharedText,
            text_color      = LrView.kDisabledColor,
            fill_horizontal = 1,
            height_in_lines = 2,
        },
        f:static_text {
            title      = "★ = unique to this model",
            text_color = LrView.kDisabledColor,
        },
    }

    local result = LrDialogs.presentModalDialog {
        title      = "Compare Models — Results",
        contents   = contents,
        actionVerb = "Compare Again",
        otherVerb  = "Done",
        cancelVerb = "< exclude",
    }

    return result == "ok"  -- "ok" = Compare Again, "other" = Done
end

-- ── Entry point ──────────────────────────────────────────────────────────
LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("AICompareModels", function(context)

        local SETTINGS = Prefs.getPrefs()
        local catalog  = LrApplication.activeCatalog()
        local targetPhotos = catalog:getTargetPhotos()

        -- Must select exactly one photo
        if #targetPhotos == 0 then
            LrDialogs.message("Compare Models",
                "No photo selected.\n\nSelect one photo in the Library grid and try again.", "info")
            return
        end
        if #targetPhotos > 1 then
            LrDialogs.message("Compare Models",
                "Please select exactly one photo for comparison.\n\n" ..
                "The comparison runs each selected model on the same image " ..
                "so you can compare keyword quality side by side.", "info")
            return
        end

        local photo = targetPhotos[1]

        -- Check file type
        local path = photo:getRawMetadata('path')
        if not Engine.SUPPORTED_EXTS[Engine.getExt(path)] then
            LrDialogs.message("Compare Models",
                "Unsupported file type: " .. Engine.getExt(path) .. "\n\n" ..
                "Supported: JPEG, PNG, TIFF, WEBP, HEIC, RAW.", "warning")
            return
        end

        -- Compare loop — allows "Compare Again" from results
        local compareAgain = true
        while compareAgain do
            -- Show model selection dialog
            local selectedModels, promptOverride = showSelectionDialog(photo, SETTINGS)
            if not selectedModels then return end

            -- Run comparison
            local results = runComparison(photo, selectedModels, SETTINGS, promptOverride, context)

            -- Show results (returns true if user clicked "Compare Again")
            if #results > 0 then
                compareAgain = showResults(photo, results, promptOverride)
            else
                compareAgain = false
            end
        end

    end)
end)
