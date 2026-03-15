# AI Keywords — Lightroom Classic Plugin

## Project Overview
A macOS-only Lightroom Classic plugin that generates and applies searchable keywords to photos using local Ollama vision models or cloud APIs (Claude, OpenAI, Gemini). Built in Lua using the LR SDK.

## File Structure
- `Info.lua` — LR plugin manifest, menu items, version
- `Prefs.lua` — Preference defaults and getPrefs() loader. Pure data, no UI, no side effects. Safe to dofile().
- `AIEngine.lua` — Shared AI inference engine. Image rendering, API calls (Ollama + Claude + OpenAI + Gemini), keyword parsing, Ollama status checks. Used by GenerateKeywords.lua, CompareModels.lua, and Config.lua.
- `Config.lua` — Settings dialog UI. Invoked via Library > Plugin Extras > Settings…
- `GenerateKeywords.lua` — Main keyword generation logic. Invoked via Library > Plugin Extras > Generate AI Keywords.
- `CompareModels.lua` — Model comparison tool. Runs 2–5 models on one photo without saving keywords. Invoked via Library > Plugin Extras > Compare Models.
- `dkjson.lua` — Bundled JSON library (LR SDK has no built-in JSON)
- `README.md` — User documentation

## Architecture
1. User selects photos in LR Library, runs "Generate AI Keywords"
2. For each photo: render temp JPEG via LrExportSession → base64 encode → send to AI provider (Ollama/Claude/OpenAI/Gemini) via curl → parse comma-separated keywords → write to LR catalog
3. Folder context (folder path hints, GPS coordinates) prepended to prompt for location awareness
4. Folder aliases expand abbreviations (e.g. DR → Dominican Republic)
5. Parent keyword option nests all AI keywords under a container keyword

## Key Technical Decisions
- **LrExportSession** replaces sips for image rendering — handles all formats LR can open (RAW, HEIC, etc.)
- **curl via LrTasks.execute()** for HTTP — LrHttp was unreliable for localhost connections
- **LrTasks.pcall** (not standard pcall) wraps catalog writes — Lua 5.1 can't yield across C boundaries
- **withWriteAccessDo { timeout = 10 }** for catalog lock contention
- **CSV output format** from models (not JSON) — battle-tested, simpler prompts, better for Haiku
- **`f:tab_view`** for provider selection — each provider in its own tab, `value` bound to provider prop
- **GPS toggle** (`useGPS`) — allows users to disable GPS coordinate context for privacy

## Provider Details

### Ollama
- Endpoint: `{url}/api/chat`
- Body: `{ model, stream: false, messages: [{ role: "user", content: prompt, images: [base64] }] }`
- Response: `decoded.message.content`

### Claude API
- Endpoint: `https://api.anthropic.com/v1/messages`
- Headers: x-api-key, anthropic-version: 2023-06-01
- Body: `{ model, max_tokens: 1024, messages: [{ role: "user", content: [{ type: "image", source: { type: "base64", media_type: "image/jpeg", data } }, { type: "text", text: prompt }] }] }`
- Models: claude-haiku-4-5-20251001 (~$0.002/image), claude-sonnet-4-6 (~$0.007/image)

### OpenAI API
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Headers: Authorization: Bearer {key}, Content-Type: application/json
- Body: `{ model, max_tokens: 1024, messages: [{ role: "user", content: [{ type: "image_url", image_url: { url: "data:image/jpeg;base64,{data}" } }, { type: "text", text: prompt }] }] }`
- Models: gpt-4o-mini (~$0.001/image), gpt-4o (~$0.005/image)

