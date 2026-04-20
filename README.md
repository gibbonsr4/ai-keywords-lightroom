# AI Keywords — Lightroom Classic Plugin

Generates and applies searchable keywords to selected photos using local Ollama vision models or cloud APIs (Claude, OpenAI, Gemini).

**macOS only.** Optimized for Apple Silicon.

---

## Requirements

| Requirement | Notes |
|---|---|
| Lightroom Classic 6+ | |
| macOS (Apple Silicon recommended) | Uses `curl`; no Windows support yet |

Plus one or more of:

- **Ollama** (local, free) — requires ~2–15 GB disk per model and enough RAM to run it
- **Anthropic Claude API key** — from [console.anthropic.com](https://console.anthropic.com)
- **OpenAI API key** — from [platform.openai.com](https://platform.openai.com)
- **Google AI (Gemini) API key** — from [aistudio.google.com](https://aistudio.google.com)

### Supported file types

JPEG, PNG, TIFF, WEBP, HEIC/HEIF, and every RAW format Lightroom can open (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF, SRW). Images are rendered through Lightroom's export pipeline, so if LR can open it, the plugin can keyword it.

---

## Install the plugin

1. Download or clone this repo. Place the `AIKeywords.lrplugin` folder somewhere permanent (e.g. `~/Documents/Lightroom Plugins/`). Don't leave it in Downloads.
2. In Lightroom Classic: **File → Plug-in Manager → Add**.
3. Select the `AIKeywords.lrplugin` folder. Click **Done**.

The plugin adds three entries under **Library → Plug-in Extras**:

- **Generate AI Keywords — Selected Photos**
- **Compare Models — Selected Photo**
- **Settings…**

---

## First-run setup

Pick one path below. You can add others later.

### Path A — Ollama (local, free)

Best for privacy, large batches, no per-image cost. Slower than cloud (~5–20 s/image).

1. **Install Ollama.** Download from [ollama.com/download](https://ollama.com/download) and run the installer. It installs as a menu-bar app.
2. **Start Ollama.** Either open the Ollama app or, from the plugin's Settings (Library → Plug-in Extras → Settings…) click **Start Ollama**.
3. **Pick and install a model.** In Settings, on the **Ollama** tab, choose a model from the dropdown and click **Install Model**. Terminal opens and runs `ollama pull <model>` so you can watch progress.

Good first pick for 16 GB Macs: **Qwen2.5-VL 7B** (~5 GB, the default). For 8 GB Macs, use **Qwen3-VL 4B** (~3 GB). See the [model table](#ollama-models) below.

4. **Select a few photos** in the Library grid.
5. **Library → Plug-in Extras → Generate AI Keywords — Selected Photos.** Wait for the progress bar. Keywords appear in the Keywording panel.

If Ollama seems slow, check its menu-bar app for an **MLX backend** option — it's significantly faster on Apple Silicon once enabled.

### Path B — Cloud API (Claude / OpenAI / Gemini)

Best for accuracy and speed (~2–5 s/image). Costs fractions of a cent per image.

1. **Get an API key** from one of:
   - **Anthropic:** [console.anthropic.com](https://console.anthropic.com) → API Keys → Create Key. Needs a small credit balance (~$5 is plenty for thousands of images).
   - **OpenAI:** [platform.openai.com/api-keys](https://platform.openai.com/api-keys) → Create new secret key.
   - **Google AI Studio:** [aistudio.google.com/apikey](https://aistudio.google.com/apikey) → Create API Key.
2. **Open Settings** (Library → Plug-in Extras → Settings…) and switch to the provider's tab.
3. **Paste your API key** into the field. Pick a model from the dropdown. Save.

API keys are stored in the macOS Keychain, not in plaintext preferences.

Default models on fresh install: Claude Sonnet 4.6, OpenAI GPT-5.4 Mini, Gemini 3.1 Pro.

4. **Select photos**, run **Generate AI Keywords**. Keywords arrive in a few seconds.

---

## Usage

### Generate keywords

1. Select one or more photos in the Library grid.
2. **Library → Plug-in Extras → Generate AI Keywords — Selected Photos.**
3. Keywords land in the Keywording panel as each photo finishes.

Supports cancellation (click the × on the progress bar) and resume (re-run on the same selection with **Skip keyworded** enabled in Settings).

### Compare models

Side-by-side keyword output from up to 5 models on a single photo. No keywords are saved to the catalog — it's a preview-only tool.

1. Select **one** photo.
2. **Library → Plug-in Extras → Compare Models — Selected Photo.**
3. Check 2–5 models (Ollama, Claude, OpenAI, Gemini). Click **Compare**.
4. Results show keywords per model, timing, per-image cost estimate, and overlap analysis.

Each model uses its production prompt — Haiku gets a shorter variant, everything else gets the standard prompt. A custom prompt set in Settings wins for all selected models.

---

## Configuration

Open **Library → Plug-in Extras → Settings…** The **Save** button stays disabled until required fields are valid.

### Provider tabs

Switch between **Ollama**, **Claude**, **OpenAI**, **Gemini** via the tabs at the top. Each provider has its own model and API-key settings, but **only one provider is active at a time** — the one on the currently-selected tab.

### Ollama settings

- **Status:** shows whether Ollama is installed and running, plus its version. Clickable button: Download / Start / Refresh depending on state.
- **URL:** defaults to `http://localhost:11434` (standard Ollama). Change only if you run Ollama on another host.
- **Model:** dropdown of recommended models with install indicators. Installed models show ✓; others show "not installed."
- **Install Model / Uninstall Model:** Install opens Terminal so you can watch `ollama pull` progress. Uninstall runs `ollama rm` silently.
- **Check for New Models:** fetches the latest recommended list from GitHub — no plugin update needed when the Ollama landscape shifts.

<a id="ollama-models"></a>

#### Recommended Ollama models

| Model | RAM | Best for |
|---|---|---|
| Moondream 2 | ~1 GB | Tiny fallback for constrained Macs; basic keywords only |
| Qwen3-VL 4B | ~3 GB | Fastest decent tier; good for 8 GB Macs |
| Qwen2.5-VL 7B | ~5 GB | Battle-tested default; accurate species/object IDs |
| Gemma 4 E4B | ~6 GB | Google's current small multimodal |
| MiniCPM-V 4.5 8B | ~6 GB | Strong detail and OCR (built on Qwen3 + SigLIP2) |
| Qwen3-VL 8B | ~6 GB | Newer Qwen generation; main quality tier |
| Gemma 4 31B | ~14 GB | High-quality dense; 32 GB+ Macs |

Qwen2.5-VL and Qwen3-VL models require **Ollama 0.7+**. Gemma 4 and MiniCPM-V 4.5 need a recent Ollama build.

### Claude settings

| Model | ~Cost/image | Notes |
|---|---|---|
| Claude Haiku 4.5 | $0.002 | Cheap tier; uses a shorter compact prompt. Can over-commit to wrong specifics on unusual architecture. |
| **Claude Sonnet 4.6** | $0.007 | **Default.** Balanced — strong reasoning, conservative on specific names, clean generics. |
| Claude Opus 4.7 | $0.025 | Highest accuracy; worth it for landmark-heavy runs. |

### OpenAI settings

| Model | ~Cost/image | Notes |
|---|---|---|
| GPT-5.4 Nano | $0.0003 | Ultra-cheap batch/bulk tier. |
| **GPT-5.4 Mini** | $0.001 | **Default.** Sweet spot for single-image keyword extraction. |
| GPT-5.4 | $0.007 | Flagship — use for hard cases. |

### Gemini settings

| Model | ~Cost/image | Notes |
|---|---|---|
| Gemini 3.1 Flash-Lite | $0.0002 | Cheapest cloud option anywhere. Clean generics; rarely names specific landmarks. |
| Gemini 3 Flash | $0.0008 | Cheap + fast; comparable quality to Flash-Lite. |
| **Gemini 3.1 Pro** | $0.003 | **Default.** Strongest at naming specific landmarks/resorts/parks. |
| Gemini 2.5 Pro (legacy) | $0.005 | Kept as a fallback — still recognizes some specific properties the 3.x preview series misses. Google is phasing 2.5 out; may disappear without notice. |

All Gemini 3 IDs are currently preview-tier (as of April 2026).

### Keyword settings

| Setting | Default | Notes |
|---|---|---|
| Max keywords | 20 | 1–50 per photo. The model is told to return fewer if it doesn't have strong candidates, rather than pad with filler. |
| Keyword case | lowercase | Also: "As returned" or Title Case. |
| Timeout | 90 s | Per image. |
| Parent keyword | (blank) | Nests AI-generated keywords under a single parent. See below. |
| Skip keyworded | Off | Skip photos that already have keywords — useful for resuming interrupted runs. |

### Parent keyword (keyword hierarchy)

Leave blank for flat keywords at the root of your catalog. Set to something like `AI Generated` to nest every AI-added keyword under that parent.

Useful for:

- Distinguishing AI-added keywords from manual tagging at a glance
- Collapsing the AI subtree in the Keyword List panel
- Bulk-selecting and deleting all AI keywords

The parent itself is set to `includeOnExport = false`, so it won't appear in exported metadata — only its children will.

**Limitation:** if a keyword of the same name already exists at the root of your catalog (from a previous run without a parent), Lightroom's SDK won't move it — you may end up with duplicates. The plugin tries to minimize this by looking up children first, but the safest option if you're switching modes is to delete any stranded root-level AI keywords before your next run.

### Context & instructions

- **Use GPS coordinates from photo metadata:** passes EXIF GPS to the model for location-aware keywords. Disable for privacy. GPS values are *never* written to logs — only a "sent" flag.
- **Use catalog folder names as location hints:** treats your folder structure as soft location context (e.g. a photo in `Dominican Republic > Santo Domingo` gets that hint). Generic names like `Photos` and `Imports` are filtered out.
- **Folder aliases:** expand short folder names, e.g. `DR=Dominican Republic; CR=Costa Rica`. Accepts `;`, `,`, or newlines between entries.
- **Custom instructions:** optional extra prompt guidance (e.g. "Focus on architecture and design elements"). The built-in base prompt handles keyword style — you don't need to re-specify it here.
- **Timeout:** in seconds per image. Raise if you're on a slow Ollama model and seeing timeouts.

### Logging

Enable to write a timestamped `AI_Keywords_<date>.log` file per run. Log folder defaults to `~/Documents`.

Logs include provider, model, settings, the base prompt (once), per-image keywords / errors / timing, and the first 500 characters of each raw model response.

**GPS coordinates are redacted** — logs record only that GPS was included, not the actual values.

### Advanced — base prompt

Most users should ignore this. The built-in prompt handles keyword style, coverage, and landmark handling. Override only if you want a fundamentally different behavior. Empty means "use the plugin default," which automatically picks the right variant for the selected model (compact for Haiku, standard for everything else).

---

## Choosing a provider

|   | Ollama | Claude | OpenAI | Gemini |
|---|---|---|---|---|
| Cost | Free | $0.002–0.025 | $0.0003–0.007 | $0.0002–0.005 |
| Speed | 5–20 s | ~2 s | ~2 s | ~2 s |
| Privacy | Local | Cloud | Cloud | Cloud |
| Strength | General keywords | Conservative accuracy, strong reasoning | Balanced | Strongest at naming specific landmarks |

**Quick picks:**

- Casual tagging, privacy-sensitive: **Ollama** with Qwen2.5-VL 7B.
- Best per-photo accuracy, don't care about cost: **Claude Sonnet 4.6** or **Opus 4.7**.
- Best named-landmark recognition: **Gemini 3.1 Pro** (or Gemini 2.5 Pro as fallback).
- Cheapest cloud, bulk runs: **Gemini 3.1 Flash-Lite** or **GPT-5.4 Nano**.

Use **Compare Models** to see how 2–5 models handle the same photo side-by-side before committing.

---

## Performance notes

- **Ollama:** 5–20 s/image depending on model size and your Mac's RAM / chip.
- **Cloud providers:** 2–5 s/image including network.
- Keywords are written incrementally — cancelling mid-run keeps whatever finished.
- **Skip keyworded** in Settings avoids re-processing already-tagged photos (useful for resuming).
- Lightroom's UI may briefly unresponsive while each image is processed — this is an LR SDK limitation (no non-blocking shell exec). The progress bar updates between photos; Cancel is always available.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Ollama: "Could not connect" | Ollama isn't running. Click **Start Ollama** in Settings, or run `ollama serve` in Terminal. |
| Ollama: timeout / curl exit 28 | Raise the Timeout in Settings. Large images or small Macs can need 120–180 s. Consider a smaller model. |
| Ollama: model shows "not installed" | Click **Install Model**. Terminal opens and runs `ollama pull`. |
| Claude / OpenAI / Gemini: "HTTP 401" | Invalid or revoked API key. Regenerate at the provider's console and paste into Settings. |
| Claude / OpenAI / Gemini: "HTTP 429" | Rate limited. Wait a minute and retry. |
| Gemini: "model not found" | Google rotated a preview ID. Open Settings, pick a different Gemini model. Gemini 2.5 Pro legacy is stable; 3.x are preview-tier. |
| Keywords not under parent | Lightroom SDK limitation with pre-existing root-level keywords of the same name. Delete root-level AI keywords before switching to a parent. |
| Plugin UI feels frozen mid-run | Normal — see Performance notes above. Progress updates between images. |

---

## Privacy

- **Ollama:** nothing leaves your Mac.
- **Cloud providers:** the rendered JPEG (scaled to 1568 px long edge, stripped of face/location EXIF), the prompt text, and any GPS coordinates/folder hints you've enabled are sent to the provider. Keywords come back, and that's it.
- **API keys:** stored in the macOS Keychain.
- **Logs:** opt-in. GPS values redacted.

---

## License

See LICENSE. MIT.
