# Synthetic logo restore improve loop (Phase 4)

Executable scaffolding for **degrade → restore → score → improve** without waiting
for a neural fine-tune. This is the product training loop: prove engine wins with
the same metrics as the golden suite, then iterate.

## Layout

```
qa_logos/synthetic/
  clean/                 # North-star / flat high-res refs (PNG)
  degraded/              # Deterministic degradations of clean/
  restored/              # Last loop engine outputs (gitignored-friendly)
  pairs.json             # clean ↔ degraded + recipe + seed
  improve_log.jsonl      # Append-only run history
  improve_summary_latest.json
  training_lessons.json  # Durable lessons + automatic run snapshots
  README.md              # this file
```

## Training memory

```powershell
python scripts/improve_loop_training.py append-lesson logo `
  --title "..." --lesson "..." --do-not-regress "no invented Arc red from gray"
```

See `.cursor/rules/improve-loops-training.mdc`.

### Anchors (quality north star)

| Slug | Role |
|------|------|
| `swift_orange` | Primary document / PDF lockup — near-perfect recomposition target |
| `swift_orange_solid` | Solid chrome / menu variant — same bar |

Customer flats (`gcm`, `propak`, `trialta`, `arc`, …) exercise vectorize-friendly
lockups. Do **not** treat Swift-only hacks as success; anchors define the quality
class other logos should approach.

## Incremental loop

1. **Degrade** clean refs with controlled recipes (`downscale_jpeg`, `blur_crush`,
   `plate_halo`, `banding_jpeg`, `import_combo`) — see
   `scripts/logo_synthetic_degrade.py` (deterministic seeds).
   `import_combo` is softened so residual brand chroma usually survives (real
   phone imports rarely wipe hue to pure gray); do not invent colors when it
   does not.
2. **Restore** with current engines: `baseline` (prepare+cubic), `vectorize`,
   `esrgan` if deps present.
3. **Score** restored vs **clean** using golden metrics from
   `scripts/logo_golden_suite.py` (`ink_iou`, `palette_fidelity`, `alpha_clean`,
   `aspect_drift`, `edge_energy_ratio`, `composite`).
4. **Log** every row to `improve_log.jsonl`; print top failures.
5. **Next technique**: fix the lowest-composite gaps; re-run; promote only
   changes that raise scores. Neural fine-tune only when the suite plateaus.

Fidelity gates in the app stay on — this loop does not unwire them.

## Commands

From repo root:

```powershell
# (Re)build degraded/ + pairs.json from clean/
python scripts/logo_synthetic_degrade.py --seed-from-clean

# One improve iteration (degrade if pairs missing; restore; score; append log)
python scripts/logo_restore_improve_loop.py --degrade-first

# Faster iteration while hacking cubic/vectorize only
python scripts/logo_restore_improve_loop.py --engines baseline,vectorize --top 8
```

## Continuation trail for agents

When working on logo restore / vectorize / ESRGAN / golden suite:

1. Read `improve_summary_latest.json` + tail of `improve_log.jsonl`.
2. Attack the listed **top_failures** (especially `swift_orange*` anchors).
3. Make an incremental engine change.
4. Re-run `logo_restore_improve_loop.py` and confirm composite / IoU / palette /
   alpha move the right way.
5. Do **not** wait for the user to re-ask for “Phase 4”.
6. Commit policy: follow session / user preference; if user said wait on the
   bigger roadmap, leave files ready and do not push until asked.

See also: `.cursor/rules/logo-restore-improve-loop.mdc` and
`qa_logos/golden/README.md`.
