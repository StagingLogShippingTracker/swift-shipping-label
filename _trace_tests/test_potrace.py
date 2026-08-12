"""Quick potrace prototype."""
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


def curves_to_svg(plist, width: int, height: int, fill: str) -> str:
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
    d = "".join(parts)
    return (
        f'<svg style="background:transparent" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">'
        f'<path fill="{fill}" fill-rule="evenodd" d="{d}"/></svg>'
    )


def prepare_mask(img: Image.Image, scale: int = 4) -> Image.Image:
    work = img.resize(
        (img.width * scale, img.height * scale),
        Image.Resampling.LANCZOS,
    )
    alpha = np.array(work.split()[3], dtype=np.float32)
    alpha_img = Image.fromarray(alpha.astype(np.uint8))
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=1.2))
    alpha = np.array(alpha_img, dtype=np.float32)
    binary = (alpha > 80).astype(np.uint8) * 255
    return Image.fromarray(binary, mode="L")


def main() -> None:
    white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
    bm_img = prepare_mask(white)
    bm = Bitmap(bm_img, blacklevel=0.5)
    plist = bm.trace(
        turdsize=0,
        turnpolicy=POTRACE_TURNPOLICY_MINORITY,
        alphamax=1.0,
        opticurve=True,
        opttolerance=0.2,
    )
    w, h = bm_img.size
    svg = curves_to_svg(plist, w, h, APP_ORANGE_HEX)
    out = ROOT / "_trace_tests" / "potrace_test.svg"
    out.write_text(svg, encoding="utf-8")
    print("curves", len(plist), "bytes", len(svg), "->", out)


if __name__ == "__main__":
    main()
