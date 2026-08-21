# Logo restore golden suite

Regression harness for customer-logo **restore / knockout / finalize** quality.

Goal: smarter reconstruction (infer lost edges/fills) with **fidelity gates** —
not cubic-only, not free-form brand redesigns.

## Purpose

- Score engines against fixed seed originals under `cases/<slug>/original.png`
- Catch matte leftovers, aspect warp, color drift, and ink-mask regressions
- Evidence-gate Gemini: default **off**; only re-enable if suite scores improve

## Anchors (quality north star)

These two Swift brand marks are the **multi-iteration pinnacle** — the class of
result restore should aim for on other flat lockups (sharp edges, clean matte,
correct orange, print-ready resolution, no plate/halo junk). Not free-form
redraws; not Swift-only hacks.

| Slug | Asset | Role |
|------|-------|------|
| `swift_orange` | `swift_supply_logo_orange.png` | **Primary document / PDF** lockup (orange SWIFT + bars, black SUPPLY). Documents skip customer bg-strip on this file. |
| `swift_orange_solid` | `swift_supply_logo_orange_solid.png` | **Solid orange** chrome / side-menu variant (flat, no shadow). |
| `gcm`, `bird` | customer seeds | Strong / fragile cases (white outlines; multi-color wordmark) |
| Others | customer seeds | Flat + photo-like mix (Propak, Trialta, BFL, Arc, …) |

## Phase 4 — synthetic improve loop

Executable degrade → restore → score scaffolding lives under
[`qa_logos/synthetic/`](../synthetic/README.md) (`scripts/logo_synthetic_degrade.py`,
`scripts/logo_restore_improve_loop.py`). Agents continue that loop on logo/restore
work without waiting for a re-prompt; golden cases here remain the regression
gate. Neural fine-tune is optional later — score-proven engine wins first.

## Metrics

| Metric | Meaning |
|--------|---------|
| `aspect_drift` | Ink AABB aspect change vs source (0 = identical) |
| `ink_iou` | Alpha ink-mask IoU after downsample to source size |
| `palette_fidelity` | Fraction of restored ink near a source brand color |
| `alpha_clean` | 1 − leftover plate fraction (near-white/near-black outer canvas) |
| `edge_energy_ratio` | Optional: restored edge strength / source (↑ = sharper) |
| `composite` | Weighted blend used for ranking modes |

## How to run

From repo root (Windows):

```powershell
# Default pipeline path in Python harness (prepare + cubic upscale proxy).
# Modes: baseline | vectorize | esrgan | gemini-off | gemini-on | all
python scripts/logo_golden_suite.py --mode all

# Write scores
#   qa_logos/golden/scores_latest.json
#   qa_logos/golden/scores_latest.csv
```

Dart non-regression (prepare / process path; skips if folder missing):

```powershell
cd mobile
flutter test test/logo_golden_suite_test.dart
```

Env:

- `LOGO_RESTORE_USE_GEMINI=1` — allow optional Gemini branch in the app restorer
- Gemini API key required only for `--mode gemini-on`

## Interpreting scores

Higher `composite` / `ink_iou` / `palette_fidelity` / `alpha_clean` is better.
`aspect_drift` should stay low (typically &lt; 0.25 for faithful restores).
Compare modes on the same seed set before promoting an engine.
