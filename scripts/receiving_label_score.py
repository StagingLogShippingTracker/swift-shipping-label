#!/usr/bin/env python3
"""Score Receiving Label synthetic PNG renders (improve-loop metrics).

Receiving differs from Shipping:
  - Full-width stack (no two-column gutter metric)
  - Yellow SO pill (recvSoBg) with under-pill hairline showRule=True (SO→PM)
  - Received band + optional red instructions alert

Do NOT apply Shipping SO/Contact lock (showRule false).

Usage (repo root):
  python scripts/receiving_label_score.py
  python scripts/receiving_label_score.py --case baseline_receiving_sample
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / "qa_receiving" / "synthetic"
RENDERS = SYN / "renders"
DEBUG = SYN / "layout_debug"
MANIFEST = SYN / "manifest.json"

# Yellow Receiving SO pill (~#FFEB3B)
YELLOW_CENTER = np.array([255, 235, 59], dtype=np.float32)

# Red instructions alert (~#E53935)
ALERT_LO = np.array([200, 40, 40], dtype=np.float32)
ALERT_HI = np.array([245, 90, 80], dtype=np.float32)

# Cream received / notes band (~#F7F0D8)
CREAM_CENTER = np.array([247, 240, 216], dtype=np.float32)

# Orange Swift bars
ORANGE_LO = np.array([170, 50, 25], dtype=np.float32)
ORANGE_HI = np.array([230, 110, 80], dtype=np.float32)

# C8 hairline
HAIRLINE_LO = 185
HAIRLINE_HI = 215


def _clamp01(x: float) -> float:
    return float(max(0.0, min(1.0, x)))


def _load_rgb(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float32)


def _is_yellow(rgb: np.ndarray) -> np.ndarray:
    return np.all(np.abs(rgb - YELLOW_CENTER) < 28.0, axis=-1)


def _is_alert(rgb: np.ndarray) -> np.ndarray:
    return np.all((rgb >= ALERT_LO) & (rgb <= ALERT_HI), axis=-1)


def _is_cream(rgb: np.ndarray) -> np.ndarray:
    return np.all(np.abs(rgb - CREAM_CENTER) < 18.0, axis=-1)


def _is_orange(rgb: np.ndarray) -> np.ndarray:
    return np.all((rgb >= ORANGE_LO) & (rgb <= ORANGE_HI), axis=-1)


def _is_dark(rgb: np.ndarray, thr: float = 45.0) -> np.ndarray:
    return np.all(rgb < thr, axis=-1)


def _is_hairline_gray(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    near = (np.abs(r - g) < 10) & (np.abs(g - b) < 10)
    mid = (r >= HAIRLINE_LO) & (r <= HAIRLINE_HI)
    return near & mid


def _ink_mask(rgb: np.ndarray, white_thr: float = 245.0) -> np.ndarray:
    return np.any(rgb < white_thr, axis=-1)


def _find_yellow_pill(rgb: np.ndarray) -> tuple[int, int] | None:
    """Longest yellow run in mid page (full-width SO pill)."""
    h, w, _ = rgb.shape
    x0, x1 = int(w * 0.08), int(w * 0.92)
    y0, y1 = int(h * 0.35), int(h * 0.82)
    col = rgb[y0:y1, x0:x1]
    yel = _is_yellow(col)
    counts = yel.sum(axis=1)
    thr = max(120, int((x1 - x0) * 0.35))
    best = None
    run_s = -1
    for i, c in enumerate(counts):
        if c > thr:
            if run_s < 0:
                run_s = i
        elif run_s >= 0:
            run_e = i - 1
            if best is None or (run_e - run_s) > (best[1] - best[0]):
                best = (run_s, run_e)
            run_s = -1
    if run_s >= 0:
        run_e = len(counts) - 1
        if best is None or (run_e - run_s) > (best[1] - best[0]):
            best = (run_s, run_e)
    if best is None:
        return None
    return y0 + best[0], y0 + best[1]


def score_png(png_path: Path, layout: dict | None = None) -> dict:
    rgb = _load_rgb(png_path)
    h, w, _ = rgb.shape
    metrics: dict[str, float] = {}
    details: dict = {"png_w": w, "png_h": h}

    # --- yellow SO pill present ---
    pill = _find_yellow_pill(rgb)
    details["yellow_pill"] = pill
    metrics["so_pill_present"] = 1.0 if pill is not None else 0.0

    # --- so_show_rule (Receiving MUST have under-pill hairline) ---
    show_rule = layout.get("so_show_rule") if layout else None
    hairline_rows = 0
    if pill is not None:
        x0, x1 = int(w * 0.10), int(w * 0.90)
        y_scan0 = pill[1]
        y_scan1 = min(h - 1, pill[1] + 12)
        for y in range(y_scan0, y_scan1):
            row = rgb[y, x0:x1]
            if int(_is_hairline_gray(row).sum()) > 200:
                hairline_rows += 1
        details["hairline_rows_under_pill"] = hairline_rows
        if show_rule is True or (show_rule is None and hairline_rows > 0):
            metrics["so_rule_present"] = 1.0 if hairline_rows > 0 else 0.35
        else:
            metrics["so_rule_present"] = 0.0 if hairline_rows == 0 else 0.5
    else:
        if show_rule is True and layout and layout.get("so_rule_y") is not None:
            metrics["so_rule_present"] = 0.7  # layout says rule; PNG miss
        else:
            metrics["so_rule_present"] = 0.0

    # --- PM value ink below SO pill ---
    if pill is not None:
        pm_y0 = pill[1] + 8
        pm_y1 = min(h - 1, pill[1] + int(h * 0.12))
        pm_zone = rgb[pm_y0:pm_y1, int(w * 0.15) : int(w * 0.85)]
        pm_dark = float(_is_dark(pm_zone).mean()) if pm_zone.size else 0.0
        details["pm_dark_density"] = round(pm_dark, 4)
        metrics["pm_visibility"] = _clamp01(pm_dark / 0.02)
    else:
        metrics["pm_visibility"] = 0.3

    # --- received band (cream) near lower third ---
    cream = _is_cream(rgb)
    band = cream[int(h * 0.72) : int(h * 0.92), int(w * 0.06) : int(w * 0.94)]
    cream_dens = float(band.mean()) if band.size else 0.0
    details["received_band_density"] = round(cream_dens, 4)
    metrics["received_band"] = _clamp01(cream_dens / 0.08)

    # --- instructions alert (red) when expected — search just above yellow SO ---
    has_instr = bool(layout.get("has_instructions")) if layout else True
    alert = _is_alert(rgb)
    if pill is not None:
        a_y1 = max(1, pill[0] - 4)
        a_y0 = max(0, pill[0] - int(h * 0.22))
    else:
        a_y0, a_y1 = int(h * 0.22), int(h * 0.58)
    alert_band = alert[a_y0:a_y1, int(w * 0.08) : int(w * 0.92)]
    # Exclude orange bumper false-positives: require strong red (R>>G,B).
    if alert_band.size:
        region = rgb[a_y0:a_y1, int(w * 0.08) : int(w * 0.92)]
        r, g, b = region[..., 0], region[..., 1], region[..., 2]
        strong = (r > 200) & (g < 100) & (b < 100) & (r > g + 80) & (r > b + 80)
        alert_dens = float(strong.mean())
    else:
        alert_dens = 0.0
    details["alert_density"] = round(alert_dens, 4)
    details["alert_band_y"] = [a_y0, a_y1]
    details["has_instructions"] = has_instr
    if has_instr:
        metrics["instructions_alert"] = _clamp01(alert_dens / 0.015)
    else:
        # Empty instructions should NOT paint a large red box.
        metrics["instructions_alert"] = _clamp01(1.0 - alert_dens / 0.015)

    # --- receiving chip region (peach/yellow-ish under logos) ---
    chip = rgb[int(h * 0.10) : int(h * 0.18), int(w * 0.08) : int(w * 0.35)]
    chip_yel = float(_is_yellow(chip).mean()) if chip.size else 0.0
    # Chip uses soBg peach; also accept any mid-tone fill with dark text nearby.
    chip_ink = float(_ink_mask(chip).mean()) if chip.size else 0.0
    details["chip_ink"] = round(chip_ink, 4)
    details["chip_yellow"] = round(chip_yel, 4)
    metrics["receiving_chip"] = _clamp01(max(chip_ink / 0.08, chip_yel / 0.02))

    # --- swift_logo_clearance (same pink-gap idea as shipping) ---
    ink = _ink_mask(rgb)
    y_top, y_bot = int(h * 0.02), int(h * 0.18)
    header = ink[y_top:y_bot, :]
    col_sums = header.sum(axis=0)
    thr = max(3, int((y_bot - y_top) * 0.12))
    swift_left = None
    in_blob = False
    blob_left = None
    for x in range(w - 4, int(w * 0.50), -1):
        if col_sums[x] >= thr:
            if not in_blob:
                in_blob = True
            blob_left = x
        elif in_blob:
            break
    if blob_left is not None:
        swift_left = blob_left
    details["swift_left_x"] = swift_left
    if swift_left is not None and swift_left > 30:
        gap_w = max(16, int(w * 0.015))
        gap_x0 = max(0, swift_left - gap_w)
        gap_density = float(header[:, gap_x0:swift_left].mean())
        swift_density = float(
            header[:, swift_left : min(w, swift_left + int(w * 0.28))].mean()
        )
    else:
        gap_density = float(header[:, int(w * 0.60) : int(w * 0.64)].mean())
        swift_density = float(header[:, int(w * 0.64) : int(w * 0.96)].mean())
    details["gap_density"] = round(gap_density, 4)
    details["swift_density"] = round(swift_density, 4)
    gap_score = _clamp01(1.0 - max(0.0, gap_density - 0.10) / 0.30)
    swift_present = 1.0 if swift_density > 0.04 else 0.3
    metrics["swift_logo_clearance"] = _clamp01(0.75 * gap_score + 0.25 * swift_present)

    # --- margin integrity ---
    hard = np.zeros((h, w), dtype=bool)
    hx, hy = max(4, int(w * 0.012)), max(4, int(h * 0.012))
    hard[:hy, :] = True
    hard[-hy:, :] = True
    hard[:, :hx] = True
    hard[:, -hx:] = True
    bleed = float(ink[hard].mean()) if hard.any() else 0.0
    details["margin_bleed"] = round(bleed, 5)
    metrics["margin_integrity"] = _clamp01(1.0 - bleed / 0.08)

    # --- structure bars (orange bumpers) ---
    orange = _is_orange(rgb)
    head_band = orange[int(h * 0.00) : int(h * 0.06), int(w * 0.05) : int(w * 0.95)]
    foot_band = orange[int(h * 0.94) : int(h * 1.0), int(w * 0.05) : int(w * 0.95)]
    # Also check under-logo orange rule ~0.12–0.20
    mid_rule = orange[int(h * 0.12) : int(h * 0.20), int(w * 0.05) : int(w * 0.95)]
    head_ok = float(head_band.mean()) > 0.001 or float(mid_rule.mean()) > 0.002
    foot_ok = float(foot_band.mean()) > 0.001
    details["orange_header"] = bool(head_ok)
    details["orange_footer"] = bool(foot_ok)
    metrics["structure_bars"] = (0.6 if head_ok else 0.0) + (0.4 if foot_ok else 0.0)

    # --- overcrowding: body ink density soft ceiling ---
    body = ink[int(h * 0.18) : int(h * 0.70), int(w * 0.08) : int(w * 0.92)]
    body_dens = float(body.mean()) if body.size else 0.0
    details["body_ink_density"] = round(body_dens, 4)
    # Typical receiving ~0.10–0.36; punish extreme fill only.
    if body_dens <= 0.36:
        metrics["overcrowding"] = 1.0
    else:
        metrics["overcrowding"] = _clamp01(1.0 - (body_dens - 0.36) / 0.25)

    composite = float(np.mean(list(metrics.values()))) if metrics else 0.0
    return {
        "metrics": {k: round(v, 4) for k, v in metrics.items()},
        "composite": round(composite, 4),
        "details": details,
    }


def evaluate_gates(layout: dict | None, metrics: dict) -> dict:
    """Receiving gates: SO under-pill rule ON; structure present."""
    gates: dict = {
        "so_show_rule_ok": None,
        "so_pill_ok": None,
        "structure_ok": None,
        "received_band_ok": None,
    }
    if layout:
        show = layout.get("so_show_rule")
        if show is not None:
            gates["so_show_rule_ok"] = show is True
        elif layout.get("so_rule_y") is not None:
            gates["so_show_rule_ok"] = True
    if "so_pill_present" in metrics:
        gates["so_pill_ok"] = metrics["so_pill_present"] >= 0.99
    if "structure_bars" in metrics:
        gates["structure_ok"] = metrics["structure_bars"] >= 0.9
    if "received_band" in metrics:
        gates["received_band_ok"] = metrics["received_band"] >= 0.5
    present = [v for v in gates.values() if v is not None]
    gates["all_ok"] = bool(present) and all(v is True for v in present)
    return gates


def score_case(case_id: str) -> dict:
    png = RENDERS / f"{case_id}.png"
    layout_path = DEBUG / f"{case_id}.json"
    layout = None
    if layout_path.is_file():
        layout = json.loads(layout_path.read_text(encoding="utf-8"))
    if not png.is_file():
        return {
            "case_id": case_id,
            "ok": False,
            "note": "missing_png",
            "composite": None,
            "metrics": {},
            "gates": {},
        }
    scored = score_png(png, layout)
    gates = evaluate_gates(layout, scored["metrics"])
    return {
        "case_id": case_id,
        "ok": True,
        "note": "ok",
        "composite": scored["composite"],
        "metrics": scored["metrics"],
        "gates": gates,
        "details": scored["details"],
        "png": str(png.relative_to(ROOT)).replace("\\", "/"),
        "layout_debug": str(layout_path.relative_to(ROOT)).replace("\\", "/")
        if layout_path.is_file()
        else None,
    }


def score_all(case_ids: list[str] | None = None) -> dict:
    if case_ids is None:
        if MANIFEST.is_file():
            man = json.loads(MANIFEST.read_text(encoding="utf-8"))
            case_ids = [c["case_id"] for c in man.get("cases") or []]
        else:
            case_ids = sorted(p.stem for p in RENDERS.glob("*.png"))
    rows = [score_case(cid) for cid in case_ids]
    scored = [r for r in rows if r.get("ok") and r.get("composite") is not None]
    mean = (
        round(float(np.mean([r["composite"] for r in scored])), 4) if scored else None
    )
    gate_fails = [
        {
            "case_id": r["case_id"],
            "gates": {k: v for k, v in (r.get("gates") or {}).items() if v is False},
        }
        for r in scored
        if r.get("gates") and not r["gates"].get("all_ok", True)
    ]
    return {
        "ok": len(gate_fails) == 0 and mean is not None,
        "n_cases": len(rows),
        "n_scored": len(scored),
        "mean_composite": mean,
        "cases": rows,
        "gate_fails": gate_fails,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Score Receiving Label improve-loop renders")
    p.add_argument("--case", action="append", default=None)
    args = p.parse_args(argv)
    out = score_all(args.case)
    print(json.dumps(out, indent=2))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
