--[[
  GenerateKeywords.lua
  ─────────────────────────────────────────────────────────────────────────────
  Iterates over selected Lightroom Classic photos, renders each one via
  LrExportSession, sends to AI provider (Ollama/Claude/OpenAI/Gemini),
  parses keywords, and writes them to the LR catalog.

  macOS only. Settings via Library > Plugin Extras > Settings...
--]]

-- ── LR SDK imports ─────────────────────────────────────────────────────────
local LrApplication     = import 'LrApplication'
local LrDate            = import 'LrDate'
local LrDialogs         = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils       = import 'LrPathUtils'
local LrProgressScope   = import 'LrProgressScope'
local LrTasks           = import 'LrTasks'

local Engine = dofile(_PLUGIN.path .. '/AIEngine.lua')
local Prefs  = dofile(_PLUGIN.path .. '/Prefs.lua')

-- ── Logger ────────────────────────────────────────────────────────────────
-- Writes incrementally so crash mid-run still captures everything up to that point.
local Logger = {}

function Logger:init(settings, photoCount)
    self.enabled = settings.enableLogging
    self.fileHandle = nil
    self.startTime = LrDate.currentTime()
    if not self.enabled then return end

    local LrFileUtils = import 'LrFileUtils'
    local timestamp = LrDate.timeToUserFormat(self.startTime, "%Y-%m-%d_%H-%M-%S")
    local folder = settings.logFolder
    if not folder or folder == "" then
        folder = LrPathUtils.getStandardFilePath('documents')
    end

    -- Validate log folder exists, fall back to Documents
    if not LrFileUtils.exists(folder) then
        local fallback = LrPathUtils.getStandardFilePath('documents')
        self:_writeRaw("WARNING: Log folder does not exist: " .. folder .. " — using " .. fallback .. "\n")
        folder = fallback
    end

    self.filePath = folder .. "/AI_Keywords_" .. timestamp .. ".log"
    self.fileHandle = io.open(self.filePath, "w")

    -- Compact header
    self:log("═══════════════════════════════════════════════════════════")
    self:log("AI Keywords — Run started at " .. LrDate.timeToUserFormat(self.startTime, "%Y-%m-%d %H:%M:%S"))

    local modelName
    if settings.provider == "ollama" then
        modelName = settings.model
    elseif settings.provider == "claude" then
        modelName = settings.claudeModel
    elseif settings.provider == "openai" then
        modelName = settings.openaiModel
    elseif settings.provider == "gemini" then
        modelName = settings.geminiModel
    end
    self:log(string.format("Provider: %s  |  Model: %s", settings.provider, modelName or "unknown"))
    self:log(string.format("Processing %d photos  |  Max keywords: %d  |  Case: %s",
        photoCount, settings.maxKeywords, settings.keywordCase))
    self:log(string.format("Parent keyword: %s  |  Skip keyworded: %s",
        (settings.parentKeyword ~= "" and settings.parentKeyword or "(none)"),
        tostring(settings.skipKeyworded)))
    self:log(string.format("Folder context: %s  |  GPS context: %s",
        settings.useFolderContext and "enabled" or "disabled",
        settings.useGPS and "enabled" or "disabled"))

    local custom = settings.prompt or ""
    if custom ~= "" then
        self:log("Custom instructions: " .. custom)
    end

    self:log("═══════════════════════════════════════════════════════════")
end

function Logger:_writeRaw(text)
    if self.fileHandle then
        self.fileHandle:write(text)
        self.fileHandle:flush()
    end
end

function Logger:log(message)
    if not self.enabled then return end
    local ts = LrDate.timeToUserFormat(LrDate.currentTime(), "%H:%M:%S")
    local line = ts .. "  " .. message .. "\n"
    self:_writeRaw(line)
end

function Logger:logImageStart(index, total, filename)
    if not self.enabled then return end
    self:_writeRaw("\n")
    self:log(string.format("[%d/%d] %s", index, total, filename))
