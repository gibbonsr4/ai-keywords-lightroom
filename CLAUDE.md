# AI Keywords — Lightroom Classic Plugin

## Project Overview
A macOS-only Lightroom Classic plugin that generates and applies searchable keywords to photos using local Ollama vision models or cloud APIs (Claude, OpenAI, Gemini). Built in Lua using the LR SDK.

## File Structure
- `Info.lua` — LR plugin manifest, menu items, version
- `Prefs.lua` — Preference defaults and getPrefs() loader. Pure data, no UI, no side effects. Safe to dofile() from any module.
- `AIEngine.lua` — Shared AI inference engine. Image rendering, API calls (Ollama + Claude + OpenAI + Gemini), keyword parsing, Ollama status checks, cloud model lists. Used by GenerateKeywords.lua, CompareModels.lua, and Config.lua.
- `Config.lua` — Settings dialog UI using `f:tab_view` for provider selection. Invoked via Library > Plugin Extras > Settings…
- `GenerateKeywords.lua` — Main keyword generation logic. Invoked via Library > Plugin Extras > Generate AI Keywords.
- `CompareModels.lua` — Model comparison tool. Runs 2–5 models on one photo without saving keywords. Invoked via Library > Plugin Extras > Compare Models.
- `dkjson.lua` — Bundled JSON library (LR SDK has no built-in JSON)
- `README.md` — User documentation
- `ROADMAP.md` — Feature roadmap referencing GitHub Issues

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
- **Cloud model lists** defined once in AIEngine.lua, shared by Config.lua (dropdowns) and CompareModels.lua (checkboxes)
- **Folder aliases** accept semicolons, commas, and newlines as delimiters

## Provider Details

### Ollama
- Endpoint: `{url}/api/chat`
- Body: `{ model, stream: false, messages: [{ role: "user", content: prompt, images: [base64] }] }`
- Response: `decoded.message.content`

### Claude API
- Endpoint: `https://api.anthropic.com/v1/messages`
- Headers: x-api-key, anthropic-version: 2023-06-01
- Body: `{ model, max_tokens: 1024, messages: [{ role: "user", content: [{ type: "image", source: { type: "base64", media_type: "image/jpeg", data } }, { type: "text", text: prompt }] }] }`
- Models: claude-haiku-4-5-20251001 (~$0.002/image), claude-sonnet-4-6 (~$0.007/image), claude-opus-4-7 (~$0.025/image)

### OpenAI API
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Headers: Authorization: Bearer {key}, Content-Type: application/json
- Body: `{ model, max_tokens: 1024, messages: [{ role: "user", content: [{ type: "image_url", image_url: { url: "data:image/jpeg;base64,{data}" } }, { type: "text", text: prompt }] }] }`
- Models: gpt-5.4-nano (~$0.0003/image), gpt-5.4-mini (~$0.001/image), gpt-5.4 (~$0.007/image)

