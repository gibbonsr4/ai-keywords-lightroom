--[[
  AIEngine.lua
  ─────────────────────────────────────────────────────────────────────────────
  Shared AI inference engine — image rendering, API calls, keyword parsing.
  Used by GenerateKeywords.lua, CompareModels.lua, and Config.lua.
  Stateless helper module — no UI, no dialog boxes.
--]]

local LrApplication     = import 'LrApplication'
local LrDate            = import 'LrDate'
local LrExportSession   = import 'LrExportSession'
local LrFileUtils       = import 'LrFileUtils'
local LrPathUtils       = import 'LrPathUtils'
local LrTasks           = import 'LrTasks'

local json = dofile(_PLUGIN.path .. '/dkjson.lua')

local M = {}

-- ── Constants ─────────────────────────────────────────────────────────────
-- LR SDK sandboxes os.getenv; try io.popen to read macOS per-user TMPDIR
do
    local dir = "/tmp"
    local ok, handle = pcall(io.popen, 'printf "%s" "$TMPDIR"')
    if ok and handle then
        local result = handle:read("*a")
        handle:close()
        if result and result ~= "" then
            dir = result:gsub("/$", "")
        end
    end
    M.TEMP_DIR = dir
end

-- Cloud API base64 image limit ~5MB. Base64 is ~4/3 of raw, so raw limit ~3.75MB.
M.CLOUD_MAX_RAW_BYTES = 3750000

-- JSON schema for structured output (cloud providers only)
M.KEYWORD_SCHEMA = {
    type = "object",
    properties = {
        keywords = {
            type  = "array",
            items = { type = "string" },
        },
    },
    required = { "keywords" },
    additionalProperties = false,
}

-- Minimum image dimension — images smaller than this won't produce useful keywords
M.MIN_IMAGE_DIMENSION = 200

-- SUPPORTED_EXTS is checked before LrExportSession to give clear error messages
-- for unsupported formats (e.g. PSD, AI) instead of opaque render failures.
M.SUPPORTED_EXTS = {
    jpg = true, jpeg = true, png = true,
    tif = true, tiff = true, webp = true,
    heic = true, heif = true,
    -- RAW formats — LrExportSession handles these natively
    cr2 = true, cr3 = true, nef = true, arw = true,
    raf = true, orf = true, rw2 = true, dng = true,
    pef = true, srw = true,
}

