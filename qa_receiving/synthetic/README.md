# Receiving Label improve / training loop

Executable scaffolding for **generate → render → score → fix → re-run** on the
Receiving Label PDF. Same training contract as Shipping / BOL / logo / app —
see `.cursor/rules/improve-loops-training.mdc` and
`receiving-label-improve-loop.mdc`.

## North star

`baseline_receiving_sample` (`ShippingLabelData.receivingSample`).

Receiving-specific layout (do **not** confuse with Shipping lock):

| Behavior | Value |
|----------|-------|
| Under-pill `showRule` | **true** (SO → PM) |
| `afterPillGap` | **11.0** |
| SO pill | Yellow `recvSoBg` |
| Instructions | Red alert fill when non-empty |

## Layout

```
qa_receiving/synthetic/
  README.md
  renders/
  layout_debug/
  manifest.json
  improve_log.jsonl
  improve_summary_latest.json
  training_lessons.json
```

## Commands

```powershell
python scripts/receiving_label_improve_loop.py
python scripts/receiving_label_improve_loop.py --skip-render
python scripts/improve_loop_training.py append-lesson receiving --title "..." --lesson "..."
```

## Continuation

1. Read `improve_summary_latest.json` + `training_lessons.json`
2. Fix real top failures; expand cases for new glitches
3. Re-run; append score-proven lessons
4. Do not wait for the user to re-ask
