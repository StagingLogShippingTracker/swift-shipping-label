"""Compare black-on-white vs white-on-black tracing."""
from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

import numpy as np
import vtracer
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from process_header_logo import BRAND_TARGET_WIDTH, _pick_source, render_white_logo  # noqa: E402


def prepare(white: Image.Image, upscale: int, invert: bool) -> np.ndarray:
    work = white.resize(
        (white.width * upscale, white.height * upscale),
        Image.Resampling.LANCZOS,
    )
    alpha = np.array(work.split()[3])
    binary = Image.fromarray(((alpha > 32).astype(np.uint8) * 255), mode="L")
    binary = binary.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    arr = np.array(binary) > 128
    mask = np.full((arr.shape[0], arr.shape[1], 3), 255 if invert else 0, dtype=np.uint8)
    mask[arr] = 0 if invert else 255
    return mask


def trace(mask: np.ndarray, hierarchical: str, label: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    out = ROOT / "_trace_tests" / f"{label}.svg"
    try:
        Image.fromarray(mask).save(tmp_path)
        vtracer.convert_image_to_svg_py(
            str(tmp_path),
            str(out),
            colormode="binary",
            hierarchical=hierarchical,
            mode="spline",
            filter_speckle=0,
            corner_threshold=120,
            length_threshold=4.0,
            splice_threshold=45,
            path_precision=8,
        )
    finally:
        tmp_path.unlink(missing_ok=True)
    text = out.read_text(encoding="utf-8")
    dim = re.search(r'width="(\d+)"\s+height="(\d+)"', text)
    print(label, "dim", dim.groups(), "paths", text.count("<path"), "bytes", out.stat().st_size)


if __name__ == "__main__":
    white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
    for invert, inv_label in ((False, "black_on_white"), (True, "white_on_black")):
        mask = prepare(white, 2, invert=invert)
        for hier in ("stacked", "cutout"):
            trace(mask, hier, f"{inv_label}_{hier}_u2")