### Gemini API
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}`
- Headers: Content-Type: application/json (API key in URL query param)
- Body: `{ contents: [{ parts: [{ inlineData: { mimeType: "image/jpeg", data: base64 } }, { text: prompt }] }] }`
- Models: gemini-3.1-flash-lite-preview (~$0.0002/image), gemini-3-flash-preview (~$0.0008/image), gemini-3.1-pro-preview (~$0.003/image)
- Note: Gemini 3 IDs use dots and a "-preview" suffix. gemini-3-pro-preview was shut down 2026-03-09 in favour of the 3.1 variant; expect similar promotions as other models graduate from preview.

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
- GPS coordinates work but models sometimes leak them into keywords (parser filters these)
- Folder aliases are effective — "DR" → "Dominican Republic" successfully influences keywords
- The prompt is assembled by buildPrompt() in this order: [BASE_PROMPT or BASE_PROMPT_COMPACT] + [fenced CONTEXT data block with GPS/folder, if any] + [user custom instructions, if any] + [output format block]
- Two base-prompt variants live in AIEngine.lua: BASE_PROMPT (standard) and BASE_PROMPT_COMPACT (short, for models that hallucinate under long prompts — Haiku)
- Each model registry row has `promptProfile = "standard"` or `"compact"`. getPromptProfile(settings) resolves it at runtime; getBasePromptForSettings() respects user override
- settings.basePrompt: empty string means "use the model's profile default" (plugin updates auto-apply)
- settings.prompt contains optional user custom instructions (e.g. "Focus on architecture") — appended after base prompt, empty by default
- Output-format block (count + "don't pad" + CSV hint for Ollama) is built per-run in buildPrompt since it depends on settings.maxKeywords and provider

### Keyword Style (based on stock photography best practices)
- **Atomic keywords** — single-concept preferred; multi-word only for established terms (golden hour, copy space, fire pit) and proper nouns (New York, Baja California)
- **Singular nouns** — "boat" not "boats"; search engines handle inflection
- **Gerund verbs** — "running" not "run"
- **Lowercase** — default keywordCase changed to "lowercase"; proper nouns lowercased by parser
- **Include** — subjects, setting, dominant colors, mood/emotion, composition terms (copy space, aerial view, silhouette), people descriptors (age range, gender, activity)
- **Filler exclusion** — expanded list includes: nature, outdoor, natural, beautiful, environment, scenic, wildlife, colorful, vibrant, small, large, tiny, photo, image, picture, stock, background
- **Named structures** — BASE_PROMPT's coverage line mentions "named structures or features when recognizable" so travel-photo landmarks are a first-class keyword target without burning tokens on a taxonomy list
- **Landmark directive lives at the TAIL of BASE_PROMPT** — LLM recency weighting matters here. Earlier rewrites put the landmark paragraph mid-prompt with three layers of anti-risk caveats and observed regression in specific-name ID (pushed models toward safe generics). Current design: one closing paragraph — "use all available evidence to identify the most specific place, landmark, hotel, resort, park, or named feature you can confidently support; if uncertain of a name, prefer omission over guessing"
- **No explicit landmark safety hedge** — QA showed even a single soft hedge ("if uncertain, prefer omission") was enough to suppress well-calibrated models like Gemini 3 Flash from emitting correct specific names, while doing nothing to restrain miscalibrated models like Haiku and small Gemma variants (they hallucinate confidently regardless). Directive is now pure two-step: "determine the location, then identify specific places/landmarks/etc. consistent with that location." Hallucination risk on weak models is treated as a model-capability issue, not a prompt issue
- **Don't pad** — output-format block tells the model to return fewer than maxKeywords if it doesn't have strong candidates, rather than reaching for weak/generic filler to hit the quota

### Model Comparison (Travel Photography)

Historical benchmarks, pre-April 2026 model refresh. Provided for context —
re-benchmark the current registry when convenient.

| Model | Cost | Landmark ID | Species ID | Crop ID | Location | Speed |
|---|---|---|---|---|---|---|
| Claude Sonnet 4.6 | $0.007/img | Excellent | Excellent | Excellent | Excellent | ~2s |
| Claude Haiku 4.5 | $0.002/img | Hallucinates | Good | Poor (corn≠sugarcane) | Good | ~2s |
| Qwen2.5-VL 7B | Free | Good generic | Good | Good (got sugarcane) | Good w/context | ~5-10s |
| MiniCPM-V 8B (v2.6) | Free | Good generic | Decent | Untested | Good w/context | ~4-7s |

**New models (April 2026 refresh) — unbenchmarked:**
- **Cloud additions:** Claude Opus 4.7 (~$0.025/img), GPT-5.4 / Mini / Nano (~$0.0003–0.007/img), Gemini 3 Pro / Flash / 3.1 Flash-Lite (~$0.0002–0.003/img).
- **Ollama refresh:** Qwen3-VL (4B/8B/30B MoE), Gemma 4 (E4B, 31B), MiniCPM-V 4.5 8B (built on Qwen3 + SigLIP2). Retired: Gemma 3 (superseded by Gemma 4), Qwen2.5-VL 3B, MiniCPM-V (v2.6), Llama 3.2 Vision 11B.
- **Default Ollama model** stays at `qwen2.5vl:7b` because it's the battle-tested option with documented real-world results (sugarcane/DR). Once Qwen3-VL 8B and Gemma 4 benchmarks land, revisit.

Broad heuristics until re-benchmarked:
- Sonnet 4.6 or Opus 4.7 for accuracy-critical runs.
- Haiku 4.5 only when speed/cost matters more than accuracy (compact prompt helps).
- GPT-5.4 Nano / Gemini 3.1 Flash-Lite are the new cheap-tier picks for high-volume batches.
- Qwen3-VL 30B MoE is the new "best local quality" target for 32GB+ Apple Silicon (MoE — only 3B params active).
- Qwen 7B (2.5) for free batch processing until Qwen3-VL 8B is benchmarked on the same test set.

## Known Issues

### Remaining
- **LR_reimportExportedPhoto = false** may not prevent catalog import on all LR versions. (Monitoring — no reports of this occurring, temp files are deleted after reading.)

### Parent Keyword Inconsistency
- If keywords were previously created at root level (no parent), later enabling a parent keyword won't move them. LR SDK's `createKeyword` with `returnExisting=true` returns the existing root-level keyword instead of creating a new one under the parent.
- **Root cause:** LR SDK has no `moveKeyword()` API. Keywords cannot be relocated after creation.
- **Impact:** Only affects users who change the parent keyword setting after previous runs. Keywords still function in searches — only the hierarchy/organization is affected.
- **Workaround:** User must manually delete the stranded root-level keywords and re-run.

## Dev Environment
- macOS (Apple Silicon)
- Lightroom Classic (current version)
- Ollama 0.7+ for Qwen2.5-VL models
- API keys required for cloud providers (Claude, OpenAI, Gemini)
