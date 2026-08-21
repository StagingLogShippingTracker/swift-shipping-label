# Shipping Label improve / training loop

Executable scaffolding for **generate → render → score → fix → re-run** on the
Shipping Label PDF. Same idea as logo Phase 4 (`qa_logos/synthetic`), but the
north star is the **approved Shipping Label layout**, not logo fidelity.

## North star

Current approved sample geometry — especially SO pill → SWIFT CONTACT spacing —
as locked in `.cursor/rules/shipping-label-approved-layout.mdc` and exercised by
`mobile/test/shipping_qa_preview_test.dart` / `filled/qa_shipping_preview/shipping_preview_latest.*`.

**Do not change** locked constants to chase scores:

| Lock | Approved |
|------|----------|
| `afterPillGap` | **11.0** |
| under-pill `showRule` | **false** |
| Contact label→value | **3.0**, value **centered** |

Those are **gates**. If they “fail”, fix the scorer thresholds to match the
approved sample — never reopen the layout lock.

## Layout

```
qa_shipping/synthetic/
  README.md
  renders/                 # <case_id>.pdf + .png (from Dart harness)
  layout_debug/            # optional per-case PDF Y dumps (from Dart)
  manifest.json            # case matrix from last harness run
  improve_log.jsonl        # append-only run history
  improve_summary_latest.json
```

## Case matrix (harness)

| Case id | Intent |
|---------|--------|
| `baseline_dual_arc_trialta` | North-star dual rectangular logos |
| `square_arjae` | Square-ish customer logo height class |
| `rect_propak` | Rectangular customer logo height class |
| `mixed_arjae_propak` | Dual mixed height classes + pink clamp |
| `logo_lowres` | Small / degraded customer logo |
| `text_long_*` | Extreme strings (customer, ship_to, address, contact, project, so, instructions) |
| `freight_customer_pickup` | Customer Pick-Up freight term |

## Incremental loop

1. **Generate / render** — `flutter test test/shipping_improve_loop_test.dart`
   (repo `.tools/flutter`) writes PDF/PNG + manifest under `renders/`.
2. **Score** — `scripts/shipping_label_score.py` scores each PNG (0–1, higher
   better) and optional `layout_debug/*.json`.
3. **Log** — `scripts/shipping_label_improve_loop.py` appends
   `improve_log.jsonl` and writes `improve_summary_latest.json`.
4. **Fix** — attack top failures that are **not** locked SO/Contact gates
   (overflow, logo encroachment, margins, columns, bars). Re-run.
5. **Gates** — if only SO/Contact gate “failures” appear and the approved sample
   fails the same way, tighten/loosen **scorer bands** to the approved sample.

## Commands

From repo root:

```powershell
# One full iteration (render + score + summary)
python scripts/shipping_label_improve_loop.py

# Score existing renders only
python scripts/shipping_label_score.py

# Harness only
.\.tools\flutter\bin\flutter.bat test test/shipping_improve_loop_test.dart
# (cwd: mobile/)
```

## Continuation trail for agents

When touching Shipping Label PDF / layout / logo ink-fit for shipping:

1. Read `improve_summary_latest.json` (and tail of `improve_log.jsonl`).
2. Fix the listed **top_failures** without changing locked SO/Contact constants.
3. Re-run `shipping_label_improve_loop.py` and confirm composite / gates move
   the right way.
4. Do **not** wait for the user to re-ask — continue unprompted on this loop.
5. Commit only if the user (or standing repo commit policy for this session)
   asked; this loop itself does not require a commit.

See also: `.cursor/rules/shipping-label-improve-loop.mdc` and
`.cursor/rules/shipping-label-approved-layout.mdc`.