### Gemini API
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}`
- Headers: Content-Type: application/json (API key in URL query param)
- Body: `{ contents: [{ parts: [{ inlineData: { mimeType: "image/jpeg", data: base64 } }, { text: prompt }] }] }`
- Models: gemini-2.0-flash (~$0.0005/image), gemini-2.5-flash (~$0.001/image), gemini-2.5-pro (~$0.005/image)

## Image Rendering
- Cloud providers (Claude, OpenAI, Gemini): 1568px long edge
- Ollama: 1024px long edge
- JPEG quality: 70%, sRGB, minimal metadata, no sharpening/watermark
- Progressive fallback for cloud providers if image exceeds 3.75MB raw: 1568 → 1024 → 768
- Minimum dimension check: 200px short edge

## Prompt Engineering Notes
- Haiku works best with SHORT, minimal prompts. Over-prompting causes hallucinations.
- Haiku confidently hallucinates specific landmark names (e.g. "Fort Jefferson" for any coastal fort)
- Sonnet handles complex reasoning chains and gets specific IDs right
- Qwen2.5-VL 7B (local) is surprisingly good — correctly ID'd sugarcane in Dominican Republic
- The prompt is assembled by buildPrompt() in this order: [GPS/folder context] + [BASE_PROMPT] + [user custom instructions] + [output format]
- BASE_PROMPT is hardcoded in AIEngine.lua — contains keywording best practices, not user-editable
- settings.prompt contains optional user custom instructions (e.g. "Focus on architecture") — can be empty
- GPS coordinates and folder context are prepended when available

### Keyword Style (based on stock photography best practices)
- **Atomic keywords** — single-concept preferred; multi-word only for established terms (golden hour, copy space, fire pit) and proper nouns (New York, Baja California)
- **Singular nouns** — "boat" not "boats"; search engines handle inflection
- **Gerund verbs** — "running" not "run"
- **Lowercase** — default keywordCase changed to "lowercase"; proper nouns lowercased by parser
- **Include** — subjects, setting, dominant colors, mood/emotion, composition terms (copy space, aerial view, silhouette), people descriptors (age range, gender, activity)
- **Filler exclusion** — expanded list includes: nature, outdoor, natural, beautiful, environment, scenic, wildlife, colorful, vibrant, small, large, tiny, photo, image, picture, stock, background

## Known Issues / Code Review Findings

### Resolved in v3.0.0
1. ~~Temp file cleanup~~ — Sweep `/tmp/ai_kw_*` at start of each run.
2. ~~writeResult not fully checked~~ — Now checks `~= "executed"`.
3. ~~Logger writes all at end~~ — Now writes incrementally with flush.
4. ~~parseAliases per-image~~ — Parsed once at run start.
5. ~~No log folder validation~~ — Falls back to ~/Documents if folder doesn't exist.
7. ~~Base64 encoder slow~~ — Pre-built lookup table.
9. ~~fileSize opens file~~ — Uses LrFileUtils.fileAttributes().
12. ~~API key in plain text~~ — Backlogged (GitHub issue #1). API key no longer visible in process list.
13. ~~Validation after dialog closes~~ — actionBinding grays out Save when invalid.
14. ~~No Ollama URL validation~~ — Checked in actionBinding.
15. ~~"Settings Saved" dialog~~ — Removed.
16. ~~Logger crash-safety~~ — Incremental writes.
17. ~~No per-image timing~~ — Logged per image.
18. ~~Prompt not logged~~ — Full prompt logged per image.
19. ~~Raw response not logged~~ — Raw model output logged.
20. ~~Outdated README~~ — Comprehensive rewrite.
21. ~~Info.lua comment~~ — Fixed.
22. ~~Version 2.0.0~~ — Bumped to 3.0.0.
23. ~~LrPluginInfoUrl placeholder~~ — Points to GitHub repo.
24. ~~Config vs Prefs variable~~ — Renamed to Prefs.
25. ~~SUPPORTED_EXTS comment~~ — Documented why it exists.
27. ~~GPS/prompt leakage~~ — Parser filters coordinates, markdown, pure numbers.
- ~~Shell injection via shellEscape~~ — Curl uses config files, no user input in shell commands.
- ~~API key in process list~~ — API key written to temp config file, not command line.
- ~~Prefs.lua boolean defaults bug~~ — Explicit nil-check helpers for booleans.
- ~~json.encode unhandled~~ — Wrapped in pcall.
- ~~maxKeywords not in prompt~~ — Model told "Return up to N keywords".

### Remaining Issues
6. **LR_reimportExportedPhoto = false** may not prevent catalog import on all LR versions. (Monitoring — no reports of this occurring, temp files are deleted after reading.)

### Closed (not actual issues)
11. ~~All provider sections always visible~~ — Resolved with `f:tab_view` (SDK 1.3+). Each provider in its own tab.
8. ~~LrExportSession per image~~ — API calls (2-10s) dominate total time; render batching would save ~500ms. Not worth the complexity.
26. ~~curlPost temp file timing~~ — Not a race condition. LrTasks.execute() blocks until curl finishes; response is safely in memory before temp file deletion.

### Parent Keyword Inconsistency
- If keywords were previously created at root level (no parent), later enabling a parent keyword won't move them. LR SDK's `createKeyword` with `returnExisting=true` returns the existing root-level keyword instead of creating a new one under the parent.
- **Root cause:** LR SDK has no `moveKeyword()` API. Keywords cannot be relocated after creation.
- **Impact:** Only affects users who change the parent keyword setting after previous runs. Keywords still function in searches — only the hierarchy/organization is affected.
- **Workaround:** User must manually delete the stranded root-level keywords and re-run.

## Testing Notes
- Test LrExportSession rendering first — this is the biggest untested change from the sips refactor
- Test with RAW files (CR2, NEF, ARW) to verify LrExportSession handles them
- Test with HEIC files
- Test logging — enable, run a few photos, verify log file creation
- Test folder aliases with semicolon separator
- Test with photos that have GPS coordinates
- Verify temp files in /tmp are cleaned up after run

## Dev Environment
- macOS (Apple Silicon M5 MacBook Pro, 24GB)
- Lightroom Classic (current version)
- Ollama 0.7+ for Qwen2.5-VL models
- API keys required for cloud providers (Claude, OpenAI, Gemini)

## Roadmap & Future Development
See ROADMAP.md for high-level vision and GitHub Issues #1-#7 for task details.

## Competitive Context
Main competitor: LrGeniusAI (free, open source)
- They have: semantic search, titles/descriptions, 4 providers, backend server
- We have: 4 AI providers, GPS context, folder aliases, simpler install (no backend)
- See ROADMAP.md for full competitive analysis
