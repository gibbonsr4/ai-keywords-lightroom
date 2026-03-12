# AI Keywords — Lightroom Classic Plugin

Automatically generates and applies searchable keywords to selected photos using either a **local Ollama vision model** or the **Claude API**. Your choice of free local processing or higher-quality cloud results.

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

**For Claude API:**
- An Anthropic API key from [console.anthropic.com](https://console.anthropic.com)

### Supported File Types
JPEG, PNG, TIFF, WEBP, HEIC/HEIF, and all RAW formats supported by Lightroom (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF, SRW).

Images are rendered via Lightroom's own export pipeline, so any format Lightroom can open will work.

---

## Installation

1. Place the `AIKeywords 2.lrplugin` folder somewhere permanent (e.g. `~/Documents/LR Plugins/`)
2. In Lightroom Classic: **File → Plug-in Manager → Add**
3. Navigate to and select the `AIKeywords 2.lrplugin` folder
4. Click **Done**

---

## Usage

1. Open Settings and choose your provider (Ollama or Claude API)
2. In Lightroom Library, select one or more photos
3. **Library → Plug-in Extras → Generate AI Keywords — Selected Photos**
4. Wait for the progress bar to complete
5. Keywords appear in the **Keywording** panel

### Compare Models

Want to find the best model for your photos? Use the comparison tool:

1. Select **one** photo in the Library
2. **Library → Plug-in Extras → Compare Models — Selected Photo**
3. Check 2–5 models to compare (installed Ollama models and/or Claude models)
4. Optionally override the prompt for this comparison
5. View side-by-side results with timing, keyword counts, and overlap analysis

No keywords are saved — this is a preview-only tool for evaluating model quality and testing prompts.

---

## Configuration

Open **Library → Plug-in Extras → Settings…** to configure. The Save button is disabled until all required fields are valid.

### Provider

Choose between **Ollama (local)** and **Claude API (cloud)** via radio buttons.

### Ollama Settings

The plugin checks Ollama's status when you open Settings and shows whether it's installed, running, and which models are available. You can:

- **Start Ollama** directly from Settings (or open the download page if not installed)
- **Choose a model** from the dropdown with install status indicators (✓ = installed)
- **Install models** by clicking "Install in Terminal"

<a id="ollama-models"></a>

Recommended models for 24GB Apple Silicon:

| Model | RAM | Best For |
|---|---|---|
| Gemma 3 4B | ~3GB | Popular, versatile vision model |
| Qwen2.5-VL 3B | ~2GB | Fastest option, good quality for size |
| MiniCPM-V 8B | ~5GB | Fast, strong at detail recognition |
| Qwen2.5-VL 7B | ~5GB | Best local quality, accurate species IDs |
| Qwen3-VL 8B | ~5GB | Next-gen Qwen vision |
| Gemma 3 12B | ~8GB | High quality, strong all-rounder |
| Llama 3.2 Vision 11B | ~8GB | Solid all-rounder |
| Moondream 2 | ~1GB | Tiny, fast, basic keywords only |

> **Note:** Qwen2.5-VL and Qwen3-VL models require Ollama 0.7.0 or newer.
>
> The model list updates automatically when you open Settings — no plugin update needed. You can also uninstall models directly from Settings to free disk space.

### Claude API Settings

| Setting | Notes |
|---|---|
| API Key | Your Anthropic API key |
| Model | Haiku 4.5 (~$0.002/image) or Sonnet 4.6 (~$0.007/image) |

### Keyword Settings

| Setting | Default | Notes |
|---|---|---|
| Max keywords | 20 | Per photo, 1–50. Also communicated to the model in the prompt. |
| Keyword case | As returned | Options: As returned, lowercase, Title Case |
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

### Other Options

- **Folder context:** When enabled, catalog folder names (e.g. `Dominican Republic > Santo Domingo`) are passed to the model as location hints. Generic folder names like "Photos" and "Imports" are filtered out.
- **Folder aliases:** Expand short folder names (e.g. `DR=Dominican Republic; CR=Costa Rica`).
- **Prompt:** Fully customizable. Click "Reset to default prompt" to restore the built-in prompt.

---

## Ollama vs Claude: When to Use Each

| | Ollama | Claude API |
|---|---|---|
| Cost | Free | ~$0.002–0.007/image |
| Speed | 4–20s/image (Apple Silicon) | 2–5s/image |
| Quality | Good for general keywords | Better species ID, more consistent |
| Privacy | Images never leave your machine | Images sent to Anthropic |
| Batch (25k) | Free, hours to days | ~$50–170, much faster |

**Recommendation:** Use Ollama for casual tagging and testing. Use Claude API (Haiku) for large batch runs where quality and speed matter.

---

## Logging

Enable logging in Settings to get a timestamped log file for each run. Logs are written incrementally (crash-safe) and include:

- Provider, model, and settings used
- Per-image results (keywords, errors, skips)
- Full prompt sent to the model
- Raw model response
- Per-image timing

Log files are saved to the configured folder (default: `~/Documents`).

---

## Performance

- **Ollama:** ~4–20 seconds per image depending on model and hardware
- **Claude API:** ~2–5 seconds per image
- Keywords are written incrementally — safe to cancel and resume
- "Skip keyworded" avoids re-processing already-tagged photos

> **Note:** Lightroom's UI may be briefly unresponsive while each image is being processed. This is a limitation of the Lightroom SDK — there is no non-blocking shell execution available. The progress bar updates between images and you can cancel at any time.

---

## Troubleshooting

**Ollama: Timeout / curl exit 28** → Increase timeout in Settings.
**Ollama: "Could not connect"** → Start Ollama from Settings or run `ollama serve` in Terminal.
**Claude: "API error"** → Check your API key and account balance at console.anthropic.com.
**Keywords not appearing under parent** → See note above about existing root-level keywords.
**Old prompt after upgrade** → Open Settings → "Reset to default prompt".
