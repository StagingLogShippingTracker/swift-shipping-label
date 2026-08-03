"""Stage B: geometric polish — smooth contours + hole arc refinement from PNG alpha."""

from __future__ import annotations

import re
from dataclasses import dataclass

import cv2
import numpy as np
from PIL import Image

from .preprocess import PreprocessConfig, build_mask
from .refine import refine_opencv_holes
from .smooth import adaptive_rdp_factor, smooth_contour


@dataclass
class PolishConfig:
    upscale: int = 4
    blur_radius: float = 1.2
    alpha_threshold: int = 80
    min_area: float = 500
    fill_hex: str = "#FFFFFF"
    chaikin_iters: int = 2

    def preprocess(self) -> PreprocessConfig:
        return PreprocessConfig(
            upscale=self.upscale,
            blur_radius=self.blur_radius,
            alpha_threshold=self.alpha_threshold,
            min_area=self.min_area,
        )


@dataclass
class PolishResult:
    svg: str
    contour_count: int
    hole_count: int
    trace_size: tuple[int, int]
    source_size: tuple[int, int]


def _wrap_svg(body: str, source_size: tuple[int, int], fill_hex: str) -> str:
    w, h = source_size
    return (
        f'<svg style="background:transparent" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg">'
        f'<path fill="{fill_hex}" fill-rule="evenodd" d="{body}"/>'
        f"</svg>"
    )


def _scale_path_d(d: str, scale: float) -> str:
    if scale == 1.0:
        return d

    def repl(match: re.Match[str]) -> str:
        return f"{float(match.group(0)) / scale:.3f}"

    return re.sub(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", repl, d)


def polish_png(
    img: Image.Image,
    cfg: PolishConfig | None = None,
) -> PolishResult:
    """
    Stage B: PNG alpha → geometrically polished path SVG.

    Pipeline: upscale + blur + rethreshold → RETR_CCOMP contours → RDP +
    Chaikin + Catmull-Rom cubics → optional P-bowl circle arcs → evenodd SVG.
    """
    cfg = cfg or PolishConfig()
    mask, trace_size, source_size = build_mask(img, cfg.preprocess())
    scale = float(cfg.upscale)

    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    if hierarchy is None or not contours:
        raise RuntimeError("no contours found for geometric polish")

    h = hierarchy[0]
    trace_area = float(trace_size[0] * trace_size[1])
    raw_subpaths: list[str] = []
    holes = 0
    kept = 0

    for i, contour in enumerate(contours):
        area = cv2.contourArea(contour)
        if area < cfg.min_area:
            continue
        kept += 1
        if h[i][3] != -1:
            holes += 1
        rdp = adaptive_rdp_factor(area, trace_area)
        d = smooth_contour(contour, rdp_factor=rdp, chaikin_iters=cfg.chaikin_iters)
        if d:
            raw_subpaths.append(d)

    if not raw_subpaths:
        raise RuntimeError("geometric polish produced no subpaths")

    refined = refine_opencv_holes(mask, raw_subpaths, contours, hierarchy, cfg.min_area)
    subpaths = [_scale_path_d(d, scale) for d in refined]
    svg = _wrap_svg("".join(subpaths), source_size, cfg.fill_hex)
    return PolishResult(
        svg=svg,
        contour_count=kept,
        hole_count=holes,
        trace_size=trace_size,
        source_size=source_size,
    )


def polish_file(
    png_path,
    *,
    fill_hex: str = "#FFFFFF",
    upscale: int = 4,
) -> PolishResult:
    from pathlib import Path

    img = Image.open(Path(png_path)).convert("RGBA")
    return polish_png(
        img,
        PolishConfig(upscale=upscale, fill_hex=fill_hex),
    )