end

function Logger:logDetail(label, value)
    if not self.enabled then return end
    local ts = LrDate.timeToUserFormat(LrDate.currentTime(), "%H:%M:%S")
    self:_writeRaw(string.format("%s         %s: %s\n", ts, label, value))
end

function Logger:logResult(result, detail)
    if not self.enabled then return end
    local ts = LrDate.timeToUserFormat(LrDate.currentTime(), "%H:%M:%S")
    if result == "success" then
        self:_writeRaw(string.format("%s         ✓ %s\n", ts, detail))
    elseif result == "skipped" then
        self:_writeRaw(string.format("%s         SKIP — %s\n", ts, detail))
    else
        self:_writeRaw(string.format("%s         ERROR — %s\n", ts, detail))
    end
end

function Logger:finish(successCount, errorCount, skippedCount)
    if not self.enabled then return end
    local elapsed = LrDate.currentTime() - self.startTime
    self:_writeRaw("\n")
    self:log("═══════════════════════════════════════════════════════════")
    self:log(string.format("Run complete — %d keyworded, %d errors, %d skipped (%.0fs elapsed)",
        successCount, errorCount, skippedCount, elapsed))
    self:log("═══════════════════════════════════════════════════════════")

    if self.fileHandle then
        self.fileHandle:close()
        self.fileHandle = nil
    end
end

-- ── Query router (wraps Engine functions with settings) ──────────────────
local function queryModel(photo, folderHint, gpsInfo, settings, imageIndex)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000)) .. "_" .. tostring(imageIndex or 0)

    local img, err = Engine.prepareImage(photo, ts, settings.provider)
    if not img then return nil, err end

    local prompt = Engine.buildPrompt(settings, folderHint, gpsInfo)

    local raw
    if settings.provider == "claude" then
        raw, err = Engine.queryClaude(img, prompt, settings.claudeModel,
            settings.claudeApiKey, settings.timeoutSecs)
    elseif settings.provider == "openai" then
        raw, err = Engine.queryOpenAI(img, prompt, settings.openaiModel,
            settings.openaiApiKey, settings.timeoutSecs)
    elseif settings.provider == "gemini" then
        raw, err = Engine.queryGemini(img, prompt, settings.geminiModel,
            settings.geminiApiKey, settings.timeoutSecs)
    else
        raw, err = Engine.queryOllama(img, prompt, settings.model,
            settings.ollamaUrl, settings.timeoutSecs)
    end

    if not raw then return nil, nil, err end

    local keywords = Engine.parseKeywords(raw, settings)
    if #keywords == 0 then
        return nil, raw, "No parseable keywords. Raw: " .. raw:sub(1, 200)
    end

    return keywords, raw, nil
end

-- ── Catalog keyword writer ───────────────────────────────────────────────
-- Returns "executed", "aborted", or an error string.
local function applyKeywords(catalog, photo, keywords, filename, settings)
    local writeResult = catalog:withWriteAccessDo(
        "AI Keywords - " .. filename,
        function()
            local parent = nil
            local hasParent = settings.parentKeyword and settings.parentKeyword ~= ""
            if hasParent then
                parent = catalog:createKeyword(settings.parentKeyword, {}, false, nil, true)
            end

            for _, kwText in ipairs(keywords) do
                -- First call: returnExisting=true only when no parent (flat keywords).
                -- With a parent, returnExisting=false avoids returning a stale root-level
                -- keyword with the same name. If that fails, retry with returnExisting=true.
                local kw = catalog:createKeyword(kwText, {}, true, parent, not hasParent)
                if not kw then
                    kw = catalog:createKeyword(kwText, {}, true, parent, true)
                end
                if kw then photo:addKeyword(kw) end
            end
        end,
        { timeout = 10 }
    )
    return writeResult
end

