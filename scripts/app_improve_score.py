#!/usr/bin/env python3
"""Score qa_app/synthetic/harness_results.json → per-case composites (0–1).

Usage (repo root):
  python scripts/app_improve_score.py
  python scripts/app_improve_score.py --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / "qa_app" / "synthetic"
RESULTS = SYN / "harness_results.json"

# Soft speed budgets (ms). Score = clamp(budget / max(ms, 1), 0, 1) when ok.
BUDGETS_MS = {
    "cold_start_storage": 2500,
    "generate_shipping": 12000,
    "generate_receiving": 12000,
    "generate_bol": 18000,
    "logo_restore_cubic": 20000,
    "address_book_local": 800,
    "history_snapshot_heuristics": 500,
    "rapid_generate_loop": 45000,
}

# Cases scored mainly on boolean gates / success (speed secondary).
GATE_CASES = {
    "history_open_no_prune",
    "exclusive_dialogs",
}


def _clamp01(x: float) -> float:
    return max(0.0, min(1.0, float(x)))


def _speed_score(ms: float | None, budget: float) -> float:
    if ms is None:
        return 0.0
    if ms <= 0:
        return 1.0
    return _clamp01(budget / max(ms, 1.0))


def score_case(row: dict) -> dict:
    case_id = str(row.get("case_id") or "unknown")
    ok = bool(row.get("ok"))
    ms = row.get("duration_ms")
    try:
        ms_f = float(ms) if ms is not None else None
    except (TypeError, ValueError):
        ms_f = None

    metrics: dict[str, float] = {}
    gates: dict[str, bool] = {"success": ok}

    if case_id in GATE_CASES:
        raw = row.get("gates_raw") or {}
        for k, v in raw.items():
            gates[str(k)] = bool(v)
        all_gate = all(gates.values()) if gates else ok
        metrics["gates"] = 1.0 if all_gate else 0.0
        metrics["success"] = 1.0 if ok else 0.0
        composite = 1.0 if all_gate and ok else 0.0
        gates["all_ok"] = all_gate and ok
    elif case_id.startswith("generate_") or case_id == "rapid_generate_loop":
        bytes_n = int(row.get("bytes") or 0)
        min_b = int(row.get("min_bytes") or 0)
        if case_id == "rapid_generate_loop":
            raw = row.get("metrics_raw") or {}
            n = int(raw.get("n") or 0)
            successes = int(raw.get("successes") or 0)
            metrics["success_rate"] = (successes / n) if n else 0.0
            sizes = raw.get("sizes") or []
            if sizes:
                metrics["file_integrity"] = 1.0 if min(sizes) >= 10000 else 0.0
            else:
                metrics["file_integrity"] = 0.0
        else:
            metrics["file_integrity"] = (
                1.0 if (ok and bytes_n >= max(min_b, 1)) else 0.0
            )
            metrics["success"] = 1.0 if ok else 0.0
        budget = BUDGETS_MS.get(case_id, 15000)
        metrics["speed"] = _speed_score(ms_f, budget) if ok else 0.0
        # Weight integrity/success higher than raw speed.
        if case_id == "rapid_generate_loop":
            composite = (
                0.45 * metrics["success_rate"]
                + 0.35 * metrics["file_integrity"]
                + 0.20 * metrics["speed"]
            )
            gates["all_ok"] = metrics["success_rate"] >= 1.0 and metrics[
                "file_integrity"
            ] >= 1.0
        else:
            composite = (
                0.40 * metrics.get("success", 0.0)
                + 0.35 * metrics["file_integrity"]
                + 0.25 * metrics["speed"]
            )
            gates["all_ok"] = ok and metrics["file_integrity"] >= 1.0
    elif case_id == "logo_restore_cubic":
        budget = BUDGETS_MS[case_id]
        metrics["success"] = 1.0 if ok else 0.0
        metrics["speed"] = _speed_score(ms_f, budget) if ok else 0.0
        metrics["output_bytes"] = 1.0 if int(row.get("bytes") or 0) > 0 else 0.0
        composite = (
            0.50 * metrics["success"]
            + 0.30 * metrics["output_bytes"]
            + 0.20 * metrics["speed"]
        )
        gates["all_ok"] = ok and metrics["output_bytes"] >= 1.0
    elif case_id == "address_book_local":
        budget = BUDGETS_MS[case_id]
        raw = row.get("metrics_raw") or {}
        hits = int(raw.get("filter_hits") or 0)
        collapsed = int(raw.get("collapsed_count") or 0)
        raw_n = int(raw.get("raw_count") or 0)
        metrics["success"] = 1.0 if ok else 0.0
        metrics["filter_works"] = 1.0 if hits > 0 else 0.0
        metrics["collapse_works"] = 1.0 if (raw_n > 0 and collapsed < raw_n) else 0.0
        metrics["speed"] = _speed_score(ms_f, budget) if ok else 0.0
        composite = (
            0.35 * metrics["success"]
            + 0.25 * metrics["filter_works"]
            + 0.25 * metrics["collapse_works"]
            + 0.15 * metrics["speed"]
        )
        gates["all_ok"] = ok and hits > 0 and collapsed < raw_n
    elif case_id == "cold_start_storage":
        budget = BUDGETS_MS[case_id]
        metrics["success"] = 1.0 if ok else 0.0
        metrics["speed"] = _speed_score(ms_f, budget) if ok else 0.0
        composite = 0.55 * metrics["success"] + 0.45 * metrics["speed"]
        gates["all_ok"] = ok
    elif case_id == "history_snapshot_heuristics":
        budget = BUDGETS_MS[case_id]
        metrics["success"] = 1.0 if ok else 0.0
        metrics["speed"] = _speed_score(ms_f, budget) if ok else 0.0
        composite = 0.85 * metrics["success"] + 0.15 * metrics["speed"]
        gates["all_ok"] = ok
    else:
        metrics["success"] = 1.0 if ok else 0.0
        composite = metrics["success"]
        gates["all_ok"] = ok

    return {
        "case_id": case_id,
        "ok": ok and gates.get("all_ok", ok),
        "composite": round(composite, 4),
        "duration_ms": ms_f,
        "metrics": {k: round(v, 4) for k, v in metrics.items()},
        "gates": gates,
        "raw": {
            k: row.get(k)
            for k in ("bytes", "engine", "error", "skip_generative", "metrics_raw")
            if k in row
        },
    }


def score_all(results_path: Path | None = None) -> dict:
    path = results_path or RESULTS
    if not path.is_file():
        return {
            "ok": False,
            "n_cases": 0,
            "n_scored": 0,
            "mean_composite": None,
            "cases": [],
            "gate_fails": [{"case_id": "_", "reason": f"missing:{path}"}],
            "error": f"missing harness results: {path}",
        }

    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get("cases") or []
    scored = [score_case(r) for r in rows]
    ok_rows = [c for c in scored if c.get("composite") is not None]
    mean = (
        round(sum(c["composite"] for c in ok_rows) / len(ok_rows), 4)
        if ok_rows
        else None
    )
    gate_fails = []
    for c in scored:
        g = c.get("gates") or {}
        if not g.get("all_ok", False):
            gate_fails.append(
                {
                    "case_id": c["case_id"],
                    "gates": g,
                    "composite": c.get("composite"),
                }
            )

    return {
        "ok": bool(data.get("ok")) and not gate_fails and mean is not None,
        "n_cases": len(rows),
        "n_scored": len(ok_rows),
        "mean_composite": mean,
        "cases": scored,
        "gate_fails": gate_fails,
        "notes": data.get("notes") or [],
        "budgets_ms": BUDGETS_MS,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Score app improve-loop harness results")
    p.add_argument("--json", action="store_true", help="Print full JSON")
    p.add_argument(
        "--results",
        type=Path,
        default=None,
        help="Path to harness_results.json",
    )
    args = p.parse_args(argv)
    scored = score_all(args.results)
    if args.json:
        print(json.dumps(scored, indent=2))
    else:
        print(
            json.dumps(
                {
                    "ok": scored.get("ok"),
                    "mean_composite": scored.get("mean_composite"),
                    "n_scored": scored.get("n_scored"),
                    "gate_fails": scored.get("gate_fails"),
                },
                indent=2,
            )
        )
        for c in scored.get("cases") or []:
            print(
                f"  {c['case_id']}: composite={c['composite']} "
                f"ok={c['ok']} metrics={c.get('metrics')}",
                flush=True,
            )
    return 0 if scored.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
