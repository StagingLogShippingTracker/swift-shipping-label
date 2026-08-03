# Logo Vectorizer — Ensemble + AI Advisors

Multi-backend PNG → SVG vectorizer with automatic scoring, optional vision AI advisors, hole preservation, and param caching.

## Install

```powershell
pip install -r tools/logo_vectorizer/requirements.txt
```

Optional: `winget install Inkscape.Inkscape` for an additional trace backend.

## CLI

```powershell
# Offline ensemble (no API keys needed)
python -m tools.logo_vectorizer --input assets/brand/swift_supply_logo_orange.png `
  --output out.svg --fill "#CE4E30" --qa

# With vision AI advisors (reads keys from environment only)
$env:GOOGLE_API_KEY = "..."      # or GEMINI_API_KEY
$env:ANTHROPIC_API_KEY = "..."
$env:OPENAI_API_KEY = "..."

python -m tools.logo_vectorizer --input assets/brand/swift_supply_logo_orange.png `
  --output out.svg --fill "#CE4E30" --qa --ai `
  --ai-providers gemini,claude,openai
```

## Brand export

```powershell
python scripts/process_header_logo.py --brand
```

## Pipeline

1. **AI pre-analysis** (optional) — Gemini/Claude/OpenAI vision → hole detection, backend/preprocess hints
2. **Preprocess ensemble** — 4 scale/blur/threshold variants (2×–4× LANCZOS)
3. **Multi-backend race** — OpenCV RETR_TREE + RETR_CCOMP, potrace, vtracer, Inkscape
4. **Scoring** — alpha IoU, SSIM, edge overlap, SUPPLY P-counter hollow ratio
5. **AI critique** (optional) — vision review of top candidates; reject filled P counters / jagged edges
6. **Post-refinement** — RDP, Chaikin, Catmull-Rom Béziers; arc-fit for P bowls
7. **Cache** — best backend+params in `tools/logo_vectorizer/.cache/` by image hash
8. **QA** — Chrome headless render; P-counter transparency + side-by-side crop

All paths use `fill-rule="evenodd"` so letter counters subtract correctly.

## API keys (never commit)

| Provider | Environment variable |
|----------|---------------------|
| Gemini   | `GOOGLE_API_KEY` or `GEMINI_API_KEY` |
| Claude   | `ANTHROPIC_API_KEY` |
| OpenAI   | `OPENAI_API_KEY` |

If no keys are set, `--ai` soft-fails and the offline ensemble runs fully.
