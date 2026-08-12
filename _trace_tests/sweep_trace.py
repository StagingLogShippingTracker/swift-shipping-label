"""Sweep trace settings and report path counts / file sizes."""
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
from process_header_logo import (  # noqa: E402
    BRAND_TARGET_WIDTH,
    _pick_source,
    _postprocess_traced_svg,
    render_white_logo,
    APP_ORANGE_HEX,
)


def prepare_mask(img: Image.Image, upscale: int, close_iters: int) -> tuple[np.ndarray, tuple[int, int]]:
    work = img
    if upscale > 1:
        work = img.resize(
            (img.width * upscale, img.height * upscale),
            Image.Resampling.LANCZOS,
        )
    alpha = np.array(work.split()[3])
    binary = Image.fromarray(((alpha > 32).astype(np.uint8) * 255), mode="L")
    for _ in range(close_iters):
        binary = binary.filter(ImageFilter.MaxFilter(3))
        binary = binary.filter(ImageFilter.MinFilter(3))
    mask = np.full((binary.height, binary.width, 3), 255, dtype=np.uint8)
    mask[np.array(binary) < 128] = 0
    return mask, work.size


def run_case(
    white: Image.Image,
    upscale: int,
    close_iters: int,
    hierarchical: str,
    filter_speckle: int,
    corner_threshold: int,
) -> None:
    mask, trace_size = prepare_mask(white, upscale, close_iters)
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    out_svg = ROOT / "_trace_tests" / (
        f"sweep_u{upscale}_c{close_iters}_{hierarchical}_fs{filter_speckle}_ct{corner_threshold}.svg"
    )
    try:
        Image.fromarray(mask).save(tmp_path)
        vtracer.convert_image_to_svg_py(
            str(tmp_path),
            str(out_svg),
            colormode="binary",
            hierarchical=hierarchical,
            mode="spline",
            filter_speckle=filter_speckle,
            corner_threshold=corner_threshold,
            length_threshold=4.0,
            splice_threshold=45,
            path_precision=8,
        )
    finally:
        tmp_path.unlink(missing_ok=True)

    raw = out_svg.read_text(encoding="utf-8")
    processed = _postprocess_traced_svg(raw, APP_ORANGE_HEX)
    dim = re.search(r'width="(\d+)"\s+height="(\d+)"', raw)
    print(
        out_svg.name,
        "trace",
        trace_size,
        "svg_dim",
        dim.groups() if dim else None,
        "paths",
        processed.count("<path"),
        "bytes",
        len(processed),
    )


if __name__ == "__main__":
    white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
    for hierarchical in ("cutout", "stacked"):
        for upscale in (2, 3):
            run_case(white, upscale, 1, hierarchical, 0, 120)
            run_case(white, upscale, 1, hierarchical, 1, 100)