M.SKIP_FOLDERS = {
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

-- ── Recommended vision models for Ollama ──────────────────────────────────
-- Bundled list — ships with the plugin.  Users can check for updates via
-- the "Check for New Models" button in Settings (fetches models.json).
M.VISION_MODELS = {
    { value = "gemma3:4b",            label = "Gemma 3 4B",             info = "~3GB RAM  |  Popular, versatile vision model" },
    { value = "qwen2.5vl:3b",        label = "Qwen2.5-VL 3B",          info = "~2GB RAM  |  Fastest, good quality  |  Requires Ollama 0.7+" },
    { value = "minicpm-v",            label = "MiniCPM-V 8B",           info = "~5GB RAM  |  Fast, strong detail recognition" },
    { value = "qwen2.5vl:7b",        label = "Qwen2.5-VL 7B",          info = "~5GB RAM  |  Best local quality, accurate IDs  |  Requires Ollama 0.7+" },
    { value = "qwen3-vl:8b",         label = "Qwen3-VL 8B",            info = "~5GB RAM  |  Next-gen Qwen vision  |  Requires Ollama 0.7+" },
    { value = "gemma3:12b",          label = "Gemma 3 12B",            info = "~8GB RAM  |  High quality, strong all-rounder" },
    { value = "llama3.2-vision:11b",  label = "Llama 3.2 Vision 11B",   info = "~8GB RAM  |  Solid all-rounder" },
    { value = "moondream",            label = "Moondream 2",            info = "~1GB RAM  |  Tiny, fast, basic keywords only" },
}

-- ── Cloud provider models ───────────────────────────────────────────────
-- Shared by Config.lua (dropdowns) and CompareModels.lua (checkboxes).
M.CLAUDE_MODELS = {
    { value = "claude-haiku-4-5-20251001", label = "Claude Haiku 4.5",  cost = "~$0.002" },
    { value = "claude-sonnet-4-6",         label = "Claude Sonnet 4.6", cost = "~$0.007" },
}

M.OPENAI_MODELS = {
    { value = "gpt-5-mini-2025-08-07", label = "GPT-5 Mini",  cost = "~$0.001" },
    { value = "gpt-5.4",               label = "GPT-5.4",     cost = "~$0.007" },
}

M.GEMINI_MODELS = {
    { value = "gemini-2.5-flash-lite", label = "Gemini 2.5 Flash-Lite", cost = "~$0.0003" },
    { value = "gemini-2.5-flash",      label = "Gemini 2.5 Flash",      cost = "~$0.001" },
    { value = "gemini-2.5-pro",        label = "Gemini 2.5 Pro",        cost = "~$0.005" },
}

-- ── Remote model list URL (opt-in refresh via Settings) ──────────────
M.MODELS_JSON_URL =
    "https://raw.githubusercontent.com/gibbonsr4/ai-keywords-lightroom/main/models.json"

-- ── Base64 encoder ────────────────────────────────────────────────────────
-- Pre-built lookup table avoids repeated string.sub() calls per character.
local B64_CHAR = {}
do
    local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 0, 63 do B64_CHAR[i] = B64:sub(i + 1, i + 1) end
end

function M.base64Encode(data)
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
function M.readBinaryFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*all'); f:close(); return data
end

function M.fileSize(path)
    local attrs = LrFileUtils.fileAttributes(path)
    return (attrs and attrs.fileSize) or 0
end

function M.getExt(path)
    return (LrPathUtils.extension(path) or ''):lower()
end

function M.trim(s)
    return s:match("^%s*(.-)%s*$") or ''
end

function M.normalizeCase(s, mode)
    if mode == "lowercase" then return s:lower()
    elseif mode == "title_case" then
        return s:gsub("(%a)([%a']*)", function(a, b) return a:upper() .. b:lower() end)
    end
    return s
end

function M.safeDelete(path)
    pcall(function() LrFileUtils.delete(path) end)
end

-- POSIX-safe shell escaping: wrap in single quotes, escape internal single quotes.
-- This prevents injection via $(...), backticks, double-quote tricks, etc.
function M.shellEscape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- ── Ollama status helpers ─────────────────────────────────────────────────
function M.isOllamaInstalled()
    local appExists = LrFileUtils.exists("/Applications/Ollama.app")
    if appExists then return true end
    local exitCode = LrTasks.execute("which ollama >/dev/null 2>&1")
    return exitCode == 0
end

function M.getInstalledModels(ollamaUrl)
    local installed = {}
    local tmpCfg = M.TEMP_DIR .. "/ai_kw_tags_cfg.txt"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_tags.json"

    local cfh = io.open(tmpCfg, "w")
    if not cfh then return installed, false end
    cfh:write("-s\n")
    cfh:write(string.format('url = "%s/api/tags"\n', ollamaUrl))
    cfh:write("max-time = 5\n")
    cfh:close()

    local cmd = string.format("curl -K %s -o %s", M.shellEscape(tmpCfg), M.shellEscape(tmpOut))
    local exitCode = LrTasks.execute(cmd)

    if exitCode == 0 then
        local rf = io.open(tmpOut, "r")
        if rf then
            local response = rf:read("*all")
            rf:close()
            pcall(function() LrFileUtils.delete(tmpCfg) end)
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

    pcall(function() LrFileUtils.delete(tmpCfg) end)
    pcall(function() LrFileUtils.delete(tmpOut) end)
    return installed, false
end

function M.isModelInstalled(installed, modelValue)
    if installed[modelValue] then return true end
    -- Only fall back to base-name match when the modelValue has no explicit tag
    -- (e.g. "gemma3" matches "gemma3:latest"), NOT when it has a specific tag
    -- (e.g. "gemma3:12b" should NOT match "gemma3:4b")
    local base, tag = modelValue:match("^([^:]+):?(.*)")
    if base and (tag == nil or tag == "") and installed[base] then return true end
    return false
end

function M.fetchRemoteModels()
    local tmpCfg = M.TEMP_DIR .. "/ai_kw_models_cfg.txt"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_models.json"

    local cfh = io.open(tmpCfg, "w")
    if not cfh then return nil end
    cfh:write("-s\n")
    cfh:write(string.format('url = "%s"\n', M.MODELS_JSON_URL))
    cfh:write("max-time = 5\n")
    cfh:close()

    local cmd = string.format("curl -K %s -o %s", M.shellEscape(tmpCfg), M.shellEscape(tmpOut))
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
                if ok and type(data) == "table" and data.models and #data.models > 0 then
                    return data.models
                end
            end
        end
    end

    pcall(function() LrFileUtils.delete(tmpCfg) end)
    pcall(function() LrFileUtils.delete(tmpOut) end)
    return nil
end

-- ── Folder aliases ────────────────────────────────────────────────────────
-- Parses "DR=Dominican Republic; CR=Costa Rica" into a lookup table.
function M.parseAliases(aliasStr)
    local aliases = {}
    if not aliasStr or aliasStr == "" then return aliases end
    for entry in aliasStr:gmatch("[^;,\n\r]+") do
        local key, val = entry:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if key and val and key ~= "" and val ~= "" then
            aliases[key:lower()] = val
        end
    end
    return aliases
end

-- ── Folder context ────────────────────────────────────────────────────────
function M.getFolderContext(photo, catalog, aliases)
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
        if not M.SKIP_FOLDERS[lower] and not lower:match("^%d%d%d%d$") then
            local words = {}
            for word in part:gmatch("%S+") do
                local wordLower = word:lower()
                if wordLower:match("^%d+%-?%d*$") then
                    -- skip pure numeric/date tokens
                else
                    local replacement = aliases[wordLower]
                    table.insert(words, replacement or word)
                end
            end
            local expanded = table.concat(words, " ")
            expanded = M.trim(expanded)
            if expanded ~= "" then
                table.insert(parts, expanded)
            end
        end
    end
    return parts
end

-- ── Image rendering via LrExportSession ──────────────────────────────────
-- Uses Lightroom's own render pipeline. Handles every format in SUPPORTED_EXTS
-- (RAW, HEIC, TIFF, etc.) and respects Develop adjustments.
-- Always outputs sRGB JPEG with minimal metadata, no sharpening/watermark.
-- Returns (jpegPath, fileSize) or (nil, errorMsg).
function M.renderImage(photo, ts, maxDimension)
    local dim = maxDimension or 1024

    local exportSettings = {
        LR_export_destinationType       = 'specificFolder',
        LR_export_destinationPathPrefix = M.TEMP_DIR,
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
            local size = M.fileSize(pathOrMsg)
            if size > 0 then
                return pathOrMsg, size
            end
            M.safeDelete(pathOrMsg)
            return nil, "Render produced empty file"
        else
            return nil, "LR render failed: " .. tostring(pathOrMsg)
        end
    end

    return nil, "No renditions produced"
end

-- ── Prepare image for API ────────────────────────────────────────────────
-- Renders via LrExportSession at provider-appropriate size, reads,
-- base64-encodes. For cloud providers, retries at smaller dimensions if needed.
function M.prepareImage(photo, ts, provider)
    -- Check minimum dimensions
    local dims = photo:getRawMetadata('croppedDimensions')
    if dims then
        local minEdge = math.min(dims.width, dims.height)
        if minEdge < M.MIN_IMAGE_DIMENSION then
            return nil, string.format("Image too small (%dx%d). Minimum edge: %dpx.",
                dims.width, dims.height, M.MIN_IMAGE_DIMENSION)
        end
    end

    -- Provider-appropriate render size:
    -- Cloud: 1568px for best accuracy (Anthropic's recommendation, works well for all)
    -- Ollama: 1024px (local models work well at this size)
    local renderDim = (provider == "ollama") and 1024 or 1568

    local renderedPath, renderedSize = M.renderImage(photo, ts, renderDim)

    -- For cloud providers: retry at smaller sizes if too large for API
    if provider ~= "ollama" and renderedPath and renderedSize > M.CLOUD_MAX_RAW_BYTES then
        M.safeDelete(renderedPath)
        renderedPath, renderedSize = M.renderImage(photo, ts .. "_sm", 1024)
    end
    if provider ~= "ollama" and renderedPath and renderedSize > M.CLOUD_MAX_RAW_BYTES then
        M.safeDelete(renderedPath)
        renderedPath, renderedSize = M.renderImage(photo, ts .. "_xs", 768)
    end

    if not renderedPath then
        return nil, renderedSize  -- renderedSize is the error message when path is nil
    end

    local imageData = M.readBinaryFile(renderedPath)
    M.safeDelete(renderedPath)

    if not imageData then
        return nil, "Cannot read rendered file"
    end

    -- Final size check for cloud providers
    if provider ~= "ollama" and #imageData > M.CLOUD_MAX_RAW_BYTES then
        return nil, string.format(
            "Image too large for %s API (%.1f MB). Try exporting a smaller JPEG.",
            provider, #imageData / 1048576
        )
    end

    return {
        base64   = M.base64Encode(imageData),
        fileSize = #imageData,
    }, nil
end

-- ── Base keywording prompt (default — user can override in Settings > Advanced) ──
-- Contains keyword style rules, best practices, and guardrails based on
-- stock photography standards. User customization goes in settings.prompt.
M.BASE_PROMPT =
    "Analyze this photo and return keywords ordered by relevance. " ..
    "Use singular nouns (boat, tree, cloud) and gerund verbs (running, cooking, swimming). " ..
    "Prefer atomic, single-concept keywords. " ..
    "Use multi-word keywords only for established terms or proper nouns " ..
    "(e.g. golden hour, fire pit, copy space, New York). " ..
    "Do not combine adjective+noun when they work as separate keywords " ..
    "(e.g. 'boat' and 'anchor' not 'anchored boat', 'coast' and 'cliff' not 'coastal cliff'). " ..
    "Include: subjects, setting, dominant colors, mood or emotion when genuinely conveyed, " ..
    "and composition terms (e.g. copy space, close-up, aerial view, silhouette). " ..
    "For people: include age range, gender, and activity. " ..
    "Only name specific landmarks, species, or varieties if you are highly confident — " ..
    "wrong specifics are worse than correct generics. " ..
    "For animals and plants you can confidently identify, use the most specific common name — " ..
    "no scientific/Latin names, no taxonomic categories. " ..
    "Include useful search synonyms where they differ meaningfully " ..
    "(e.g. both 'jungle' and 'rainforest', both 'ocean' and 'sea') " ..
    "but not near-duplicate descriptors (e.g. not both 'black fur' and 'dark fur'). " ..
    "Avoid generic filler: nature, outdoor, natural, beautiful, environment, scenic, wildlife, " ..
    "colorful, vibrant, small, large, tiny, photo, image, picture, stock, background."

-- ── Build prompt with folder context and GPS ─────────────────────────────
function M.buildPrompt(settings, folderHint, gpsInfo)
    local basePrompt = settings.basePrompt
    if not basePrompt or basePrompt == "" then
        basePrompt = M.BASE_PROMPT
    end
    local prompt = basePrompt

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

    -- Append user custom instructions (if any)
    local custom = settings.prompt or ""
    if custom ~= "" then
        prompt = prompt .. " " .. custom
    end

    -- Append output format instruction
    prompt = prompt ..
        string.format(" Return up to %d keywords.", settings.maxKeywords) ..
        " Return ONLY a comma-separated list — no sentences, no numbering, no explanation." ..
        " Do not include GPS coordinates, folder paths, or metadata in your keywords."
    return prompt
end

-- ── Parse keywords from model output ─────────────────────────────────────
-- Tries JSON first (structured output from cloud providers), falls back to CSV.
function M.parseKeywords(raw, settings)
    -- Try JSON: {"keywords":["..."]} or bare ["..."]
    local ok, decoded = pcall(function() return json.decode(raw) end)
    if ok and type(decoded) == "table" then
        local arr = nil
        if type(decoded.keywords) == "table" then
            arr = decoded.keywords
        elseif #decoded > 0 and type(decoded[1]) == "string" then
            arr = decoded
        end
        if arr then
            local keywords = {}
            local seen = {}
            for _, kw in ipairs(arr) do
                local t = M.trim(tostring(kw))
                t = M.normalizeCase(t, settings.keywordCase)
                local key = t:lower()
                if #t > 1 and #t < 80 and not seen[key] then
                    seen[key] = true
                    table.insert(keywords, t)
                end
                if #keywords >= settings.maxKeywords then break end
            end
            if #keywords > 0 then return keywords end
        end
    end

    -- Fallback: CSV/newline parsing (Ollama and non-structured responses)
    local keywords = {}
    local seen = {}
    for kw in raw:gmatch("[^,\n]+") do
        local t = M.trim(kw)
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
        t = M.trim(t)

        -- Filter out GPS coordinates and pure numbers
        if t:match("^%-?%d+%.%d+$") then t = "" end                     -- single coordinate
        if t:match("^%-?%d+%.%d+%s*[,;]%s*%-?%d+%.%d+$") then t = "" end  -- coordinate pair
        if t:match("^%d+$") then t = "" end                              -- pure integer

        t = M.normalizeCase(t, settings.keywordCase)
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
-- Escape a value for use inside double quotes in a curl config file.
local function escapeCurlConfigValue(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"')
end

function M.writeCurlConfig(cfgPath, url, headers, timeoutSecs)
    local fh = io.open(cfgPath, "w")
    if not fh then return false end
    fh:write("-s\n")
    fh:write("-X POST\n")
    fh:write(string.format('url = "%s"\n', escapeCurlConfigValue(url)))
    for _, h in ipairs(headers) do
        fh:write(string.format('header = "%s"\n', escapeCurlConfigValue(h)))
    end
    fh:write(string.format("max-time = %d\n", timeoutSecs))
    fh:close()
    return true
end

function M.curlPost(cfgPath, tmpIn, tmpOut, imgSize, timeoutSecs)
    local curlCmd = string.format(
        "curl -K %s -d @%s -o %s",
        M.shellEscape(cfgPath), M.shellEscape(tmpIn), M.shellEscape(tmpOut)
    )
    local rawExit = LrTasks.execute(curlCmd)

    local result = nil
    local rf = io.open(tmpOut, "r")
    if rf then result = rf:read("*all"); rf:close() end

    M.safeDelete(cfgPath)
    M.safeDelete(tmpIn)
    M.safeDelete(tmpOut)

    if rawExit ~= 0 or not result or result == "" then
        -- macOS wait() status: exit code is in bits 15-8 (rawExit / 256),
        -- signal number (if killed) is in bits 6-0.
        local curlCode = math.floor(rawExit / 256)  -- actual curl exit code
        local signal   = rawExit % 128               -- signal if killed (0 = not killed)

        local detail
        if signal > 0 and curlCode == 0 then
            detail = string.format(
                "curl killed by signal %d. Image: %.1f MB. Timeout: %ds.",
                signal, imgSize / 1048576, timeoutSecs
            )
        else
            detail = string.format(
                "curl exit %d. Image: %.1f MB. Timeout: %ds.",
                curlCode, imgSize / 1048576, timeoutSecs
            )
            if curlCode == 28 then
                detail = detail .. " Timeout — increase timeout or use a faster model."
            elseif curlCode == 7 then
                detail = detail .. " Could not connect."
            end
        end
        return nil, detail
    end

    return result, nil
end

-- ── Ollama provider ──────────────────────────────────────────────────────
function M.queryOllama(img, prompt, modelName, ollamaUrl, timeoutSecs)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000))
    local encodeOk, body = pcall(json.encode, {
        model    = modelName,
        stream   = false,
        messages = {{
            role    = "user",
            content = prompt,
            images  = { img.base64 },
        }}
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local tmpCfg = M.TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = M.TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not M.writeCurlConfig(tmpCfg, ollamaUrl .. "/api/chat",
            { "Content-Type: application/json" }, timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = M.curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, timeoutSecs)
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
function M.queryClaude(img, prompt, claudeModel, apiKey, timeoutSecs)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000))
    local encodeOk, body = pcall(json.encode, {
        model      = claudeModel,
        max_tokens = 1024,
        messages   = {{
            role    = "user",
            content = {
                {
                    type   = "image",
                    source = {
                        type       = "base64",
                        media_type = "image/jpeg",
                        data       = img.base64,
                    },
                },
                {
                    type = "text",
                    text = prompt,
                },
            },
        }},
        output_config = {
            format = {
                type   = "json_schema",
                name   = "keywords",
                schema = M.KEYWORD_SCHEMA,
            },
        },
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local cleanKey = apiKey:gsub("%s+", "")

    local tmpCfg = M.TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = M.TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not M.writeCurlConfig(tmpCfg, "https://api.anthropic.com/v1/messages", {
        "x-api-key: " .. cleanKey,
        "anthropic-version: 2023-06-01",
        "content-type: application/json",
    }, timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = M.curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, timeoutSecs)
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

-- ── OpenAI API provider ────────────────────────────────────────────────
function M.queryOpenAI(img, prompt, openaiModel, apiKey, timeoutSecs)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000))
    local encodeOk, body = pcall(json.encode, {
        model                = openaiModel,
        max_completion_tokens = 1024,
        messages   = {{
            role    = "user",
            content = {
                {
                    type      = "image_url",
                    image_url = {
                        url = "data:image/jpeg;base64," .. img.base64,
                    },
                },
                {
                    type = "text",
                    text = prompt,
                },
            },
        }},
        response_format = {
            type        = "json_schema",
            json_schema = {
                name   = "keywords",
                strict = true,
                schema = M.KEYWORD_SCHEMA,
            },
        },
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local cleanKey = apiKey:gsub("%s+", "")

    local tmpCfg = M.TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = M.TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not M.writeCurlConfig(tmpCfg, "https://api.openai.com/v1/chat/completions", {
        "Authorization: Bearer " .. cleanKey,
        "Content-Type: application/json",
    }, timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = M.curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, timeoutSecs)
    if not result then return nil, err end

    local ok, decoded = pcall(function() return json.decode(result) end)
    if not ok or type(decoded) ~= "table" then
        return nil, "Could not parse OpenAI response: " .. tostring(result):sub(1, 200)
    end

    if decoded.error then
        return nil, "OpenAI API error: " .. (decoded.error.message or "Unknown")
    end

    if decoded.choices and type(decoded.choices) == "table" and decoded.choices[1] then
        local msg = decoded.choices[1].message
        if msg and msg.content then
            return msg.content, nil
        end
    end

    return nil, "Unexpected OpenAI response: " .. tostring(result):sub(1, 200)
end

-- ── Gemini API provider ────────────────────────────────────────────────
function M.queryGemini(img, prompt, geminiModel, apiKey, timeoutSecs)
    local ts = tostring(math.floor(LrDate.currentTime() * 1000))
    local encodeOk, body = pcall(json.encode, {
        contents = {{
            parts = {
                {
                    inlineData = {
                        mimeType = "image/jpeg",
                        data     = img.base64,
                    },
                },
                {
                    text = prompt,
                },
            },
        }},
        generationConfig = {
            responseMimeType = "application/json",
            responseSchema   = M.KEYWORD_SCHEMA,
        },
    })
    if not encodeOk then return nil, "JSON encode failed: " .. tostring(body) end

    local cleanKey = apiKey:gsub("%s+", "")
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        geminiModel, cleanKey
    )

    local tmpCfg = M.TEMP_DIR .. "/ai_kw_cfg_" .. ts .. ".txt"
    local tmpIn  = M.TEMP_DIR .. "/ai_kw_req_" .. ts .. ".json"
    local tmpOut = M.TEMP_DIR .. "/ai_kw_resp_" .. ts .. ".json"

    if not M.writeCurlConfig(tmpCfg, url, {
        "Content-Type: application/json",
    }, timeoutSecs) then
        return nil, "Could not write curl config file"
    end

    local fh = io.open(tmpIn, "w")
    if not fh then return nil, "Could not write temp file: " .. tmpIn end
    fh:write(body); fh:close()

    local result, err = M.curlPost(tmpCfg, tmpIn, tmpOut, img.fileSize, timeoutSecs)
    if not result then return nil, err end

    local ok, decoded = pcall(function() return json.decode(result) end)
    if not ok or type(decoded) ~= "table" then
        return nil, "Could not parse Gemini response: " .. tostring(result):sub(1, 200)
    end

    if decoded.error then
        return nil, "Gemini API error: " .. (decoded.error.message or "Unknown")
    end

    if decoded.candidates and type(decoded.candidates) == "table" and decoded.candidates[1] then
        local content = decoded.candidates[1].content
        if content and content.parts and type(content.parts) == "table" and content.parts[1] then
            local text = content.parts[1].text
            if text then
                return text, nil
            end
        end
    end

    return nil, "Unexpected Gemini response: " .. tostring(result):sub(1, 200)
end

return M
