#!/usr/bin/env python3
"""Batch parity check: prepare_for_engine vs Dart knockout expectations.

Mirrors mobile/test/customer_logo_knockout_regression_test.dart metrics on
customer_logos/*.png. Writes qa_logos/synthetic/_customer_logo_python_prepare.txt
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from logo_raster_finish import (  # noqa: E402
    _estimate_plate_rgb,
    _plate_fill_mask,
    centerline_protect_mask,
    crop_to_ink,
    is_near_black_canvas,
    knockout_border_plate,
    load_rgba,
    prepare_for_engine,
    punch_enclosed_plate_holes,
)

_HOLE_DIRS = (
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
)


def _plate_kind(plate: tuple[int, int, int] | None) -> str:
    if plate is None:
        return "none"
    if is_near_black_canvas(*plate):
        return "black"
    sat = max(plate) - min(plate)
    lum = sum(plate) / 3.0
    if lum >= 230 and sat <= 22:
        return "white"
    return "other"


def _is_canvas_like(r: int, g: int, b: int) -> bool:
    if is_near_black_canvas(r, g, b):
        return True
    sat = max(r, g, b) - min(r, g, b)
    lum = (r + g + b) / 3.0
    if lum >= 200 and sat <= 28:
        return True
    if 145 <= lum <= 205 and sat <= 40:
        return True
    return False


def _ink_stats(arr: np.ndarray, plate: tuple[int, int, int] | None) -> tuple:
    fill = _plate_fill_mask(arr, plate)
    a = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.int32)
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    near_black = (lum <= 40) & (sat <= 16)
    canvas = near_black | ((lum >= 200) & (sat <= 28)) | (
        (lum >= 145) & (lum <= 205) & (sat <= 40)
    )
    brand_mask = (a >= 80) & ~canvas & ~fill
    brand = int(brand_mask.sum())
    chrom = int(((sat >= 28) & brand_mask).sum())
    if brand == 0:
        return brand, chrom, 0, 0, False
    ys, xs = np.where(brand_mask)
    min_x, max_x = int(xs.min()), int(xs.max())
    min_y, max_y = int(ys.min()), int(ys.max())
    bb_w = max_x - min_x + 1
    bb_h = max_y - min_y + 1
    area = max(1, bb_w * bb_h)
    solid = brand >= 80 and (brand / area >= 0.18 or chrom >= brand * 0.25)
    return brand, chrom, bb_w, bb_h, solid


def _prepare_parity(arr: np.ndarray, pixels: int) -> tuple[np.ndarray, str]:
    """Full prepare on smaller rasters; core knockout path on huge restored PNGs."""
    if pixels <= 1_500_000:
        return prepare_for_engine(arr), "full"
    protect = centerline_protect_mask(arr)
    src_plate = _estimate_plate_rgb(arr)
    hole_plate = src_plate if src_plate is not None else (255, 255, 255)
    out = knockout_border_plate(arr, protect=protect)
    out = punch_enclosed_plate_holes(out, protect=protect, plate=hole_plate)
    out = crop_to_ink(out)
    out = punch_enclosed_plate_holes(out, protect=protect, plate=hole_plate)
    return out, "knockout"


def _corners_transparent(arr: np.ndarray) -> bool:
    h, w = arr.shape[:2]
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if arr[y, x, 3] >= 40:
            return False
    return True


def _count_punchable_holes(arr: np.ndarray, plate: tuple[int, int, int]) -> int:
    """Dart `_punchEnclosedPlateHoles` detector on a processed raster."""
    h, w = arr.shape[:2]
    if w < 8 or h < 8:
        return 0
    fill = _plate_fill_mask(arr, plate)
    a = arr[:, :, 3]
    ink = (a >= 80) & ~fill
    ink_count = int(ink.sum())
    if ink_count < 40:
        return 0

    seen = np.zeros((h, w), dtype=bool)
    holes = 0
    for y in range(h):
        for x in range(w):
            if seen[y, x] or not fill[y, x] or a[y, x] < 12:
                continue
            stack = [(x, y)]
            seen[y, x] = True
            comp: list[tuple[int, int]] = []
            touches = False
            min_x, min_y, max_x, max_y = w, h, 0, 0
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                if cx == 0 or cy == 0 or cx == w - 1 or cy == h - 1:
                    touches = True
                min_x = min(min_x, cx)
                min_y = min(min_y, cy)
                max_x = max(max_x, cx)
                max_y = max(max_y, cy)
                for dx, dy in _HOLE_DIRS:
                    nx, ny = cx + dx, cy + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    if seen[ny, nx] or not fill[ny, nx] or a[ny, nx] < 12:
                        continue
                    seen[ny, nx] = True
                    stack.append((nx, ny))
            if touches:
                continue
            size = len(comp)
            if size < 8 or size > ink_count * 0.22:
                continue
            bw = max_x - min_x + 1
            bh = max_y - min_y + 1
            if bw <= 0 or bh <= 0:
                continue
            if bw > bh * 3.5 or bh > bw * 3.5:
                continue
            if size / float(bw * bh) < 0.32:
                continue
            ink_n = 0
            clear_n = 0
            for cx, cy in comp:
                for dx, dy in _HOLE_DIRS:
                    nx, ny = cx + dx, cy + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        clear_n += 1
                        continue
                    if a[ny, nx] < 80:
                        clear_n += 1
                        continue
                    if fill[ny, nx]:
                        continue
                    ink_n += 1
            boundary = ink_n + clear_n
            if boundary == 0:
                continue
            if ink_n < boundary * 0.7 or ink_n <= clear_n:
                continue
            holes += 1
    return holes


def main() -> int:
    logos = ROOT / "customer_logos"
    files = sorted(logos.glob("*.png"), key=lambda p: p.stat().st_size)
    failures: list[str] = []
    anomalies: list[str] = []
    lines = [
        "python prepare_for_engine customer_logo parity",
        f"dir  {logos}",
        f"n    {len(files)}",
        "",
    ]
    slow: list[tuple[str, float]] = []

    for path in files:
        arr = load_rgba(path)
        plate = _estimate_plate_rgb(arr)
        hole_plate = plate if plate is not None else (255, 255, 255)
        src = _ink_stats(arr, plate)
        pixels = arr.shape[0] * arr.shape[1]
        t0 = time.perf_counter()
        prep, mode = _prepare_parity(arr, pixels)
        ms = (time.perf_counter() - t0) * 1000
        slow.append((path.name, ms))
        print(f"  {path.name} ({mode}, {ms:.0f}ms)", flush=True)
        pst = _ink_stats(prep, plate)
        retain = pst[0] / src[0] if src[0] else 1.0
        shrink = (
            (pst[2] * pst[3]) / (src[2] * src[3]) if src[2] * src[3] else 1.0
        )
        pk = _plate_kind(plate)
        holes = _count_punchable_holes(prep, hole_plate)
        lines.append(
            f"{path.name:48} mode={mode} plate={pk}  "
            f"srcInk={src[0]}  prepInk={pst[0]} ({retain * 100:.1f}%)  "
            f"aabb {src[2]}x{src[3]}->{pst[2]}x{pst[3]} ({shrink * 100:.0f}%)  "
            f"holes={holes}  solid={src[4]}  corners={_corners_transparent(prep)}  "
            f"ms={ms:.0f}"
        )
        if src[4] and src[0] >= 80 and retain < 0.80:
            failures.append(
                f"{path.name}: over-erased {retain * 100:.1f}% "
                f"({pst[0]}/{src[0]})"
            )
        if pk in ("white", "black") and not _corners_transparent(prep):
            failures.append(f"{path.name}: opaque {pk} plate corners")
        if holes > 0:
            failures.append(
                f"{path.name}: {holes} enclosed plate counters remain"
            )
        if src[0] >= 80 and src[2] * src[3] > 200 and shrink < 0.55:
            anomalies.append(
                f"{path.name}: aabb shrink {src[2]}x{src[3]} -> "
                f"{pst[2]}x{pst[3]} ({shrink * 100:.1f}%)"
            )

    lines.extend(["", "ANOMALOUS"])
    if anomalies:
        for a in anomalies:
            lines.append(f"  {a}")
    else:
        lines.append("  none")
    lines.extend(["", "FAILURES"])
    if failures:
        for f in failures:
            lines.append(f"  {f}")
    else:
        lines.append("  none")

    report = "\n".join(lines)
    print(report)
    out = ROOT / "qa_logos/synthetic/_customer_logo_python_prepare.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(report + "\n", encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
