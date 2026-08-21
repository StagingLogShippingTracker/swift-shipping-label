#!/usr/bin/env python3
"""Score Shipping Label synthetic PNG renders (improve-loop metrics).

Metrics are 0–1 (higher better). Composite is the mean of available metrics.
Approved SO/Contact geometry is also reported as hard gates (not softened by
changing layout constants — adjust bands here if the approved sample fails).

Usage (repo root):
  python scripts/shipping_label_score.py
  python scripts/shipping_label_score.py --case baseline_dual_arc_trialta
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / "qa_shipping" / "synthetic"
RENDERS = SYN / "renders"
DEBUG = SYN / "layout_debug"
MANIFEST = SYN / "manifest.json"

# --- Approved SO/Contact bands (PDF pt). Match shipping-label-approved-layout.
PILL_TO_CONTACT_LABEL_PT = (9.0, 13.0)  # afterPillGap lock ≈ 11
NAME_CLEAR_PIECE_PT = 8.0
# PNG @2×: pill bottom → CONTACT micro-label (~18–26 px for 9–13 pt)
PILL_TO_CONTACT_LABEL_PX = (18.0, 26.0)

# Orange Swift brand bar (~#CE4E30)
ORANGE_LO = np.array([170, 50, 25], dtype=np.float32)
ORANGE_HI = np.array([230, 110, 80], dtype=np.float32)

# SO peach pill (~#F8EBE7)
PEACH_CENTER = np.array([248, 235, 231], dtype=np.float32)

# C8 hairline (~#C8C8C8)
HAIRLINE_LO = 185
HAIRLINE_HI = 215


def _clamp01(x: float) -> float:
    return float(max(0.0, min(1.0, x)))


def _band_score(value: float, lo: float, hi: float, soft: float = 4.0) -> float:
    """1.0 inside [lo, hi]; linear falloff outside over `soft` units."""
    if lo <= value <= hi:
        return 1.0
    if value < lo:
        return _clamp01(1.0 - (lo - value) / soft)
    return _clamp01(1.0 - (value - hi) / soft)


def _load_rgb(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float32)


def _is_peach(rgb: np.ndarray) -> np.ndarray:
    return np.all(np.abs(rgb - PEACH_CENTER) < 12.0, axis=-1)


def _is_dark(rgb: np.ndarray, thr: float = 40.0) -> np.ndarray:
    return np.all(rgb < thr, axis=-1)


def _is_orange(rgb: np.ndarray) -> np.ndarray:
    return np.all((rgb >= ORANGE_LO) & (rgb <= ORANGE_HI), axis=-1)


def _is_hairline_gray(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    near = (np.abs(r - g) < 10) & (np.abs(g - b) < 10)
    mid = (r >= HAIRLINE_LO) & (r <= HAIRLINE_HI)
    return near & mid


def _find_peach_pill(rgb: np.ndarray) -> tuple[int, int] | None:
    """Return (start_y, end_y) of longest peach run in right column."""
    h, w, _ = rgb.shape
    x0, x1 = int(w * 0.58), int(w * 0.92)
    y0, y1 = int(h * 0.35), int(h * 0.85)
    col = rgb[y0:y1, x0:x1]
    peach = _is_peach(col)
    counts = peach.sum(axis=1)
    thr = max(80, int((x1 - x0) * 0.25))
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


def _first_dark_row(
    rgb: np.ndarray, y_start: int, y_end: int, x0: float, x1: float, min_px: int = 40
) -> int | None:
    h, w, _ = rgb.shape
    xa, xb = int(w * x0), int(w * x1)
    y_end = min(y_end, h)
    for y in range(max(0, y_start), y_end):
        if int(_is_dark(rgb[y, xa:xb]).sum()) > min_px:
            return y
    return None


def _ink_mask(rgb: np.ndarray, white_thr: float = 245.0) -> np.ndarray:
    return np.any(rgb < white_thr, axis=-1)


def score_png(png_path: Path, layout: dict | None = None) -> dict:
    rgb = _load_rgb(png_path)
    h, w, _ = rgb.shape
    metrics: dict[str, float] = {}
    details: dict = {"png_w": w, "png_h": h}

    # --- so_contact_gap (PNG peach → next dark in right col ≈ CONTACT label)
    peach = _find_peach_pill(rgb)
    if peach is not None:
        _, peach_end = peach
        details["peach_end_y"] = peach_end
        label_y = _first_dark_row(rgb, peach_end + 1, peach_end + 80, 0.58, 0.92, 25)
        details["contact_label_y_png"] = label_y
        if label_y is not None:
            gap_px = float(label_y - peach_end)
            details["so_contact_gap_px"] = gap_px
            metrics["so_contact_gap"] = _band_score(
                gap_px, PILL_TO_CONTACT_LABEL_PX[0], PILL_TO_CONTACT_LABEL_PX[1], soft=8.0
            )
        else:
            metrics["so_contact_gap"] = 0.0
    else:
        # Fall back to layout_debug PDF coords when peach detection fails.
        if layout and layout.get("pill_to_contact_label_pt") is not None:
            gap_pt = float(layout["pill_to_contact_label_pt"])
            details["so_contact_gap_pt"] = gap_pt
            metrics["so_contact_gap"] = _band_score(
                gap_pt, PILL_TO_CONTACT_LABEL_PT[0], PILL_TO_CONTACT_LABEL_PT[1], soft=4.0
            )
        else:
            metrics["so_contact_gap"] = 0.0

    # Prefer layout_debug for precise gate (PDF space).
    if layout and layout.get("pill_to_contact_label_pt") is not None:
        gap_pt = float(layout["pill_to_contact_label_pt"])
        details["so_contact_gap_pt"] = gap_pt
        # Blend: layout dump is authoritative for the lock.
        metrics["so_contact_gap"] = _band_score(
            gap_pt, PILL_TO_CONTACT_LABEL_PT[0], PILL_TO_CONTACT_LABEL_PT[1], soft=4.0
        )

    # --- contact_clear_piece
    if layout and layout.get("name_clear_piece_pt") is not None:
        clear_pt = float(layout["name_clear_piece_pt"])
        details["name_clear_piece_pt"] = clear_pt
        if clear_pt >= NAME_CLEAR_PIECE_PT:
            metrics["contact_clear_piece"] = 1.0
        else:
            metrics["contact_clear_piece"] = _clamp01(clear_pt / NAME_CLEAR_PIECE_PT)
    else:
        # PNG heuristic: dark name below peach, soft rule band below name.
        if peach is not None:
            name_y = _first_dark_row(
                rgb, peach[1] + 20, int(h * 0.92), 0.58, 0.92, 40
            )
            details["contact_name_y_png"] = name_y
            # Piece-band soft rule ~ mid-lower page; score 1 if name is above 0.88h
            if name_y is not None and name_y < int(h * 0.88):
                metrics["contact_clear_piece"] = 1.0
            elif name_y is not None:
                metrics["contact_clear_piece"] = 0.4
            else:
                metrics["contact_clear_piece"] = 0.0
        else:
            metrics["contact_clear_piece"] = 0.5

    # --- no_so_hairline (no C8 rule between peach and contact name)
    if peach is not None:
        name_y = details.get("contact_name_y_png") or _first_dark_row(
            rgb, peach[1] + 20, int(h * 0.92), 0.58, 0.92, 40
        )
        hairline_rows = 0
        if name_y is not None:
            x0, x1 = int(w * 0.58), int(w * 0.92)
            for y in range(peach[1] + 1, name_y):
                row = rgb[y, x0:x1]
                if int(_is_hairline_gray(row).sum()) > 150:
                    hairline_rows += 1
        details["hairline_rows"] = hairline_rows
        show_rule = layout.get("so_show_rule") if layout else None
        if show_rule is True:
            metrics["no_so_hairline"] = 0.0
        elif hairline_rows > 0:
            metrics["no_so_hairline"] = _clamp01(1.0 - hairline_rows / 3.0)
        else:
            metrics["no_so_hairline"] = 1.0
    else:
        if layout and layout.get("so_show_rule") is False:
            metrics["no_so_hairline"] = 1.0
        elif layout and layout.get("so_show_rule") is True:
            metrics["no_so_hairline"] = 0.0
        else:
            metrics["no_so_hairline"] = 0.5

    # --- swift_logo_clearance: empty pink gap just left of Swift (right header)
    # Dual logos may fill most of the left frame; only the strip immediately
    # before Swift must stay clear (customerLogoToSwiftGap ≈ 12pt → ~24px @2×).
    ink = _ink_mask(rgb)
    y_top, y_bot = int(h * 0.02), int(h * 0.18)
    header = ink[y_top:y_bot, :]
    col_sums = header.sum(axis=0)
    thr = max(3, int((y_bot - y_top) * 0.12))
    # Left edge of rightmost header ink blob (Swift), searched from page right.
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
        gap_w = max(16, int(w * 0.015))  # ~24px @1584
        gap_x0 = max(0, swift_left - gap_w)
        gap_density = float(header[:, gap_x0:swift_left].mean())
        swift_density = float(
            header[:, swift_left : min(w, swift_left + int(w * 0.28))].mean()
        )
    else:
        gap_x0, gap_x1 = int(w * 0.60), int(w * 0.64)
        gap_density = float(header[:, gap_x0:gap_x1].mean()) if gap_x1 > gap_x0 else 0.0
        swift_density = float(header[:, int(w * 0.64) : int(w * 0.96)].mean())
    details["gap_density"] = round(gap_density, 4)
    details["swift_density"] = round(swift_density, 4)
    # Allow faint AA in the gap; punish only real encroachment into pink strip.
    gap_score = _clamp01(1.0 - max(0.0, gap_density - 0.10) / 0.30)
    swift_present = 1.0 if swift_density > 0.04 else 0.3
    metrics["swift_logo_clearance"] = _clamp01(0.75 * gap_score + 0.25 * swift_present)

    # --- margin_integrity: little ink in outer margin strips
    mx_px = max(8, int(w * 0.04))  # ~0.52" at 2× ≈ 75px; use softer band
    my_px = max(8, int(h * 0.035))
    border = np.zeros((h, w), dtype=bool)
    border[:my_px, :] = True
    border[-my_px:, :] = True
    border[:, :mx_px] = True
    border[:, -mx_px:] = True
    # Exclude intentional orange bars that sit near content edges but inside mx/my.
    # Score only extreme outer 2% as hard margin.
    hard = np.zeros((h, w), dtype=bool)
    hx, hy = max(4, int(w * 0.012)), max(4, int(h * 0.012))
    hard[:hy, :] = True
    hard[-hy:, :] = True
    hard[:, :hx] = True
    hard[:, -hx:] = True
    bleed = float(ink[hard].mean()) if hard.any() else 0.0
    details["margin_bleed"] = round(bleed, 5)
    metrics["margin_integrity"] = _clamp01(1.0 - bleed / 0.08)

    # --- column_separation: center gutter should be mostly empty of body ink
    gutter_x0, gutter_x1 = int(w * 0.48), int(w * 0.52)
    body_y0, body_y1 = int(h * 0.22), int(h * 0.78)
    gutter = ink[body_y0:body_y1, gutter_x0:gutter_x1]
    g_density = float(gutter.mean()) if gutter.size else 0.0
    details["gutter_density"] = round(g_density, 4)
    metrics["column_separation"] = _clamp01(1.0 - g_density / 0.25)

    # --- structure_bars: orange header + footer bars present
    orange = _is_orange(rgb)
    # Header bar under logos ~ y 0.14–0.22; footer near bottom content
    head_band = orange[int(h * 0.12) : int(h * 0.22), int(w * 0.05) : int(w * 0.95)]
    foot_band = orange[int(h * 0.82) : int(h * 0.96), int(w * 0.05) : int(w * 0.95)]
    head_ok = float(head_band.mean()) > 0.002 if head_band.size else False
    foot_ok = float(foot_band.mean()) > 0.001 if foot_band.size else False
    details["orange_header"] = bool(head_ok)
    details["orange_footer"] = bool(foot_ok)
    metrics["structure_bars"] = (1.0 if head_ok else 0.0) * 0.6 + (
        1.0 if foot_ok else 0.0
    ) * 0.4

    composite = float(np.mean(list(metrics.values()))) if metrics else 0.0
    return {
        "metrics": {k: round(v, 4) for k, v in metrics.items()},
        "composite": round(composite, 4),
        "details": details,
    }


def evaluate_gates(layout: dict | None, metrics: dict) -> dict:
    """Hard gates for approved SO/Contact lock."""
    gates = {
        "after_pill_gap_ok": None,
        "so_show_rule_ok": None,
        "contact_clear_piece_ok": None,
        "no_so_hairline_ok": None,
    }
    if layout:
        gap = layout.get("pill_to_contact_label_pt")
        if gap is not None:
            g = float(gap)
            gates["after_pill_gap_ok"] = PILL_TO_CONTACT_LABEL_PT[0] <= g <= PILL_TO_CONTACT_LABEL_PT[1]
        show = layout.get("so_show_rule")
        if show is not None:
            gates["so_show_rule_ok"] = show is False
        clear = layout.get("name_clear_piece_pt")
        if clear is not None:
            gates["contact_clear_piece_ok"] = float(clear) >= NAME_CLEAR_PIECE_PT
    if "no_so_hairline" in metrics:
        gates["no_so_hairline_ok"] = metrics["no_so_hairline"] >= 0.99
    gates["all_ok"] = all(v is True for v in gates.values() if v is not None) and any(
        v is not None for v in gates.values()
    )
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
        "n_cases": len(rows),
        "n_scored": len(scored),
        "mean_composite": mean,
        "cases": rows,
        "gate_fails": gate_fails,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Score shipping label synthetic renders")
    p.add_argument("--case", action="append", help="Case id (repeatable)")
    p.add_argument(
        "--json-out",
        type=Path,
        help="Optional path to write full score JSON",
    )
    args = p.parse_args(argv)
    result = score_all(args.case)
    print(json.dumps({k: result[k] for k in ("n_cases", "n_scored", "mean_composite", "gate_fails")}, indent=2))
    worst = sorted(
        [r for r in result["cases"] if r.get("composite") is not None],
        key=lambda r: r["composite"],
    )[:8]
    print("\nLowest composites:")
    for r in worst:
        print(f"  {r['case_id']}: {r['composite']}  {r.get('metrics')}")
    if args.json_out:
        args.json_out.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
