"""Sweep potrace settings for quality vs speed."""
from __future__ import annotations

import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from potrace import POTRACE_TURNPOLICY_MINORITY, Bitmap

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from process_header_logo import (  # noqa: E402
    APP_ORANGE_HEX,
    BRAND_TARGET_WIDTH,
    _pick_source,
    render_white_logo,
)


def prepare(scale: int, blur: float, threshold: int) -> Image.Image:
    white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
    work = white.resize(
        (white.width * scale, white.height * scale),
        Image.Resampling.LANCZOS,
    )
    alpha = np.array(work.split()[3], dtype=np.float32)
    alpha_img = Image.fromarray(alpha.astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(radius=blur)
    )
    binary = (np.array(alpha_img) > threshold).astype(np.uint8) * 255
    return Image.fromarray(binary, mode="L")


def run(scale: int, blur: float, threshold: int, alphamax: float, opttol: float) -> None:
    bm_img = prepare(scale, blur, threshold)
    t0 = time.perf_counter()
    plist = Bitmap(bm_img, blacklevel=0.5).trace(
        turdsize=0,
        turnpolicy=POTRACE_TURNPOLICY_MINORITY,
        alphamax=alphamax,
        opticurve=True,
        opttolerance=opttol,
    )
    elapsed = time.perf_counter() - t0
    label = f"u{scale}_b{blur}_t{threshold}_a{alphamax}_o{opttol}"
    out = ROOT / "_trace_tests" / f"pot_{label}.svg"
    w, h = bm_img.size
    parts: list[str] = []
    for curve in plist:
        fs = curve.start_point
        parts.append(f"M{fs.x:.2f},{fs.y:.2f}")
        for segment in curve.segments:
            if segment.is_corner:
                a, b = segment.c, segment.end_point
                parts.append(f"L{a.x:.2f},{a.y:.2f}L{b.x:.2f},{b.y:.2f}")
            else:
                a, b, c = segment.c1, segment.c2, segment.end_point
                parts.append(
                    f"C{a.x:.2f},{a.y:.2f} {b.x:.2f},{b.y:.2f} {c.x:.2f},{c.y:.2f}"
                )
        parts.append("z")
    src_w = BRAND_TARGET_WIDTH
    src_h = round(BRAND_TARGET_WIDTH * 910 / 2987)  # approximate
    svg = (
        f'<svg style="background:transparent" width="{src_w}" height="{src_h}" '
        f'viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg">'
        f'<path fill="{APP_ORANGE_HEX}" fill-rule="evenodd" d="{"".join(parts)}"/></svg>'
    )
    out.write_text(svg, encoding="utf-8")
    print(label, "curves", len(plist), f"{elapsed:.1f}s", len(svg), "bytes")


if __name__ == "__main__":
    for scale in (3,):
        for blur, threshold in ((1.0, 80), (1.2, 72)):
            for alphamax, opttol in ((1.0, 0.2), (1.334, 0.5)):
                run(scale, blur, threshold, alphamax, opttol)
