"""Restore low-resolution logos to a clean ultra-high-resolution PNG.

Pipeline:
  1. Predictive trace (smooth masks + optional font/tilt recreate)
  2. Else RealESRGAN 4x upscale
  3. Lanczos to min height if needed
  4. Flatten solid fills last

Dependencies:
  pip install torch torchvision realesrgan basicsr opencv-python-headless numpy Pillow
"""

from __future__ import annotations

import argparse
import os
import sys
import urllib.request
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

WEIGHTS_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/"
    "RealESRGAN_x4plus.pth"
)
WEIGHTS_NAME = "RealESRGAN_x4plus.pth"


def _weights_path() -> Path:
    cache = Path(__file__).resolve().parent / ".cache" / "realesrgan"
    cache.mkdir(parents=True, exist_ok=True)
    return cache / WEIGHTS_NAME


def _ensure_weights(path: Path) -> Path:
    if path.is_file() and path.stat().st_size > 1_000_000:
        return path
    print(f"Downloading RealESRGAN weights to {path} ...", file=sys.stderr)
    tmp = path.with_suffix(".pth.part")
    urllib.request.urlretrieve(WEIGHTS_URL, tmp)
    tmp.replace(path)
    return path


def _load_bgr_alpha(input_path: str) -> tuple[np.ndarray, np.ndarray | None]:
    """Load image as BGR uint8 plus optional alpha uint8."""
    img = cv2.imdecode(np.fromfile(input_path, dtype=np.uint8), cv2.IMREAD_UNCHANGED)
    if img is None:
        pil = Image.open(input_path)
        pil = pil.convert("RGBA") if "A" in pil.getbands() else pil.convert("RGB")
        arr = np.array(pil)
        if arr.ndim == 2:
            bgr = cv2.cvtColor(arr, cv2.COLOR_GRAY2BGR)
            return bgr, None
        if arr.shape[2] == 4:
            bgr = cv2.cvtColor(arr[:, :, :3], cv2.COLOR_RGB2BGR)
            return bgr, arr[:, :, 3]
        return cv2.cvtColor(arr, cv2.COLOR_RGB2BGR), None

    if img.ndim == 2:
        return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR), None
    if img.shape[2] == 4:
        return img[:, :, :3], img[:, :, 3]
    return img, None


def _save_png(output_path: str, bgr: np.ndarray, alpha: np.ndarray | None) -> None:
    if alpha is not None:
        if alpha.shape[:2] != bgr.shape[:2]:
            alpha = cv2.resize(
                alpha, (bgr.shape[1], bgr.shape[0]), interpolation=cv2.INTER_LANCZOS4
            )
        out = cv2.merge([bgr, alpha])
    else:
        out = bgr
    ext = os.path.splitext(output_path)[1].lower() or ".png"
    ok, buf = cv2.imencode(".png" if ext != ".png" else ext, out)
    if not ok:
        raise RuntimeError(f"Failed to encode PNG for {output_path}")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    Path(output_path).write_bytes(buf.tobytes())


def _realesrgan_upscale_4x(bgr: np.ndarray) -> np.ndarray:
    """4x RealESRGAN upscale. Input/output BGR uint8."""
    import sys

    import torch
    import torchvision.transforms.functional as tvF

    # basicsr still imports the removed torchvision.transforms.functional_tensor.
    sys.modules.setdefault("torchvision.transforms.functional_tensor", tvF)

    from basicsr.archs.rrdbnet_arch import RRDBNet
    from realesrgan import RealESRGANer

    weights = _ensure_weights(_weights_path())
    model = RRDBNet(
        num_in_ch=3,
        num_out_ch=3,
        num_feat=64,
        num_block=23,
        num_grow_ch=32,
        scale=4,
    )
    device = "cuda" if torch.cuda.is_available() else "cpu"
    upsampler = RealESRGANer(
        scale=4,
        model_path=str(weights),
        model=model,
        tile=0,
        tile_pad=10,
        pre_pad=0,
        half=device == "cuda",
        device=device,
    )
    output, _ = upsampler.enhance(bgr, outscale=4)
    return output


