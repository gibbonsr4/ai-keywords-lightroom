# AI Keywords — Roadmap

Detailed task breakdowns and progress are tracked in [GitHub Issues](https://github.com/gibbonsr4/ai-keywords-lightroom/issues).

| Priority | Feature | Issue | Summary |
|---|---|---|---|
| Next | Metadata expansion | [#2](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/2) | Generate IPTC titles, captions, and alt text |
| Next | Controlled vocabulary | [#3](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/3) | Map AI output to a curated vocabulary with LR synonym support |
| Future | Hierarchical keywords | [#4](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/4) | Categorized keywords that create proper LR keyword hierarchies |
| Future | Semantic search | [#5](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/5) | Natural language photo search |
| Future | Cost tracking | [#6](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/6) | Parse token usage from API responses and display per-run costs |
| Future | Windows support | [#7](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/7) | Replace macOS-specific commands |

## Shipped

| Feature | Issue | Shipped in | Summary |
|---|---|---|---|
| April 2026 model refresh | — | 1.2.0 | Gemini 3 family (Flash-Lite, Flash, Pro), Claude Opus 4.7, GPT-5.4 Nano/Mini, Gemma 4 (E4B, 31B), Qwen3-VL (4B, 8B), MiniCPM-V 4.5 |
| Prompt rewrite for landmark/species ID | — | 1.2.0 | Post-CONTEXT landmark directive with soft hedge; compact prompt profile for Haiku; base prompts restructured for prioritization and coverage |
| Provider code deduplication | — | 1.2.0 | `M.queryAPI(spec)` shared transport for all providers; HTTP status capture; temp-file hygiene |
| Compare Models UX | — | 1.2.0 | Per-image cost estimates, photo thumbnail, wrapping results layout, phase-aware progress caption |
| Parent-keyword stranding fix | — | 1.2.0 | `findOrCreateUnderParent` looks up children first, no more duplicated-at-root keywords |
| Security hardening | — | 1.2.0 | curl config URL escaping, strict Ollama healthcheck, prompt-injection fencing for folder/GPS metadata, GPS redacted from logs |
| Encrypted API keys | [#1](https://github.com/gibbonsr4/ai-keywords-lightroom/issues/1) | 1.1.0 | API keys stored in the macOS Keychain via LrPasswords, with auto-migration from the pre-1.1 plaintext pref on first read |
