# AI Keywords — Lightroom Classic Plugin

## Project Overview
A macOS-only Lightroom Classic plugin that generates and applies searchable keywords to photos using either local Ollama vision models or the Claude API. Built in Lua using the LR SDK.

## File Structure
- `Info.lua` — LR plugin manifest, menu items, version
- `Prefs.lua` — Preference defaults and getPrefs() loader. Pure data, no UI, no side effects. Safe to dofile().
- `Config.lua` — Settings dialog UI. Invoked via Library > Plugin Extras > Settings…
- `GenerateKeywords.lua` — Main processing logic. Invoked via Library > Plugin Extras > Generate AI Keywords.
- `dkjson.lua` — Bundled JSON library (LR SDK has no built-in JSON)
- `README.md` — User documentation

## Architecture
1. User selects photos in LR Library, runs "Generate AI Keywords"
2. For each photo: render temp JPEG via LrExportSession → base64 encode → send to Ollama or Claude API via curl → parse comma-separated keywords → write to LR catalog
3. Folder context (folder path hints, GPS coordinates) prepended to prompt for location awareness
4. Folder aliases expand abbreviations (e.g. DR → Dominican Republic)
5. Parent keyword option nests all AI keywords under a container keyword

## Key Technical Decisions
- **LrExportSession** replaces sips for image rendering — handles all formats LR can open (RAW, HEIC, etc.)
- **curl via LrTasks.execute()** for HTTP — LrHttp was unreliable for localhost connections
- **LrTasks.pcall** (not standard pcall) wraps catalog writes — Lua 5.1 can't yield across C boundaries
- **withWriteAccessDo { timeout = 10 }** for catalog lock contention
- **CSV output format** from models (not JSON) — battle-tested, simpler prompts, better for Haiku
- **Both provider sections always visible** in Settings — LR SDK visible binding doesn't collapse elements

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

## Image Rendering
- Claude: 1568px long edge (per Anthropic recommendation)
- Ollama: 1024px long edge
- JPEG quality: 70%, sRGB, minimal metadata, no sharpening/watermark
- Progressive fallback for Claude if image exceeds 3.75MB raw: 1568 → 1024 → 768
- Minimum dimension check: 200px short edge

## Prompt Engineering Notes
- Haiku works best with SHORT, minimal prompts. Over-prompting causes hallucinations.
- Haiku confidently hallucinates specific landmark names (e.g. "Fort Jefferson" for any coastal fort)
- Sonnet handles complex reasoning chains and gets specific IDs right
- Qwen2.5-VL 7B (local) is surprisingly good — correctly ID'd sugarcane in Dominican Republic
- The output format instruction ("Return ONLY a comma-separated list...") is auto-appended by buildPrompt(), separate from the user-editable prompt
- GPS coordinates and folder context are prepended when available

## Known Issues / Code Review Findings

### Reliability
1. **Rendered temp files may not always get cleaned up** — LrExportSession names output files itself. No cleanup sweep at end of run.
2. **withWriteAccessDo return value not fully handled** — Checks for "aborted" but not "queued". Should verify `writeResult == "executed"`.
3. **Logger writes all lines at end** — LR crash mid-run = zero log output. Should flush incrementally.
4. **parseAliases called per-image** — Should parse once at run start.
5. **No validation that log folder exists** — io.open fails silently.
6. **LR_reimportExportedPhoto = false** may not prevent catalog import on all LR versions.

### Efficiency
7. **Base64 encoder is slow** — Byte-by-byte string concat. Table-based approach would be faster.
8. **LrExportSession per image** — Creates new session per photo. Could batch renders (10 at a time).
9. **fileSize() opens file to seek** — LrFileUtils.fileAttributes() returns size without opening.
10. **Aliases parsed per-image** (duplicate of #4).

### Settings UI
11. **Both provider sections always visible** — LR SDK limitation, documented.
12. **API key in plain text** — LR SDK has LrPasswords for encrypted storage.
13. **Validation after dialog closes** — User must reopen Settings to fix. Should use actionBinding.
14. **No Ollama URL validation** — Could check on save.
15. **Unnecessary "Settings Saved" dialog** — Extra click for no reason.

### Logging
16. **Crash-safety** — Write incrementally (see #3).
17. **No render/API timing** — Per-image timing would help diagnose slow runs.
18. **Prompt not logged** — Full prompt with context would help debug keyword quality.
19. **Raw model response not logged** — Can't see what model returned vs what parser extracted.

### README / Documentation
20. **Multiple outdated references** — sips, RAW not supported, old folder name, masked API key.
21. **Info.lua comment says "OllamaKeywords"** — Should say AI Keywords.
22. **Version still 2.0.0** — Should be 3.0.0 for LrExportSession refactor.
23. **LrPluginInfoUrl is placeholder** — Points to https://github.com/.

### Code Quality
24. **Variable named Config holds Prefs module** — Confusing. Should be `local Prefs = ...`.
25. **SUPPORTED_EXTS redundant with LrExportSession** — Could try render and handle failure instead.
26. **curlPost deletes temp files before response is fully processed** — Should delete after all processing.
27. **GPS/prompt leakage into keywords** — Model sometimes includes coordinates or markdown in output. Parser should filter.

### Parent Keyword Inconsistency
- `createKeyword` with `returnExisting=true` finds existing root-level keywords and returns them instead of creating under the parent. Existing root keywords from earlier runs stay flat.
- No SDK API to move keywords. User must delete and re-create.
- Current workaround: tries `returnExisting=false` first, falls back to `true`. Still inconsistent.

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
- Claude API key required for cloud provider

## Roadmap & Future Development
See ROADMAP.md for the full feature roadmap including:
- Metadata expansion (titles, descriptions, alt text)
- Controlled vocabulary / keyword matching
- Hierarchical keyword generation
- Additional providers (Gemini, GPT-4o, LM Studio)
- Semantic search (major feature, separate architecture)
- Batch API support
- Keyword best practices integration

## Competitive Context
Main competitor: LrGeniusAI (free, open source)
- They have: semantic search, titles/descriptions, 4 providers, backend server
- We have: Claude API, GPS context, folder aliases, simpler install (no backend)
- See ROADMAP.md for full competitive analysis
