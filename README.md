# AI Keywords — Lightroom Classic Plugin

Automatically generates and applies searchable keywords to selected photos using **local Ollama vision models** or **cloud APIs** (Claude, OpenAI, Gemini). Your choice of free local processing or higher-quality cloud results.

**macOS only** — optimized for Apple Silicon.

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS (Apple Silicon recommended) | Uses `curl` for API calls |
| Lightroom Classic 6+ | |

**For Ollama (local):**
- [Ollama](https://ollama.com) installed and running
- A vision model (install from within Settings or via `ollama pull <model>`)

**For cloud providers (any or all):**
- **Claude API:** An Anthropic API key from [console.anthropic.com](https://console.anthropic.com)
- **OpenAI:** An API key from [platform.openai.com](https://platform.openai.com)
- **Gemini:** A Google AI API key from [aistudio.google.com](https://aistudio.google.com)

### Supported File Types
JPEG, PNG, TIFF, WEBP, HEIC/HEIF, and all RAW formats supported by Lightroom (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF, SRW).

Images are rendered via Lightroom's own export pipeline, so any format Lightroom can open will work.

---

## Installation

1. Place the `AIKeywords.lrplugin` folder somewhere permanent (e.g. `~/Documents/LR Plugins/`)
2. In Lightroom Classic: **File → Plug-in Manager → Add**
3. Navigate to and select the `AIKeywords.lrplugin` folder
4. Click **Done**

---

## Usage

1. Open Settings and choose your provider (Ollama, Claude, OpenAI, or Gemini)
2. In Lightroom Library, select one or more photos
3. **Library → Plug-in Extras → Generate AI Keywords — Selected Photos**
4. Wait for the progress bar to complete
5. Keywords appear in the **Keywording** panel

### Compare Models

Want to find the best model for your photos? Use the comparison tool:

1. Select **one** photo in the Library
2. **Library → Plug-in Extras → Compare Models — Selected Photo**
3. Check 2–5 models to compare (Ollama, Claude, OpenAI, and/or Gemini models)
4. Optionally override the prompt for this comparison
5. View side-by-side results with timing, keyword counts, and overlap analysis

No keywords are saved — this is a preview-only tool for evaluating model quality and testing prompts.

---

## Configuration

Open **Library → Plug-in Extras → Settings…** to configure. The Save button is disabled until all required fields are valid.

### Provider

Choose between **Ollama (local)**, **Claude API**, **OpenAI**, and **Gemini** via tabs.

### Ollama Settings

The plugin checks Ollama's status when you open Settings and shows whether it's installed, running, and which models are available. You can:

- **Start Ollama** directly from Settings (or open the download page if not installed)
- **Choose a model** from the dropdown with install status indicators (✓ = installed)
- **Install models** by clicking "Install Model" (opens Terminal so you can watch `ollama pull` progress)

<a id="ollama-models"></a>

Recommended models, smallest to largest:

| Model | RAM | Best For |
|---|---|---|
| Moondream 2 | ~1GB | Tiny fallback, basic keywords only |
| Qwen3-VL 4B | ~3GB | Fastest decent tier, next-gen Qwen |
| Qwen2.5-VL 7B | ~5GB | Battle-tested, accurate IDs |
| Gemma 4 E4B | ~6GB | Mid-tier default, multimodal out of the box |
| MiniCPM-V 4.5 8B | ~6GB | Strong detail/OCR, built on Qwen3+SigLIP2 |
| Qwen3-VL 8B | ~6GB | Main quality tier, next-gen Qwen |
| Gemma 4 31B | ~14GB | High-quality dense, strong all-rounder |
| Qwen3-VL 30B MoE | ~20GB | Top-tier local, 32GB+ Apple Silicon |

> **Note:** Qwen2.5-VL and Qwen3-VL models require Ollama 0.7.0 or newer. Gemma 4 and MiniCPM-V 4.5 need a recent Ollama build.
>
> Ollama's MLX backend (preview) gives Apple Silicon a significant speedup — enable it in Ollama's settings if available.
>
> Click the **Check for New Models** button in Settings to pull the latest recommended list from GitHub — no plugin update needed. You can also uninstall models directly from Settings to free disk space.

### Claude API Settings

| Setting | Notes |
|---|---|
| API Key | Your Anthropic API key |
| Model | Haiku 4.5 (~$0.002/image), Sonnet 4.6 (~$0.007/image), or Opus 4.7 (~$0.025/image) |

### OpenAI Settings

| Setting | Notes |
|---|---|
| API Key | Your OpenAI API key |
| Model | GPT-5.4 Nano (~$0.0003/image), GPT-5.4 Mini (~$0.001/image), or GPT-5.4 (~$0.007/image) |

### Gemini Settings

| Setting | Notes |
|---|---|
| API Key | Your Google AI API key |
| Model | Gemini 3.1 Flash-Lite (~$0.0002/image), Gemini 3 Flash (~$0.0008/image), or Gemini 3.1 Pro (~$0.003/image) — all preview-tier as of April 2026 |

### Keyword Settings

| Setting | Default | Notes |
|---|---|---|
| Max keywords | 20 | Per photo, 1–50. Also communicated to the model in the prompt. |
| Keyword case | lowercase | Options: As returned, lowercase, Title Case |
| Timeout | 90 seconds | Per image |
| Parent keyword | (blank) | See below |
| Skip keyworded | Off | Skip photos that already have keywords |

### Parent Keyword (Keyword Hierarchy)

By default, keywords are created at the root level of your catalog's keyword list (flat). If you enter a parent keyword (e.g. "AI Generated"), all AI-created keywords will be nested under that parent in the Keyword List panel.

This is useful for:
- Seeing at a glance which keywords came from AI vs manual tagging
- Collapsing the AI keyword tree in the Keyword List panel
- Bulk-selecting and deleting AI keywords if needed

The parent keyword itself is set to `includeOnExport = false`, so it won't appear in exported photo metadata — only the child keywords will.

> **Note:** If a keyword with the same name already exists at the root level (from a previous run without a parent), the plugin may create a second keyword with the same name under the parent. This is a Lightroom SDK limitation. To avoid duplicates, delete root-level AI keywords before switching to a parent keyword.

### Context & Instructions

- **GPS coordinates:** When enabled (default), GPS coordinates from photo EXIF are sent to the model for location-aware keywording. Disable for privacy.
- **Folder context:** When enabled, catalog folder names (e.g. `Dominican Republic > Santo Domingo`) are passed to the model as location hints. Generic folder names like "Photos" and "Imports" are filtered out.
- **Folder aliases:** Expand short folder names (e.g. `DR=Dominican Republic; CR=Costa Rica`).
- **Custom instructions:** Optional additional prompt instructions for domain-specific guidance (e.g. "Focus on architecture and design elements"). The built-in base prompt handles keyword style automatically.

---

## Choosing a Provider

| | Ollama | Claude | OpenAI | Gemini |
|---|---|---|---|---|
| Cost | Free | $0.002–0.025/image | $0.0003–0.007/image | $0.0002–0.003/image |
| Speed | 4–20s (Apple Silicon) | ~2s | ~2s | ~2s |
| Quality | Good general keywords | Excellent, best landmark ID | Very good | Very good |
| Privacy | Local, nothing leaves your machine | Cloud | Cloud | Cloud |

**Recommendation:** Ollama for casual tagging and privacy. Claude Sonnet 4.6 or Opus 4.7 for accuracy-critical runs. Gemini 3.1 Flash-Lite (preview) for cheapest cloud option. Use Compare Models to test which works best for your photos.

---

## Logging

Enable logging in Settings to get a timestamped log file for each run. Logs are written incrementally (crash-safe) and include:

- Provider, model, and settings used
- Base prompt (once per run)
- Per-image results (keywords, errors, skips)
- Raw model response (first 500 chars)
- Per-image timing

GPS coordinates are intentionally **redacted** from logs — when GPS context is enabled, the log records only that coordinates were sent to the model, not the actual values. Logs persist on disk and are occasionally shared for support, so redaction avoids leaking exact locations.

Log files are saved to the configured folder (default: `~/Documents`).

---

## Performance

- **Ollama:** ~4–20 seconds per image depending on model and hardware
- **Cloud providers:** ~2–5 seconds per image
- Keywords are written incrementally — safe to cancel and resume
- "Skip keyworded" avoids re-processing already-tagged photos

> **Note:** Lightroom's UI may be briefly unresponsive while each image is being processed. This is a limitation of the Lightroom SDK — there is no non-blocking shell execution available. The progress bar updates between images and you can cancel at any time.

---

## Troubleshooting

**Ollama: Timeout / curl exit 28** → Increase timeout in Settings.
**Ollama: "Could not connect"** → Start Ollama from Settings or run `ollama serve` in Terminal.
**Claude: "API error"** → Check your API key and account balance at console.anthropic.com.
**OpenAI: "API error"** → Check your API key at platform.openai.com.
**Gemini: "API error"** → Check your API key at aistudio.google.com.
**Keywords not appearing under parent** → See note above about existing root-level keywords.
