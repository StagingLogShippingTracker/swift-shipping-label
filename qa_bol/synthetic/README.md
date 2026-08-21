# BOL improve / training loop

Executable scaffolding for **generate → render → score → fix → re-run** on the
Bill of Lading PDF. Same idea as Shipping Label (`qa_shipping/synthetic`) and
logo Phase 4 (`qa_logos/synthetic`).

## North star

Latest BOL sample geometry — `filled/qa_bol_preview/bol_preview_latest.png`
(regenerate via `mobile/test/generate_bol_preview_test.dart`) — plus the
`baseline_sample` case in this matrix (`ShippingLabelData.bolSample` + sample
customer logo).

Goals for score-driven fixes:

- Spacing / bleed / overcrowding
- Long **Sales Order / PO / Project / Packing List** values shrink or wrap —
  never cut off or vanish
- Single + dual customer logos (various shapes): stay inside the left header
  frame; never bleed under Probill cut-out or Swift wordmark

Do **not** touch Shipping Label locked SO/Contact constants
(`.cursor/rules/shipping-label-approved-layout.mdc`).

## Layout

```
qa_bol/synthetic/
  README.md
  renders/                 # <case_id>.pdf + .png (from Dart harness)
  layout_debug/            # per-case PDF geometry dumps
  manifest.json            # case matrix from last harness run
  improve_log.jsonl        # append-only run history
  improve_summary_latest.json
  training_lessons.json    # durable lessons + automatic run snapshots
```

## Training memory

```powershell
python scripts/improve_loop_training.py append-lesson bol `
  --title "..." --lesson "..." --do-not-regress "..."
```

See `.cursor/rules/improve-loops-training.mdc`.

## Case matrix (harness)

| Case id | Intent |
|---------|--------|
| `baseline_sample` | North-star bolSample + sample logo |
| `logo_square` | Square-ish customer logo (ARJAE) |
| `logo_rect` | Rectangular logo (Propak) |
| `logo_dual_arc_trialta` | Dual Arc + Trialta |
| `logo_wide` | Wide lockup (WPW) |
| `logo_tall_ish` | Taller / square-ish (Spartan / ARJAE) |
| `text_long_so` | Extreme sales order / order # |
| `text_long_po` | Extreme PO # |
| `text_long_project` | Extreme project |
| `text_long_packing_list` | Extreme packing list # |
| `text_long_all_refs` | All four tracking fields extreme |
| `text_long_ship_to` | Extreme ship-to name + address |

## Incremental loop

1. **Generate / render** — `flutter test test/bol_improve_loop_test.dart`
   (repo `.tools/flutter`) writes PDF/PNG + manifest under `renders/`.
2. **Score** — `scripts/bol_label_score.py` scores each PNG (0–1, higher
   better) and optional `layout_debug/*.json`.
3. **Log** — `scripts/bol_label_improve_loop.py` appends
   `improve_log.jsonl` and writes `improve_summary_latest.json`.
4. **Fix** — attack top failures that are real layout bugs (cutoff, logo
   encroachment, margins, overcrowding). Re-run.
5. Protect visual quality of `baseline_sample` / `bol_preview_latest`.

## Commands

From repo root:

```powershell
# One full iteration (render + score + summary)
python scripts/bol_label_improve_loop.py

# Score existing renders only
python scripts/bol_label_score.py

# Harness only
.\.tools\flutter\bin\flutter.bat test test/bol_improve_loop_test.dart
# (cwd: mobile/)
```

## Continuation trail for agents

When touching BOL PDF / layout / logo ink-fit for BOL:

1. Read `improve_summary_latest.json` and `training_lessons.json`.
2. Fix the listed **top_failures** without changing Shipping SO/Contact locks.
3. Re-run `bol_label_improve_loop.py` and confirm composite / gates move
   the right way; append score-proven lessons.
4. Do **not** wait for the user to re-ask — continue unprompted on this loop.
5. Commit only if the user asked; this loop itself does not require a commit.

See also: `.cursor/rules/bol-improve-loop.mdc`.
