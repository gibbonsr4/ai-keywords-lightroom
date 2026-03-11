--[[
  GenerateKeywords.lua
  ─────────────────────────────────────────────────────────────────────────────
  Iterates over selected Lightroom Classic photos, renders each one via
  LrExportSession, sends to Ollama or Claude API, parses keywords, and
  writes them to the LR catalog.

  macOS only. Settings via Library > Plugin Extras > Settings...
--]]

-- ── LR SDK imports ─────────────────────────────────────────────────────────
local LrApplication     = import 'LrApplication'
local LrDate            = import 'LrDate'
local LrDialogs         = import 'LrDialogs'
local LrExportSession   = import 'LrExportSession'
local LrFileUtils       = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils       = import 'LrPathUtils'
local LrProgressScope   = import 'LrProgressScope'
local LrTasks           = import 'LrTasks'

local json   = dofile(_PLUGIN.path .. '/dkjson.lua')
local Prefs  = dofile(_PLUGIN.path .. '/Prefs.lua')

-- ── Constants ─────────────────────────────────────────────────────────────
-- SUPPORTED_EXTS is checked before LrExportSession to give clear error messages
-- for unsupported formats (e.g. PSD, AI) instead of opaque render failures.
local SUPPORTED_EXTS = {
    jpg = true, jpeg = true, png = true,
    tif = true, tiff = true, webp = true,
    heic = true, heif = true,
    -- RAW formats — LrExportSession handles these natively
    cr2 = true, cr3 = true, nef = true, arw = true,
    raf = true, orf = true, rw2 = true, dng = true,
    pef = true, srw = true,
}

local SKIP_FOLDERS = {
    ["photos"]    = true, ["photo"]    = true,
    ["images"]    = true, ["image"]    = true,
    ["lightroom"] = true, ["lr"]       = true,
    ["catalog"]   = true, ["catalogs"] = true,
    ["imports"]   = true, ["import"]   = true,
    ["pictures"]  = true, ["picture"]  = true,
    ["downloads"] = true, ["desktop"]  = true,
    ["documents"] = true, ["raw"]      = true,
    ["jpegs"]     = true, ["edited"]   = true,
    ["selects"]   = true, ["exports"]  = true,
    ["backup"]    = true,
}

local TEMP_DIR = "/tmp"

-- Claude's base64 image limit is 5MB. Base64 is ~4/3 of raw, so raw limit ~3.75MB.
local CLAUDE_MAX_RAW_BYTES = 3750000

-- ── Logger ────────────────────────────────────────────────────────────────
-- Writes incrementally so crash mid-run still captures everything up to that point.
local Logger = {}

function Logger:init(settings)
    self.enabled = settings.enableLogging
    self.fileHandle = nil
    self.startTime = LrDate.currentTime()
    if not self.enabled then return end

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

    self:log("═══════════════════════════════════════════════════════════")
    self:log("AI Keywords — Run started at " .. LrDate.timeToUserFormat(self.startTime, "%Y-%m-%d %H:%M:%S"))
    self:log("Provider: " .. settings.provider)
    if settings.provider == "ollama" then
        self:log("Model: " .. settings.model)
        self:log("Ollama URL: " .. settings.ollamaUrl)
    else
        self:log("Model: " .. settings.claudeModel)
    end
    self:log("Max keywords: " .. tostring(settings.maxKeywords))
    self:log("Keyword case: " .. settings.keywordCase)
    self:log("Parent keyword: " .. (settings.parentKeyword ~= "" and settings.parentKeyword or "(none)"))
    self:log("Folder context: " .. tostring(settings.useFolderContext))
    self:log("Skip keyworded: " .. tostring(settings.skipKeyworded))
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

function Logger:logImage(filename, result, detail)
    if not self.enabled then return end
    if result == "success" then
        self:log("[OK]    " .. filename .. "  →  " .. detail)
    elseif result == "skipped" then
        self:log("[SKIP]  " .. filename .. "  →  " .. detail)
    else
        self:log("[FAIL]  " .. filename .. "  →  " .. detail)
    end
