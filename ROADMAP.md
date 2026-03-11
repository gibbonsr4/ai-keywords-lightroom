# AI Keywords — Roadmap & Future Development

## Current State (v3.0.0)
- LrExportSession-based image rendering (RAW, HEIC, all formats)
- Claude API (Haiku, Sonnet) and Ollama (6 vision models) providers
- GPS coordinate context from EXIF
- Folder context with alias expansion
- Parent keyword hierarchy
- Per-run logging
- macOS only

---

## Known Issues (Code Review)
See CLAUDE.md for the full 27-item list. Top priorities:

1. **README is outdated** — references sips, says RAW not supported, old folder name
2. **Logger writes all at end** — crash mid-run = zero log. Need incremental writes
3. **withWriteAccessDo return not fully checked** — should verify `== "executed"`, not just not-error
4. **GPS/prompt text leaking into keywords** — parser should filter coordinate patterns and markdown
5. **Aliases parsed per-image** — should parse once at run start
6. **Batch LrExportSession renders** — biggest performance win, render 10 at a time
7. **Timing and raw response in logs** — essential for debugging

---

## Feature Roadmap

### Phase 1: Reliability & Polish (Next)
- [ ] Fix all 27 code review items from CLAUDE.md
- [ ] Bump version to 3.0.0
- [ ] Comprehensive README rewrite
- [ ] Test LrExportSession with RAW (CR2, NEF, ARW), HEIC, TIFF
- [ ] Test logging end-to-end
- [ ] Test folder aliases

### Phase 2: Metadata Expansion
**Titles & Descriptions** — LrGeniusAI's biggest advantage over us. Relatively easy to add since we're already sending the image.

- [ ] Generate IPTC title (short, descriptive)
- [ ] Generate IPTC caption/description (1-2 sentences)
- [ ] Generate alt text (accessibility-focused)
- [ ] Settings toggle for which metadata fields to populate
- [ ] Separate prompt or structured response for titles/descriptions vs keywords
- [ ] Write to `photo:setRawMetadata('title', ...)` and `photo:setRawMetadata('caption', ...)`

### Phase 3: Keyword Quality & Consistency

#### Controlled Vocabulary / Keyword Matching
Post-processing step that maps model output to a curated vocabulary.

- [ ] **Vocabulary file format** — simple text file, one keyword per line, with optional synonyms:
  ```
  fortress: colonial fortress, fort, fortification, citadel, stronghold
  sugarcane: sugar cane, cane field, sugarcane field
  ocean: sea, atlantic ocean, pacific ocean, caribbean sea
  ```
- [ ] **Import from LR keyword export** — LR can export its keyword list as a tab-indented text file. The plugin could read this and use it as the vocabulary.
- [ ] **Matching modes:**
  - Strict: only vocabulary terms pass through, unmatched keywords dropped
  - Permissive: vocabulary terms preferred, unmatched keywords pass through as-is
  - Suggest: unmatched keywords flagged in log for review
- [ ] **Settings UI:** vocabulary file path + mode selector
- [ ] **mapToVocabulary() function** — runs between parseKeywords() and applyKeywords()

#### Keyword Best Practices Integration
- [ ] **Atomic keywords** — prompt instruction to prefer single-concept keywords ("fortress" not "stone fortress")
- [ ] **Singular form** — prompt instruction or parser normalization
- [ ] **Synonym support** — use LR's createKeyword synonym parameter instead of creating separate keywords (e.g. "rainforest" with synonym "jungle" instead of two keywords)
- [ ] **Dedup across runs** — check if photo already has a keyword before adding
- [ ] **Searchability filter** — "only include keywords you would realistically search for"

#### Available Keyword Lists (External Resources)
- **Open Source Lightroom Keyword List Project** — free, community-maintained, hierarchical, LR-compatible
  - Best starting point for a built-in vocabulary
- **Photo Keywords** — paid, some free specialist lists
  - https://www.photokeywords.com
- **Controlled Vocabulary Keyword Catalog** — paid ($70), most comprehensive
  - https://www.controlledvocabulary.com
- **Ben Willmore Digital Mastery** — paid, includes eBook
- **IPTC Subject NewsCodes** — free, news/editorial focused
  - http://cv.iptc.org/newscodes/subjectcode
- **Library of Congress Thesaurus for Graphic Materials** — free, 7000+ terms for visual content
  - https://www.loc.gov/librarians/controlled-vocabularies/

### Phase 4: Hierarchical Keywords
Generate categorized keywords that create proper LR keyword hierarchies.

- [ ] **Category-based generation** — ask model to categorize keywords:
  ```
  Location: Puerto Rico, San Juan
  Architecture: fortress, sentry box, turret
  Environment: ocean, coast, tropical
  ```
- [ ] **Map to LR hierarchy** — create parent categories automatically:
  ```
  Places > Puerto Rico > San Juan
  Architecture > fortress
  Architecture > sentry box
  ```
- [ ] **Import existing hierarchy** — read user's existing keyword tree and map new keywords into it
- [ ] **Smart nesting** — detect location keywords and auto-nest (country > city > landmark)

