# Whole-app improve / training loop

Executable scaffolding for **harness → score → fix → re-run** across Document
Generator functions (generate, history, addresses, restore smoke, speed).

Same training contract as logo / Shipping / BOL — see
`.cursor/rules/improve-loops-training.mdc` and `app-improve-loop.mdc`.

## Layout

```
qa_app/synthetic/
  README.md
  harness_results.json       # case results from Dart harness
  artifacts/                 # optional PDF/timing artifacts
  improve_log.jsonl          # append-only run history
  improve_summary_latest.json
  training_lessons.json      # durable lessons + automatic run snapshots
```

## Curriculum (expand over time)

Typical cases (see latest `harness_results.json` / summary):

| Case id | Intent |
|---------|--------|
| `cold_start_storage` | Storage open / cold start timing |
| `generate_shipping` / `receiving` / `bol` | PDF generate success + timing |
| `rapid_generate_loop` | Repeated generate without crash |
| `logo_restore_cubic` | Restore path timing (honest budgets) |
| `address_book_local` | Address book load / filter / collapse |
| `history_open_no_prune` | No prune-on-open wipe |
| `history_snapshot_heuristics` | Snapshot / missing-object heuristics |
| `exclusive_dialogs` | Exclusive dialog gates |

Add cases when new glitches appear.

## Commands

```powershell
python scripts/app_improve_loop.py
python scripts/app_improve_loop.py --skip-harness
python scripts/improve_loop_training.py append-lesson app --title "..." --lesson "..."
```

## Continuation

1. Read `improve_summary_latest.json` + `training_lessons.json`
2. Fix real top failures; expand cases for new glitches
3. Re-run; append score-proven lessons
4. Do not wait for the user to re-ask