def _ensure_min_height(
    bgr: np.ndarray,
    alpha: np.ndarray | None,
    min_height: int,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Scale so height is at least [min_height]; width follows aspect ratio."""
    h, w = bgr.shape[:2]
    if h >= min_height:
        return bgr, alpha
    scale = min_height / float(h)
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    bgr = cv2.resize(bgr, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    if alpha is not None:
        alpha = cv2.resize(alpha, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    return bgr, alpha


def _flatten_solid_areas(bgr: np.ndarray) -> np.ndarray:
    """Collapse near-uniform fills while keeping edges."""
    # Bilateral keeps edges; a light mean-shift-style blur flattens poster noise.
    smoothed = cv2.bilateralFilter(bgr, d=9, sigmaColor=70, sigmaSpace=50)
    gray = cv2.cvtColor(smoothed, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 40, 120)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    edge_mask = edges > 0

    # Cluster every near-uniform fill (any hue) down to a few solid colors.
    data = smoothed.reshape((-1, 3)).astype(np.float32)
    k = 8
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 1.0)
    _, labels, centers = cv2.kmeans(
        data, k, None, criteria, 3, cv2.KMEANS_PP_CENTERS
    )
    quantized = centers[labels.flatten()].reshape(smoothed.shape).astype(np.uint8)
    return quantized


def _clean_edge_noise(bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    # Remove speckles along edges without rounding geometry.
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    cleaned_edges = cv2.morphologyEx(edges, cv2.MORPH_OPEN, kernel, iterations=1)
    denoise = cv2.fastNlMeansDenoisingColored(bgr, None, 3, 3, 7, 21)
    mask = cleaned_edges > 0
    out = bgr.copy()
    # Blend denoise into non-edge regions; keep original edge pixels sharper.
    non_edge = ~mask
    out[non_edge] = denoise[non_edge]
    return out


def _unsharp_mask(bgr: np.ndarray, amount: float = 1.15, radius: int = 3) -> np.ndarray:
    blur = cv2.GaussianBlur(bgr, (0, 0), sigmaX=radius, sigmaY=radius)
    sharp = cv2.addWeighted(bgr, 1.0 + amount, blur, -amount, 0)
    return np.clip(sharp, 0, 255).astype(np.uint8)


def _opencv_cleanup(bgr: np.ndarray) -> np.ndarray:
    cleaned = _clean_edge_noise(bgr)
    return _unsharp_mask(cleaned)


def restore_logo(
    input_path: str,
    output_path: str,
    min_dimension: int = 3000,
) -> str:
    """Restore a low-res logo and write a PNG at least [min_dimension] px tall.

    Width is scaled with the same ratio (square → ~3000×3000, wide → 3000×wider).
    """
    if not os.path.isfile(input_path):
        raise FileNotFoundError(f"Input image not found: {input_path}")
    if min_dimension < 1:
        raise ValueError("min_dimension must be >= 1")

    bgr, alpha = _load_bgr_alpha(input_path)

    try:
        from logo_trace import predictive_trace_rebuild, write_meta

        traced = predictive_trace_rebuild(bgr, alpha, min_dimension)
        if traced is not None:
            tbgr, talpha, meta = traced
            tbgr = _flatten_solid_areas(tbgr)
            _save_png(output_path, tbgr, talpha)
            write_meta(str(Path(output_path).with_suffix(".json")), meta)
            print(f"trace rebuild: {meta}", file=sys.stderr)
            return output_path
    except Exception as e:
        print(f"trace rebuild skipped ({e}); falling back to RealESRGAN", file=sys.stderr)

    # Super-resolve in 4x steps until we are close to target height, then
    # Lanczos to exact min height. A single 4x on a 100px-tall logo only
    # reaches 400px — that looked like "sharper" without a real size jump.
    esrgan_passes = 0
    while bgr.shape[0] < min_dimension and esrgan_passes < 3:
        before_h = bgr.shape[0]
        try:
            bgr = _realesrgan_upscale_4x(bgr)
            print(f"RealESRGAN pass {esrgan_passes + 1}: {before_h} -> {bgr.shape[0]}px", file=sys.stderr)
        except Exception as e:
            print(f"RealESRGAN unavailable ({e}); continuing without it", file=sys.stderr)
            break
        if alpha is not None:
            h, w = bgr.shape[:2]
            alpha = cv2.resize(alpha, (w, h), interpolation=cv2.INTER_LANCZOS4)
        esrgan_passes += 1
        if bgr.shape[0] <= before_h:
            break

    bgr = _opencv_cleanup(bgr)
    bgr, alpha = _ensure_min_height(bgr, alpha, min_dimension)
    # Flatten last so denoise / unsharp / Lanczos cannot reintroduce splotch.
    bgr = _flatten_solid_areas(bgr)
    _save_png(output_path, bgr, alpha)
    return output_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Restore a low-resolution logo to a 3000px+ PNG via RealESRGAN."
    )
    parser.add_argument("input", help="Path to the source logo image")
    parser.add_argument(
        "output",
        nargs="?",
        help="Output PNG path (default: <input>_restored.png)",
    )
    parser.add_argument(
        "--min-dimension",
        type=int,
        default=3000,
        help="Minimum output height in pixels; width follows aspect (default: 3000)",
    )
    args = parser.parse_args(argv)
    output = args.output
    if not output:
        stem = Path(args.input).stem
        output = str(Path(args.input).with_name(f"{stem}_restored.png"))
    path = restore_logo(args.input, output, min_dimension=args.min_dimension)
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
