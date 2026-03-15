# AI Keywords — Roadmap & Future Development

## Current State
- 4 AI providers: Ollama (local), Claude API, OpenAI, Google Gemini
- 8+ Ollama vision models with remote model list updates
- LrExportSession-based image rendering (RAW, HEIC, all formats)
- GPS coordinate context from EXIF
- Folder context with alias expansion
- Base prompt with keywording best practices (atomic, singular, gerund, filler exclusion)
- Separated base prompt + user custom instructions architecture
- Compare Models tool (cross-provider comparison)
- Parent keyword hierarchy
- Per-run logging
- macOS only

---

## Feature Roadmap

Detailed task breakdowns and progress are tracked in [GitHub Issues](https://github.com/gibbonsr4/ai-keywords-lightroom/issues).

| Priority | Feature | Issue | Summary |
|---|---|---|---|
| Next | Metadata expansion | [#2](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/2) | Generate IPTC titles, captions, and alt text — the image is already being sent to the AI |
| Next | Controlled vocabulary | [#3](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/3) | Map AI output to a curated vocabulary with LR synonym support |
| Future | Hierarchical keywords | [#4](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/4) | Categorized keywords that create proper LR keyword hierarchies |
| Future | Semantic search | [#5](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/5) | Natural language photo search (separate architecture — backend + vector DB) |
| Future | Cost tracking | [#6](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/6) | Parse token usage from API responses and display per-run costs |
| Future | Windows support | [#7](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/7) | Replace macOS-specific commands; core plugin is already cross-platform |
| Backlog | Encrypted API keys | [#1](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/1) | Use LrPasswords for secure API key storage |

---

## Prompt Engineering Notes

### What We Learned
- **Haiku works best with SHORT prompts** — over-prompting causes hallucinations
- **Haiku confidently fabricates landmark names** — "Fort Jefferson" for any coastal fort
- **Sonnet handles reasoning chains** — can identify specific landmarks correctly
- **Qwen2.5-VL 7B is surprisingly good** — free, correctly ID'd sugarcane in DR
- **GPS coordinates work** — model uses them for location context but sometimes leaks them into keywords
- **Folder aliases are effective** — "DR" → "Dominican Republic" successfully influences keywords

### Prompt Architecture
buildPrompt() assembles: `[GPS/folder context] + [BASE_PROMPT] + [user custom instructions] + [output format]`

- **BASE_PROMPT** — hardcoded in AIEngine.lua, not user-editable. Contains keywording best practices (atomic keywords, singular nouns, gerund verbs, composition terms, filler exclusion, etc.)
- **Custom instructions** — user-editable in Settings, optional. For domain-specific guidance (e.g. "Focus on architecture and design elements")
- **Output format** — auto-appended ("Return up to N keywords. Return ONLY a comma-separated list...")

### Prompt Ideas to Test
- Per-model prompts (short for Haiku/Ollama, detailed for Sonnet)

---

## Key Differentiators

1. 4 AI providers — Claude, OpenAI, Gemini, Ollama (local)
2. GPS + folder context — location-aware keywording
3. Simple install — no backend server, no database
4. Best-practice keywording prompt (atomic, singular, composition terms)
5. Folder aliases for catalog-specific context
6. Open source, Lua-only, easy to modify

---

## Model Comparison (Travel Photography)

| Model | Cost | Landmark ID | Species ID | Crop ID | Location | Speed |
|---|---|---|---|---|---|---|
| Claude Sonnet 4.6 | $0.007/img | Excellent | Excellent | Excellent | Excellent | ~2s |
| Claude Haiku 4.5 | $0.002/img | Halluccinates | Good | Poor (corn≠sugarcane) | Good | ~2s |
| Qwen2.5-VL 7B | Free | Good generic | Good | Good (got sugarcane) | Good w/context | ~5-10s |
| MiniCPM-V 8B | Free | Good generic | Decent | Untested | Good w/context | ~4-7s |

**Recommendation:** Sonnet for accuracy-critical runs, Qwen 7B for free batch processing, Haiku only when speed/cost is priority over accuracy.