-- ── Entry point ──────────────────────────────────────────────────────────
LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext("AIGenerateKeywords", function(context)

        local SETTINGS = Prefs.getPrefs()
        local catalog      = LrApplication.activeCatalog()
        local targetPhotos = catalog:getTargetPhotos()

        if #targetPhotos == 0 then
            LrDialogs.message("AI Keywords",
                "No photos selected.\n\nSelect one or more photos in the Library grid and try again.", "info")
            return
        end

        -- Validate API keys
        if SETTINGS.provider == "claude" and (SETTINGS.claudeApiKey == nil or SETTINGS.claudeApiKey == "") then
            LrDialogs.message("AI Keywords",
                "Claude API selected but no API key configured.\n\nOpen Settings and enter your Anthropic API key.", "warning")
            return
        end
        if SETTINGS.provider == "openai" and (SETTINGS.openaiApiKey == nil or SETTINGS.openaiApiKey == "") then
            LrDialogs.message("AI Keywords",
                "OpenAI selected but no API key configured.\n\nOpen Settings and enter your OpenAI API key.", "warning")
            return
        end
        if SETTINGS.provider == "gemini" and (SETTINGS.geminiApiKey == nil or SETTINGS.geminiApiKey == "") then
            LrDialogs.message("AI Keywords",
                "Gemini selected but no API key configured.\n\nOpen Settings and enter your Google AI API key.", "warning")
            return
        end

        -- Split into processable vs unsupported
        local toProcess, skipped = {}, {}
        for _, photo in ipairs(targetPhotos) do
            local path = photo:getRawMetadata('path')
            if Engine.SUPPORTED_EXTS[Engine.getExt(path)] then
                table.insert(toProcess, photo)
            else
                table.insert(skipped, LrPathUtils.leafName(path))
            end
        end

        if #toProcess == 0 then
            LrDialogs.message("AI Keywords - Skipped",
                "No supported files found.\n\n" ..
                "Supported: JPEG, PNG, TIFF, WEBP, HEIC, RAW (CR2, CR3, NEF, ARW, DNG, etc.)\n\n" ..
                "Skipped: " .. table.concat(skipped, ", "):sub(1, 200), "warning")
            return
        end

        if #toProcess > 50 then
            local confirm = LrDialogs.confirm(
                "Process " .. #toProcess .. " Photos?",
                "This may take several minutes depending on your hardware.\n\nProceed?",
                "Proceed", "Cancel")
            if confirm ~= "ok" then return end
        end

        -- Clean up orphaned temp files from interrupted runs
        pcall(function()
            local td = Engine.TEMP_DIR
            LrTasks.execute(string.format("rm -f %s/ai_kw_req_* %s/ai_kw_resp_* %s/ai_kw_cfg_* 2>/dev/null", td, td, td))
        end)

        -- Initialize logger
        local log = setmetatable({}, { __index = Logger })
        log:init(SETTINGS, #toProcess)

        -- Parse folder aliases once (not per-image)
        local folderAliases = Engine.parseAliases(SETTINGS.folderAliases)

        local modelName, providerLabel
        if SETTINGS.provider == "claude" then
            modelName = SETTINGS.claudeModel
            providerLabel = "Claude API"
        elseif SETTINGS.provider == "openai" then
            modelName = SETTINGS.openaiModel
            providerLabel = "OpenAI"
        elseif SETTINGS.provider == "gemini" then
            modelName = SETTINGS.geminiModel
            providerLabel = "Gemini"
        else
            modelName = SETTINGS.model
            providerLabel = "Ollama"
        end
        local progress = LrProgressScope({
            title           = "AI Keywords (" .. providerLabel .. " — " .. modelName .. ")",
            functionContext = context,
        })

        local successCount   = 0
        local skippedKwCount = 0
        local errorLog       = {}

        -- Log the base prompt once (without per-image location context)
        local samplePrompt = Engine.buildPrompt(SETTINGS, nil, nil)
        log:log("Prompt: " .. samplePrompt)

        for i, photo in ipairs(toProcess) do
            if progress:isCanceled() then
                log:log("CANCELED by user at image " .. i)
                break
            end

            local path     = photo:getRawMetadata('path')
            local filename = LrPathUtils.leafName(path)

            progress:setPortionComplete(i - 1, #toProcess)
            progress:setCaption(string.format("[%d/%d] %s", i, #toProcess, filename))

            -- Skip already-keyworded photos
            local shouldSkip = false
            if SETTINGS.skipKeyworded then
                local existingKw = photo:getRawMetadata('keywords')
                if existingKw and #existingKw > 0 then
                    skippedKwCount = skippedKwCount + 1
                    shouldSkip = true
                    log:logImageStart(i, #toProcess, filename)
                    log:logResult("skipped", "already has " .. #existingKw .. " keywords")
                end
            end

            if not shouldSkip then

            -- Log image start
            log:logImageStart(i, #toProcess, filename)

            -- Build folder hint
            local folderHint = nil
            if SETTINGS.useFolderContext then
                local parts = Engine.getFolderContext(photo, catalog, folderAliases)
                if #parts > 0 then
                    folderHint = table.concat(parts, " > ")
                    log:logDetail("Folder", folderHint)
                end
            end

            -- Extract GPS coordinates if enabled and available
            local gpsInfo = nil
            if SETTINGS.useGPS then
                local gps = photo:getRawMetadata('gps')
                if gps and gps.latitude and gps.longitude then
                    gpsInfo = { latitude = gps.latitude, longitude = gps.longitude }
                    log:logDetail("GPS", string.format("%.4f, %.4f", gpsInfo.latitude, gpsInfo.longitude))
                end
            end

            -- Query AI model (render + send + parse)
            local queryStart = LrDate.currentTime()
            local keywords, rawResponse, err = queryModel(photo, folderHint, gpsInfo, SETTINGS, i)
            local queryElapsed = LrDate.currentTime() - queryStart

            if rawResponse then
                log:logDetail("Response", rawResponse:sub(1, 500))
            end
            log:logDetail("Time", string.format("%.1fs", queryElapsed))

            if keywords then
                -- Write keywords to catalog
                LrTasks.yield()
                local writeOk, writeErr = LrTasks.pcall(function()
                    local writeResult = applyKeywords(catalog, photo, keywords, filename, SETTINGS)
                    if writeResult ~= "executed" then
                        error("Catalog write not executed (result: " .. tostring(writeResult) .. ")")
                    end
                end)
                LrTasks.yield()

                if writeOk then
                    successCount = successCount + 1
                    log:logResult("success", #keywords .. " keywords written: " .. table.concat(keywords, ", "))
                else
                    table.insert(errorLog, "- " .. filename .. "\n  Write error: " .. tostring(writeErr))
                    log:logResult("error", "Write failed: " .. tostring(writeErr))
                end
            else
                table.insert(errorLog, "- " .. filename .. "\n  " .. (err or "unknown error"))
                log:logResult("error", err or "unknown error")
            end

            end -- if not shouldSkip

            LrTasks.sleep(0.05)
        end

        progress:done()

        -- Finish log
        log:finish(successCount, #errorLog, skippedKwCount)

        -- Build completion message
        local lines = { string.format("%d photo(s) keyworded via %s (%s)", successCount, providerLabel, modelName) }
        if skippedKwCount > 0 then
            lines[#lines + 1] = string.format("%d photo(s) skipped (already keyworded)", skippedKwCount)
        end
        if #skipped > 0 then
            lines[#lines + 1] = string.format("%d file(s) skipped (unsupported format)", #skipped)
        end
        if #errorLog > 0 then
            lines[#lines + 1] = string.format("%d error(s):\n%s",
                #errorLog, table.concat(errorLog, "\n"):sub(1, 1200))
        end
        if log.enabled and log.filePath then
            lines[#lines + 1] = "\nLog saved to: " .. log.filePath
        end

        LrDialogs.message("AI Keywords - Complete", table.concat(lines, "\n"), "info")

    end)
end)