### Phase 5: Additional Providers
- [ ] **Google Gemini** — very competitive vision + pricing, large context window
  - Gemini 2.0 Flash is fast and cheap
  - API pattern similar to Claude
- [ ] **OpenAI GPT-4o / GPT-4o-mini** — widely used, good vision
- [ ] **LM Studio** — LrGeniusAI supports this, local alternative to Ollama
- [ ] **Provider comparison tool** — run same image through multiple providers, compare results

### Phase 6: Semantic Search (Major Feature)
LrGeniusAI's headline feature. Requires fundamentally different architecture.

- [ ] **Backend server** — Python/Node process running alongside LR
- [ ] **Image embeddings** — generate CLIP/OpenCLIP embeddings for each photo
- [ ] **Vector database** — store embeddings locally (SQLite + vector extension, or dedicated vector DB)
- [ ] **Natural language search** — "happy dog on beach" finds matching photos
- [ ] **LR integration** — search results shown in LR via Smart Collection or custom panel
- [ ] **Incremental indexing** — only process new/changed photos

This is essentially a separate product that shares the LR plugin layer. Significant development effort.

### Phase 7: Batch API & Cost Optimization
- [ ] **Claude Batch API** — submit all images in one request, 50% cost discount
  - Async processing: submit → poll → collect results
  - Requires job management (what if LR closes mid-batch?)
  - Significant architecture change but big cost savings for large libraries
- [ ] **Token usage tracking** — estimate and display cost per run
- [ ] **Provider cost comparison** — show estimated cost before starting batch

### Phase 8: Platform & Distribution
- [ ] **Windows support** — replace macOS-specific commands (osascript, open -a)
  - curl works on Windows too
  - LrExportSession is cross-platform
  - Folder picker and Ollama start need platform checks
- [ ] **GitHub repo** — public repository for distribution
- [ ] **Releases** — versioned .zip downloads
- [ ] **Adobe Exchange** — (difficult publishing process per community reports)
- [ ] **Auto-update check** — notify user when new version available

---

## Prompt Engineering Notes

### What We Learned
- **Haiku works best with SHORT prompts** — over-prompting causes hallucinations
- **Haiku confidently fabricates landmark names** — "Fort Jefferson" for any coastal fort
- **Sonnet handles reasoning chains** — can identify specific landmarks correctly
- **Qwen2.5-VL 7B is surprisingly good** — free, correctly ID'd sugarcane in DR
- **Location-first prompting** — telling the model to determine location before identifying specifics helps but doesn't prevent Haiku hallucinations
- **GPS coordinates work** — model uses them for location context but sometimes leaks them into keywords
- **Folder aliases are effective** — "DR" → "Dominican Republic" successfully influences keywords

### Current Default Prompt
```
Analyze this photo and return keywords ordered by prominence.
Only name specific landmarks, species, or crop varieties if you are highly confident.
If unsure, use a broader category instead (e.g. 'fortress' not a specific fort name,
'crop field' not a specific crop, 'songbird' not a specific species).
Wrong specifics are worse than correct generics.
For animals and plants you can confidently identify, use the most specific common name —
no scientific/Latin names, no taxonomic categories (mammal, primate, reptile, amphibian).
Include useful search synonyms where they differ meaningfully
(e.g. both 'jungle' and 'rainforest', both 'ocean' and 'sea')
but not near-duplicate descriptors (e.g. not both 'black fur' and 'dark fur').
Avoid generic filler: nature, outdoor, natural, beautiful, environment, scenic, wildlife,
colorful, vibrant, small, large, tiny.
```

### Auto-Appended by buildPrompt()
```
Return ONLY a comma-separated list of keywords — no sentences, no numbering, no explanation.
```

### Prompt Ideas to Test
- Per-model prompts (short for Haiku/Ollama, detailed for Sonnet)
- "Use singular form for all keywords"
- "Prefer single-concept keywords over compound phrases"
- "Only include keywords you would realistically search for to find this photo"
- "Do not include GPS coordinates, folder paths, or metadata in your keywords"

---

## Competitive Landscape

### LrGeniusAI (free, open source)
- **Pros:** Semantic search, titles/descriptions/alt text, 4 providers (ChatGPT, Gemini, Ollama, LM Studio), face workflows
- **Cons:** Complex setup (backend server required), no Claude support, no GPS context, no folder aliases
- **Architecture:** LR plugin + separate backend server + local database

### Excire Search (~$104)
- **Pros:** Deep LR integration, face recognition, text-prompt search, AI culling, in-house AI model
- **Cons:** Proprietary, no cloud AI option, can't leverage latest models
- **Architecture:** Native LR plugin with bundled AI model

### Peakto
- **Pros:** Multi-app host (LR Classic, Apple Photos, etc.), automatic keywording
- **Cons:** Separate application, not a LR plugin

### Our Advantages
1. Claude API — best vision model accuracy
2. GPS + folder context — location-aware keywording
3. Simple install — no backend server, no database
4. Fully customizable prompts
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