end

function Logger:finish(successCount, errorCount, skippedCount)
    if not self.enabled then return end
    local elapsed = LrDate.currentTime() - self.startTime
    self:log("═══════════════════════════════════════════════════════════")
    self:log(string.format("Run complete — %d keyworded, %d errors, %d skipped (%.0fs elapsed)",
        successCount, errorCount, skippedCount, elapsed))
    self:log("═══════════════════════════════════════════════════════════")

    if self.fileHandle then
        self.fileHandle:close()
        self.fileHandle = nil
    end
end

-- ── Base64 encoder ────────────────────────────────────────────────────────
-- Pre-built lookup table avoids repeated string.sub() calls per character.
local B64_CHAR = {}
do
    local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 0, 63 do B64_CHAR[i] = B64:sub(i + 1, i + 1) end
end

local function base64Encode(data)
    local result = {}
    local len = #data
    for i = 1, len - 2, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        result[#result + 1] = B64_CHAR[math.floor(n / 262144)]
            .. B64_CHAR[math.floor(n / 4096) % 64]
            .. B64_CHAR[math.floor(n / 64) % 64]
            .. B64_CHAR[n % 64]
    end
    local r = len % 3
    if r == 1 then
        local n = data:byte(len) * 65536
        result[#result + 1] = B64_CHAR[math.floor(n / 262144)]
            .. B64_CHAR[math.floor(n / 4096) % 64] .. '=='
    elseif r == 2 then
        local b1, b2 = data:byte(len - 1, len)
        local n = b1 * 65536 + b2 * 256
        result[#result + 1] = B64_CHAR[math.floor(n / 262144)]
            .. B64_CHAR[math.floor(n / 4096) % 64]
            .. B64_CHAR[math.floor(n / 64) % 64] .. '='
    end
    return table.concat(result)
end

-- ── File & string helpers ─────────────────────────────────────────────────
local function readBinaryFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*all'); f:close(); return data
end

local function fileSize(path)
    local attrs = LrFileUtils.fileAttributes(path)
    return (attrs and attrs.fileSize) or 0
end

local function getExt(path)
    return (LrPathUtils.extension(path) or ''):lower()
end

local function trim(s)
    return s:match("^%s*(.-)%s*$") or ''
end

local function normalizeCase(s, mode)
    if mode == "lowercase" then return s:lower()
    elseif mode == "title_case" then
        return s:gsub("(%a)([%a']*)", function(a, b) return a:upper() .. b:lower() end)
    end
    return s
end

local function safeDelete(path)
    pcall(function() LrFileUtils.delete(path) end)
end

-- POSIX-safe shell escaping: wrap in single quotes, escape internal single quotes.
-- This prevents injection via $(...), backticks, double-quote tricks, etc.
local function shellEscape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- ── Folder aliases ────────────────────────────────────────────────────────
-- Parses "DR=Dominican Republic; CR=Costa Rica" into a lookup table.
local function parseAliases(aliasStr)
    local aliases = {}
    if not aliasStr or aliasStr == "" then return aliases end
    for entry in aliasStr:gmatch("[^;]+") do
        local key, val = entry:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if key and val and key ~= "" and val ~= "" then
            aliases[key:lower()] = val
        end
    end
    return aliases
end

-- ── Folder context ────────────────────────────────────────────────────────
local function getFolderContext(photo, catalog, aliases)
    local fullPath = photo:getRawMetadata('path')
    local relPath = fullPath
    for _, rootFolder in ipairs(catalog:getFolders()) do
        local rootPath = rootFolder:getPath()
        if rootPath:sub(-1) ~= "/" then rootPath = rootPath .. "/" end
        if fullPath:sub(1, #rootPath) == rootPath then
            relPath = fullPath:sub(#rootPath + 1); break
        end
    end
    local folderPart = relPath:match("^(.*)/[^/]+$") or ""
    local parts = {}
    for part in folderPart:gmatch("[^/]+") do
        local lower = part:lower()
        if not SKIP_FOLDERS[lower] and not lower:match("^%d%d%d%d$") then
            -- Apply aliases: check each word in the folder name
            local words = {}
            for word in part:gmatch("%S+") do
                local wordLower = word:lower()
                -- Skip date-like tokens (e.g. "12-2025", "2025-12", "12-25")
                if wordLower:match("^%d+%-?%d*$") then
                    -- skip pure numeric/date tokens
                else
                    local replacement = aliases[wordLower]
                    table.insert(words, replacement or word)
                end
            end
            local expanded = table.concat(words, " ")
            expanded = trim(expanded)
            if expanded ~= "" then
                table.insert(parts, expanded)
            end
        end
    end
    return parts
end

-- ── Image rendering via LrExportSession ──────────────────────────────────
-- Uses Lightroom's own render pipeline instead of sips. Handles every format
-- LR can open (RAW, HEIC, PSD, TIFF, etc.) and respects Develop adjustments.
-- Always outputs sRGB JPEG with minimal metadata, no sharpening/watermark.
-- Returns (jpegPath, fileSize) or (nil, errorMsg).
local function renderImage(photo, ts, maxDimension)
    local dim = maxDimension or 1024

    local exportSettings = {
        LR_export_destinationType       = 'specificFolder',
        LR_export_destinationPathPrefix = TEMP_DIR,
        LR_export_useSubfolder          = false,
        LR_format                       = 'JPEG',
        LR_jpeg_quality                 = 0.70,
        LR_export_colorSpace            = 'sRGB',
        LR_size_doConstrain             = true,
        LR_size_doNotEnlarge            = true,
        LR_size_maxHeight               = dim,
        LR_size_maxWidth                = dim,
        LR_size_resizeType              = 'longEdge',
        LR_reimportExportedPhoto        = false,
        LR_minimizeEmbeddedMetadata     = true,
        LR_outputSharpeningOn           = false,
        LR_useWatermark                 = false,
        LR_metadata_keywordOptions      = 'flat',
        LR_removeFaceMetadata           = true,
        LR_removeLocationMetadata       = true,
    }

    local session = LrExportSession({
        photosToExport = { photo },
        exportSettings = exportSettings,
    })

    for _, rendition in session:renditions() do
        local success, pathOrMsg = rendition:waitForRender()
        if success then
            local size = fileSize(pathOrMsg)
            if size > 0 then
                return pathOrMsg, size
            end
            safeDelete(pathOrMsg)
            return nil, "Render produced empty file"
        else
            return nil, "LR render failed: " .. tostring(pathOrMsg)
        end
    end

    return nil, "No renditions produced"
end

-- Minimum image dimension — images smaller than this won't produce useful keywords
local MIN_IMAGE_DIMENSION = 200

-- ── Prepare image for API ────────────────────────────────────────────────
-- Renders via LrExportSession at provider-appropriate size, reads,
-- base64-encodes. For Claude, retries at smaller dimensions if needed.
local function prepareImage(photo, ts, provider)
    -- Check minimum dimensions
    local dims = photo:getRawMetadata('croppedDimensions')
    if dims then
        local minEdge = math.min(dims.width, dims.height)
        if minEdge < MIN_IMAGE_DIMENSION then
            return nil, string.format("Image too small (%dx%d). Minimum edge: %dpx.",
                dims.width, dims.height, MIN_IMAGE_DIMENSION)
        end
    end

    -- Provider-appropriate render size:
    -- Claude: 1568px per Anthropic's recommendation for best accuracy
    -- Ollama: 1024px (local models work well at this size)
    local renderDim = (provider == "claude") and 1568 or 1024

    local renderedPath, renderedSize = renderImage(photo, ts, renderDim)

    -- For Claude: retry at smaller sizes if too large for API
    if provider == "claude" and renderedPath and renderedSize > CLAUDE_MAX_RAW_BYTES then
        safeDelete(renderedPath)
        renderedPath, renderedSize = renderImage(photo, ts .. "_sm", 1024)
    end
    if provider == "claude" and renderedPath and renderedSize > CLAUDE_MAX_RAW_BYTES then
        safeDelete(renderedPath)
        renderedPath, renderedSize = renderImage(photo, ts .. "_xs", 768)
    end

    if not renderedPath then
        return nil, renderedSize  -- renderedSize is the error message when path is nil
    end

    local imageData = readBinaryFile(renderedPath)
    safeDelete(renderedPath)

    if not imageData then
        return nil, "Cannot read rendered file"
    end

    -- Final size check for Claude
    if provider == "claude" and #imageData > CLAUDE_MAX_RAW_BYTES then
        return nil, string.format(
            "Image too large for Claude API (%.1f MB). Try exporting a smaller JPEG.",
            #imageData / 1048576
        )
    end

    return {
        base64   = base64Encode(imageData),
        fileSize = #imageData,
    }, nil
end

-- ── Build prompt with folder context and GPS ─────────────────────────────
local function buildPrompt(settings, folderHint, gpsInfo)
    local prompt = settings.prompt

    -- Prepend location context
    local contextParts = {}
    if gpsInfo then
        table.insert(contextParts, string.format(
            "GPS coordinates: %.4f, %.4f", gpsInfo.latitude, gpsInfo.longitude))
    end
    if folderHint and folderHint ~= "" then
        table.insert(contextParts, "Folder path: " .. folderHint)
    end

    if #contextParts > 0 then
        prompt = (
            "Location context for this photo: " ..
            table.concat(contextParts, ". ") .. ". " ..
            "Use this to inform location-related keywords if it fits the image. " ..
            prompt
        )
    end

    -- Append output format instruction (separate from user-editable prompt)
    prompt = prompt ..
        string.format(" Return up to %d keywords.", settings.maxKeywords) ..
        " Return ONLY a comma-separated list — no sentences, no numbering, no explanation." ..
        " Do not include GPS coordinates, folder paths, or metadata in your keywords."
    return prompt
end

-- ── Parse keywords from model output ─────────────────────────────────────
local function parseKeywords(raw, settings)
    local keywords = {}
    local seen = {}
    for kw in raw:gmatch("[^,\n]+") do
        local t = trim(kw)
        -- Strip markdown formatting
        t = t:gsub("%*%*", "")          -- bold markers
        t = t:gsub("^#+%s*", "")        -- heading markers
        t = t:gsub("`", "")             -- inline code
        -- Strip numbering, bullets, Unicode bullets
        t = t:gsub("^%d+[%.%)]%s+", "")
        t = t:gsub("^[%-%*]%s+", "")
        t = t:gsub("^\226\128\162%s*", "")
        -- Strip trailing punctuation
        t = t:gsub("[%.,:;!?]+$", "")
        t = trim(t)

        -- Filter out GPS coordinates and pure numbers
        if t:match("^%-?%d+%.%d+$") then t = "" end                     -- single coordinate
        if t:match("^%-?%d+%.%d+%s*[,;]%s*%-?%d+%.%d+$") then t = "" end  -- coordinate pair
        if t:match("^%d+$") then t = "" end                              -- pure integer

        t = normalizeCase(t, settings.keywordCase)
        local key = t:lower()
        if #t > 1 and #t < 80 and not seen[key] then
            seen[key] = true
            table.insert(keywords, t)
        end
        if #keywords >= settings.maxKeywords then break end
    end
    return keywords
end

-- ── curl helper ──────────────────────────────────────────────────────────
-- Writes a curl config file with headers/URL/method, then invokes curl with
-- only controlled temp file paths on the command line. This prevents shell
-- injection and keeps sensitive values (API keys) out of the process list.
local function writeCurlConfig(cfgPath, url, headers, timeoutSecs)
    local fh = io.open(cfgPath, "w")
    if not fh then return false end
    fh:write("-s\n")
    fh:write("-X POST\n")
    fh:write(string.format('url = "%s"\n', url))
    for _, h in ipairs(headers) do
        fh:write(string.format('header = "%s"\n', h))
    end
    fh:write(string.format("max-time = %d\n", timeoutSecs))
    fh:close()
    return true
end

local function curlPost(cfgPath, tmpIn, tmpOut, imgSize, timeoutSecs)
    local curlCmd = string.format(
        "curl -K %s -d @%s -o %s",
        shellEscape(cfgPath), shellEscape(tmpIn), shellEscape(tmpOut)
    )
    local exitCode = LrTasks.execute(curlCmd)

    local result = nil
    local rf = io.open(tmpOut, "r")
    if rf then result = rf:read("*all"); rf:close() end

    safeDelete(cfgPath)
    safeDelete(tmpIn)
    safeDelete(tmpOut)

    if exitCode ~= 0 or not result or result == "" then
        local detail = string.format(
            "curl exit %d. Image: %.1f MB. Timeout: %ds.",
            exitCode, imgSize / 1048576, timeoutSecs
        )
        if exitCode == 28 then
            detail = detail .. " Timeout — increase timeout or use a faster model."
        elseif exitCode == 7 then
            detail = detail .. " Could not connect."
        end
        return nil, detail
    end

    return result, nil
end

-- ── Ollama provider ──────────────────────────────────────────────────────
local function queryOllama(img, prompt, settings, ts)
    local encodeOk, body = pcall(json.encode, {
        model    = settings.model,
        stream   = false,
        messages = {{
            role    = "user",
            content = prompt,
            images  = { img.base64 },
        }}
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local tmpCfg = TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not writeCurlConfig(tmpCfg, settings.ollamaUrl .. "/api/chat",
            { "Content-Type: application/json" }, settings.timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, settings.timeoutSecs)
    if not result then return nil, err end

    local ok, decoded = pcall(function() return json.decode(result) end)
    if not ok or type(decoded) ~= "table" then
        return nil, "Could not parse Ollama response: " .. tostring(result):sub(1, 200)
    end
    if not (decoded.message and decoded.message.content) then
        return nil, "Unexpected Ollama response: " .. tostring(result):sub(1, 200)
    end

    return decoded.message.content, nil
end

-- ── Claude API provider ──────────────────────────────────────────────────
local function queryClaude(img, prompt, settings, ts)
    local encodeOk, body = pcall(json.encode, {
        model      = settings.claudeModel,
        max_tokens = 1024,
        messages   = {{
            role    = "user",
            content = {
                {
                    type   = "image",
                    source = {
                        type       = "base64",
                        media_type = "image/jpeg",  -- always JPEG from LrExportSession
                        data       = img.base64,
                    },
                },
                {
                    type = "text",
                    text = prompt,
                },
            },
        }}
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local apiKey = settings.claudeApiKey:gsub("%s+", "")

    local tmpCfg = TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not writeCurlConfig(tmpCfg, "https://api.anthropic.com/v1/messages", {
        "x-api-key: " .. apiKey,
        "anthropic-version: 2023-06-01",
        "content-type: application/json",
    }, settings.timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, settings.timeoutSecs)
    if not result then return nil, err end

    local ok, decoded = pcall(function() return json.decode(result) end)
    if not ok or type(decoded) ~= "table" then
        return nil, "Could not parse Claude response: " .. tostring(result):sub(1, 200)
    end

    if decoded.error then
        return nil, "Claude API error: " .. (decoded.error.message or "Unknown")
    end

    if decoded.content and type(decoded.content) == "table" then
        for _, block in ipairs(decoded.content) do
            if block.type == "text" and block.text then
                return block.text, nil
            end
        end
    end

    return nil, "Unexpected Claude response: " .. tostring(result):sub(1, 200)
end

-- ── Query router ─────────────────────────────────────────────────────────
local function queryModel(photo, folderHint, gpsInfo, settings, imageIndex)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000)) .. "_" .. tostring(imageIndex or 0)

    local img, err = prepareImage(photo, ts, settings.provider)
    if not img then return nil, err end

    local prompt = buildPrompt(settings, folderHint, gpsInfo)

    local raw
    if settings.provider == "claude" then
        raw, err = queryClaude(img, prompt, settings, ts)
    else
        raw, err = queryOllama(img, prompt, settings, ts)
    end

    if not raw then return nil, nil, err end

    local keywords = parseKeywords(raw, settings)
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

        -- Validate Claude API key
        if SETTINGS.provider == "claude" and (SETTINGS.claudeApiKey == nil or SETTINGS.claudeApiKey == "") then
            LrDialogs.message("AI Keywords",
                "Claude API selected but no API key configured.\n\nOpen Settings and enter your Anthropic API key.", "warning")
            return
        end

        -- Split into processable vs unsupported
        local toProcess, skipped = {}, {}
        for _, photo in ipairs(targetPhotos) do
            local path = photo:getRawMetadata('path')
            if SUPPORTED_EXTS[getExt(path)] then
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
            LrTasks.execute("rm -f /tmp/ai_kw_req_* /tmp/ai_kw_resp_* /tmp/ai_kw_cfg_* 2>/dev/null")
        end)

        -- Initialize logger
        local log = setmetatable({}, { __index = Logger })
        log:init(SETTINGS)

        -- Parse folder aliases once (not per-image)
        local folderAliases = parseAliases(SETTINGS.folderAliases)

        local providerLabel = SETTINGS.provider == "claude" and "Claude API" or "Ollama"
        local progress = LrProgressScope({
            title           = "AI Keywords (" .. providerLabel .. ")",
            functionContext = context,
        })

        local successCount   = 0
        local skippedKwCount = 0
        local errorLog       = {}

        for i, photo in ipairs(toProcess) do
            if progress:isCanceled() then
                log:log("Run canceled by user at image " .. i)
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
                    log:logImage(filename, "skipped", "already has " .. #existingKw .. " keywords")
                end
            end

            if not shouldSkip then

            -- Build folder hint
            local folderHint = nil
            if SETTINGS.useFolderContext then
                local parts = getFolderContext(photo, catalog, folderAliases)
                if #parts > 0 then
                    folderHint = table.concat(parts, " > ")
                end
            end

            -- Extract GPS coordinates if available
            local gpsInfo = nil
            local gps = photo:getRawMetadata('gps')
            if gps and gps.latitude and gps.longitude then
                gpsInfo = { latitude = gps.latitude, longitude = gps.longitude }
            end

            -- Query AI model (render + send + parse)
            local queryStart = LrDate.currentTime()
            local keywords, rawResponse, err = queryModel(photo, folderHint, gpsInfo, SETTINGS, i)
            local queryElapsed = LrDate.currentTime() - queryStart

            -- Log prompt, raw response, and timing
            log:log(string.format("  Prompt: %s", buildPrompt(SETTINGS, folderHint, gpsInfo):sub(1, 300)))
            if rawResponse then
                log:log(string.format("  Raw response: %s", rawResponse:sub(1, 500)))
            end
            log:log(string.format("  Query time: %.1fs", queryElapsed))

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
                    log:logImage(filename, "success", table.concat(keywords, ", "))
                else
                    table.insert(errorLog, "- " .. filename .. "\n  Write error: " .. tostring(writeErr))
                    log:logImage(filename, "error", "Write failed: " .. tostring(writeErr))
                end
            else
                table.insert(errorLog, "- " .. filename .. "\n  " .. (err or "unknown error"))
                log:logImage(filename, "error", err or "unknown error")
            end

            end -- if not shouldSkip

            LrTasks.sleep(0.05)
        end

        progress:done()

        -- Finish log
        log:finish(successCount, #errorLog, skippedKwCount)

        -- Build completion message
        local lines = { string.format("%d photo(s) keyworded via %s", successCount, providerLabel) }
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
