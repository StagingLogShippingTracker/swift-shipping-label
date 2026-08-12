"""Potrace with separate path elements."""
from __future__ import annotations

import sys
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


def curve_to_d(curve) -> str:
    parts = [f"M{curve.start_point.x:.2f},{curve.start_point.y:.2f}"]
    for seg in curve.segments:
        if seg.is_corner:
            parts.append(
                f"L{seg.c.x:.2f},{seg.c.y:.2f}L{seg.end_point.x:.2f},{seg.end_point.y:.2f}"
            )
        else:
            parts.append(
                f"C{seg.c1.x:.2f},{seg.c1.y:.2f} "
                f"{seg.c2.x:.2f},{seg.c2.y:.2f} "
                f"{seg.end_point.x:.2f},{seg.end_point.y:.2f}"
            )
    parts.append("z")
    return "".join(parts)


def main() -> None:
    white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
    scale = 3
    work = white.resize(
        (white.width * scale, white.height * scale),
        Image.Resampling.LANCZOS,
    )
    alpha = np.array(work.split()[3], dtype=np.float32)
    ai = Image.fromarray(alpha.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))
    binary = (np.array(ai) > 80).astype(np.uint8) * 255
    bm_img = Image.fromarray(binary, mode="L")
    plist = Bitmap(bm_img, blacklevel=0.5).trace(
        turdsize=0,
        turnpolicy=POTRACE_TURNPOLICY_MINORITY,
        alphamax=1.334,
        opticurve=True,
        opttolerance=0.5,
    )
    w, h = bm_img.size
    path_tags = [
        f'<path fill="{APP_ORANGE_HEX}" d="{curve_to_d(c)}"/>' for c in plist
    ]
    svg = (
        f'<svg style="background:transparent" width="{white.width}" height="{white.height}" '
        f'viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg">'
        + "".join(path_tags)
        + "</svg>"
    )
    out = ROOT / "_trace_tests" / "pot_separate_paths.svg"
    out.write_text(svg, encoding="utf-8")
    print("paths", len(path_tags), "bytes", len(svg))


if __name__ == "__main__":
    main()
