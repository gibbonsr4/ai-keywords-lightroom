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
6. **LR_reimportExportedPhoto = false** may not prevent catalog import on all LR versions. (Monitoring)
8. **LrExportSession per image** — Could batch renders. Deferred: API time is the bottleneck, not render time.
11. **Both provider sections always visible** — LR SDK limitation, documented.
26. **curlPost temp file timing** — Response is read into memory before deletion; minor debug concern only.

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
