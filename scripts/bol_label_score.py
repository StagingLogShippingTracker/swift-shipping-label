#!/usr/bin/env python3
"""Score BOL synthetic PNG renders (improve-loop metrics).

Metrics are 0–1 (higher better). Composite is the mean of available metrics.
North star: baseline_sample / filled/qa_bol_preview/bol_preview_latest.png.

Usage (repo root):
  python scripts/bol_label_score.py
  python scripts/bol_label_score.py --case baseline_sample
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / "qa_bol" / "synthetic"
RENDERS = SYN / "renders"
DEBUG = SYN / "layout_debug"
MANIFEST = SYN / "manifest.json"

# Orange Swift brand (~#CE4E30)
ORANGE_LO = np.array([170, 50, 25], dtype=np.float32)
ORANGE_HI = np.array([230, 110, 80], dtype=np.float32)


def _clamp01(x: float) -> float:
    return float(max(0.0, min(1.0, x)))


def _load_rgb(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float32)


def _is_orange(rgb: np.ndarray) -> np.ndarray:
    return np.all((rgb >= ORANGE_LO) & (rgb <= ORANGE_HI), axis=-1)


def _is_dark(rgb: np.ndarray, thr: float = 55.0) -> np.ndarray:
    return np.all(rgb < thr, axis=-1)


def _ink_mask(rgb: np.ndarray, white_thr: float = 245.0) -> np.ndarray:
    return np.any(rgb < white_thr, axis=-1)


def _pt_to_px(layout: dict, x: float, y: float) -> tuple[float, float]:
    """PDF bottom-left pt → PNG top-left px (@ layout png.scale)."""
    page = layout.get("page_format") or {}
    png = layout.get("png") or {}
    page_w = float(page.get("width") or 612.0)
    page_h = float(page.get("height") or 792.0)
    scale = float(png.get("scale") or 2.0)
    png_w = float(png.get("width") or page_w * scale)
    png_h = float(png.get("height") or page_h * scale)
    sx = png_w / page_w
    sy = png_h / page_h
    return x * sx, (page_h - y) * sy


def _rect_px(layout: dict, rect: dict | None) -> tuple[int, int, int, int] | None:
    if not rect:
        return None
    x = float(rect["x"])
    y = float(rect["y"])
    w = float(rect["w"])
    h = float(rect["h"])
    x0, y_top = _pt_to_px(layout, x, y + h)
    x1, y_bot = _pt_to_px(layout, x + w, y)
    return (
        int(max(0, min(x0, x1))),
        int(max(0, min(y_top, y_bot))),
        int(max(x0, x1)),
        int(max(y_top, y_bot)),
    )


def _density(mask: np.ndarray, box: tuple[int, int, int, int] | None) -> float:
    if box is None:
        return 0.0
    h, w = mask.shape
    x0, y0, x1, y1 = box
    x0, x1 = max(0, x0), min(w, x1)
    y0, y1 = max(0, y0), min(h, y1)
    if x1 <= x0 or y1 <= y0:
        return 0.0
    region = mask[y0:y1, x0:x1]
    return float(region.mean()) if region.size else 0.0


def score_png(png_path: Path, layout: dict | None = None) -> dict:
    rgb = _load_rgb(png_path)
    h, w, _ = rgb.shape
    metrics: dict[str, float] = {}
    details: dict = {"png_w": w, "png_h": h}
    ink = _ink_mask(rgb)
    dark = _is_dark(rgb)
    orange = _is_orange(rgb)

    # --- structure: orange title bar present
    if layout and layout.get("title_bar"):
        box = _rect_px(layout, layout["title_bar"])
        o_den = _density(orange, box)
        details["title_orange_density"] = round(o_den, 4)
        metrics["structure"] = 1.0 if o_den > 0.15 else _clamp01(o_den / 0.15)
    else:
        # Fallback band under header logos (~0.10–0.18 of page)
        band = orange[int(h * 0.08) : int(h * 0.18), int(w * 0.05) : int(w * 0.95)]
        o_den = float(band.mean()) if band.size else 0.0
        details["title_orange_density"] = round(o_den, 4)
        metrics["structure"] = 1.0 if o_den > 0.02 else _clamp01(o_den / 0.02)

    # --- margin_integrity
    hx, hy = max(4, int(w * 0.01)), max(4, int(h * 0.01))
    hard = np.zeros((h, w), dtype=bool)
    hard[:hy, :] = True
    hard[-hy:, :] = True
    hard[:, :hx] = True
    hard[:, -hx:] = True
    bleed = float(ink[hard].mean()) if hard.any() else 0.0
    details["margin_bleed"] = round(bleed, 5)
    metrics["margin_integrity"] = _clamp01(1.0 - bleed / 0.08)

    # --- logo_swift_clearance / logo_probill_clearance (debug rects preferred)
    logo_boxes = (layout or {}).get("customer_logo_boxes") or []
    frame = (layout or {}).get("customer_logo_frame")
    swift = (layout or {}).get("swift_rect")
    probill = (layout or {}).get("probill_rect")
    gap_pt = float((layout or {}).get("customer_to_probill_gap") or 12.0)

    def _clearance_ok(logo: dict, other: dict | None, min_gap: float) -> float:
        if not other or float(other.get("w") or 0) <= 0:
            return 1.0
        lx1 = float(logo["x"]) + float(logo["w"])
        ox0 = float(other["x"])
        # Horizontal gap (logo left of other). Soft if overlapping vertically.
        ly0, ly1 = float(logo["y"]), float(logo["y"]) + float(logo["h"])
        oy0, oy1 = float(other["y"]), float(other["y"]) + float(other["h"])
        vert_overlap = not (ly1 < oy0 or oy1 < ly0)
        if not vert_overlap:
            return 1.0
        gap = ox0 - lx1
        details.setdefault("logo_gaps", []).append(round(gap, 2))
        if gap >= min_gap - 0.5:
            return 1.0
        if gap >= 0:
            return _clamp01(gap / max(min_gap, 1.0))
        return _clamp01(1.0 + gap / max(min_gap, 1.0))  # overlap → low

    if logo_boxes and (swift or probill):
        swift_scores = [_clearance_ok(b, swift, gap_pt) for b in logo_boxes]
        prob_scores = [_clearance_ok(b, probill, gap_pt) for b in logo_boxes]
        metrics["logo_swift_clearance"] = float(np.mean(swift_scores)) if swift_scores else 1.0
        metrics["logo_probill_clearance"] = float(np.mean(prob_scores)) if prob_scores else 1.0
        # Frame must not extend into Probill/Swift.
        if frame and not frame.get("skipped"):
            fr = float(frame["x"]) + float(frame["w"])
            static_left = None
            if probill and swift:
                static_left = min(float(probill["x"]), float(swift["x"]))
            elif probill:
                static_left = float(probill["x"])
            elif swift:
                static_left = float(swift["x"])
            if static_left is not None:
                frame_gap = static_left - fr
                details["frame_to_static_gap"] = round(frame_gap, 2)
                if frame_gap < gap_pt - 0.5:
                    penalty = _clamp01(frame_gap / max(gap_pt, 1.0))
                    metrics["logo_probill_clearance"] = min(
                        metrics["logo_probill_clearance"], penalty
                    )
    else:
        # PNG heuristic: gap strip between left-header ink and right Swift blob.
        y_top, y_bot = int(h * 0.015), int(h * 0.12)
        header = ink[y_top:y_bot, :]
        col_sums = header.sum(axis=0)
        thr = max(3, int((y_bot - y_top) * 0.12))
        swift_left = None
        in_blob = False
        blob_left = None
        for x in range(w - 4, int(w * 0.45), -1):
            if col_sums[x] >= thr:
                if not in_blob:
                    in_blob = True
                blob_left = x
            elif in_blob:
                break
        if blob_left is not None:
            swift_left = blob_left
        details["swift_left_x"] = swift_left
        if swift_left is not None and swift_left > 40:
            gap_w = max(18, int(w * 0.018))
            gap_x0 = max(0, swift_left - gap_w)
            gap_density = float(header[:, gap_x0:swift_left].mean())
            metrics["logo_swift_clearance"] = _clamp01(
                1.0 - max(0.0, gap_density - 0.12) / 0.35
            )
        else:
            metrics["logo_swift_clearance"] = 0.7
        # Probill is left of Swift; score mid-header emptiness vs left logo.
        mid0, mid1 = int(w * 0.38), int(w * 0.55)
        mid_den = float(header[:, mid0:mid1].mean()) if mid1 > mid0 else 0.0
        details["probill_zone_density"] = round(mid_den, 4)
        # Probill has dashed border ink — allow moderate density.
        metrics["logo_probill_clearance"] = _clamp01(1.0 - max(0.0, mid_den - 0.35) / 0.45)

    # --- tracking_field_visibility
    track = (layout or {}).get("tracking_row") or {}
    cells = track.get("cells") or []
    field_vals = (layout or {}).get("field_values") or {}
    vis_scores: list[float] = []
    for cell in cells:
        key = cell.get("key") or ""
        non_empty = bool(cell.get("value_non_empty"))
        # Also trust field_values aliases.
        if not non_empty:
            aliases = {
                "order_num": ["order_num", "sales_order"],
                "packing_list": ["packing_list", "packing_slip"],
                "po_num": ["po_num"],
                "project": ["project"],
            }
            for a in aliases.get(key, [key]):
                if str(field_vals.get(a) or "").strip():
                    non_empty = True
                    break
        if not non_empty:
            continue
        box = _rect_px(layout or {}, cell.get("value_box") or cell)
        dens = _density(dark, box)
        details.setdefault("track_densities", {})[key] = round(dens, 4)
        # Empty-looking cell when value should show → fail.
        if dens < 0.004:
            vis_scores.append(0.0)
        elif dens < 0.015:
            vis_scores.append(_clamp01(dens / 0.015))
        else:
            vis_scores.append(1.0)
    if vis_scores:
        metrics["tracking_field_visibility"] = float(np.mean(vis_scores))
    else:
        # No expected values — neutral-good.
        metrics["tracking_field_visibility"] = 1.0

    # --- micro_value_gap_consistency (optional band around locked 3.0)
    gap = (layout or {}).get("micro_to_value_gap")
    if gap is not None:
        g = float(gap)
        details["micro_to_value_gap"] = g
        # Perfect at 3.0; soft falloff outside 2.5–3.5
        if 2.5 <= g <= 3.5:
            metrics["micro_value_gap_consistency"] = 1.0
        else:
            metrics["micro_value_gap_consistency"] = _clamp01(1.0 - abs(g - 3.0) / 3.0)

    # --- overcrowding / section overlap heuristics
    # Prefer layout Y order: title above tracking; logo frame below page top.
    overcrowding = 1.0
    if layout:
        title = layout.get("title_bar") or {}
        track_y = None
        if track.get("value_y") is not None:
            track_y = float(track["value_y"])
        title_y = float(title.get("y") or 0) if title else None
        if title_y is not None and track_y is not None:
            # PDF: higher y is higher on page. Title should be above tracking.
            if title_y <= track_y:
                overcrowding = min(overcrowding, 0.2)
        # Logo boxes must stay inside frame.
        if frame and logo_boxes and not frame.get("skipped"):
            fx0 = float(frame["x"])
            fy0 = float(frame["y"])
            fx1 = fx0 + float(frame["w"])
            fy1 = fy0 + float(frame["h"])
            # Allow ~1.5pt AA / ink-pad tolerance at frame edges.
            tol = 1.5
            for b in logo_boxes:
                bx0, by0 = float(b["x"]), float(b["y"])
                bx1, by1 = bx0 + float(b["w"]), by0 + float(b["h"])
                if (
                    bx0 < fx0 - tol
                    or by0 < fy0 - tol
                    or bx1 > fx1 + tol
                    or by1 > fy1 + tol
                ):
                    overcrowding = min(overcrowding, 0.4)
                    details["logo_outside_frame"] = True
                    details["logo_outside_delta"] = {
                        "left": round(fx0 - bx0, 2),
                        "bot": round(fy0 - by0, 2),
                        "right": round(bx1 - fx1, 2),
                        "top": round(by1 - fy1, 2),
                    }
        # Probill must not overlap Swift.
        if swift and probill and float(swift.get("w") or 0) > 0:
            sx0, sy0 = float(swift["x"]), float(swift["y"])
            sx1, sy1 = sx0 + float(swift["w"]), sy0 + float(swift["h"])
            px0, py0 = float(probill["x"]), float(probill["y"])
            px1, py1 = px0 + float(probill["w"]), py0 + float(probill["h"])
            overlap_x = min(sx1, px1) - max(sx0, px0)
            overlap_y = min(sy1, py1) - max(sy0, py0)
            if overlap_x > 1 and overlap_y > 1:
                overcrowding = min(overcrowding, 0.1)
                details["probill_swift_overlap"] = True
    else:
        # PNG: dark density in mid page shouldn't be solid black mass.
        mid = dark[int(h * 0.25) : int(h * 0.75), int(w * 0.05) : int(w * 0.95)]
        mid_den = float(mid.mean()) if mid.size else 0.0
        details["mid_dark_density"] = round(mid_den, 4)
        overcrowding = _clamp01(1.0 - max(0.0, mid_den - 0.22) / 0.25)
    metrics["overcrowding"] = overcrowding

    composite = float(np.mean(list(metrics.values()))) if metrics else 0.0
    return {
        "metrics": {k: round(v, 4) for k, v in metrics.items()},
        "composite": round(composite, 4),
        "details": details,
    }


def evaluate_gates(layout: dict | None, metrics: dict) -> dict:
    """Hard gates for BOL improve loop."""
    gates: dict[str, bool | None] = {
        "structure_ok": None,
        "tracking_visible_ok": None,
        "logo_swift_ok": None,
        "logo_probill_ok": None,
        "margin_ok": None,
    }
    if "structure" in metrics:
        gates["structure_ok"] = metrics["structure"] >= 0.95
    if "tracking_field_visibility" in metrics:
        gates["tracking_visible_ok"] = metrics["tracking_field_visibility"] >= 0.85
    if "logo_swift_clearance" in metrics:
        gates["logo_swift_ok"] = metrics["logo_swift_clearance"] >= 0.90
    if "logo_probill_clearance" in metrics:
        gates["logo_probill_ok"] = metrics["logo_probill_clearance"] >= 0.90
    if "margin_integrity" in metrics:
        gates["margin_ok"] = metrics["margin_integrity"] >= 0.90
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
        "n_cases": len(rows),
        "n_scored": len(scored),
        "mean_composite": mean,
        "cases": rows,
        "gate_fails": gate_fails,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Score BOL synthetic renders")
    p.add_argument("--case", action="append", help="Case id (repeatable)")
    p.add_argument(
        "--json-out",
        type=Path,
        help="Optional path to write full score JSON",
    )
    args = p.parse_args(argv)
    result = score_all(args.case)
    print(
        json.dumps(
            {
                k: result[k]
                for k in ("n_cases", "n_scored", "mean_composite", "gate_fails")
            },
            indent=2,
        )
    )
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
