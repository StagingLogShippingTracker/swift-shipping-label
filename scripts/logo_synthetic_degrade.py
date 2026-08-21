#!/usr/bin/env python3
"""Produce controlled, deterministic logo degradations for the synthetic restore loop.

Usage:
  python scripts/logo_synthetic_degrade.py --seed-from-clean
  python scripts/logo_synthetic_degrade.py qa_logos/synthetic/clean/gcm.png \\
      --out qa_logos/synthetic/degraded/gcm__import_combo.png --recipe import_combo --seed 42

Recipes mimic real mobile/Windows import failures: downscale, JPEG, mild blur,
crushed edges, plate/halo noise, color banding.

`import_combo` is intentionally harsh but **not** chroma-wiping: earlier
scale=0.28 / q=50 fully grayed Arc red (palette 0 — unrecoverable without
inventing brand color). Softened params keep residual hue closer to real phone
imports while still stressing restore engines.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / "qa_logos" / "synthetic"
CLEAN = SYN / "clean"
DEGRADED = SYN / "degraded"
PAIRS = SYN / "pairs.json"

# Named recipes used by pairs.json / improve loop.
# Tuned for training realism: phone/screenshot imports rarely wipe brand chroma
# to pure gray. Harsh enough to stress restore, mild enough that residual hue
# cues survive when the clean mark is chromatic (Arc red, Swift orange, etc.).
# Tradeoff: softening import_combo raises suite scores when residual signal
# exists; it does NOT teach inventing brand colors from fully gray mush.
RECIPES: dict[str, dict] = {
    "downscale_jpeg": {
        "scale": 0.42,
        "jpeg_q": 65,
        "blur": 0.0,
        "crush": 0.0,
        "plate": 0.0,
        "band": 0,
        "halo": 0.0,
    },
    "blur_crush": {
        "scale": 0.45,
        "jpeg_q": 70,
        "blur": 1.15,
        "crush": 0.55,
        "plate": 0.0,
        "band": 0,
        "halo": 0.0,
    },
    "plate_halo": {
        "scale": 0.52,
        "jpeg_q": 70,
        "blur": 0.3,
        "crush": 0.1,
        "plate": 0.7,
        "band": 0,
        "halo": 0.35,
    },
    "banding_jpeg": {
        "scale": 0.35,
        "jpeg_q": 35,
        "blur": 0.4,
        "crush": 0.15,
        "plate": 0.15,
        "band": 24,
        "halo": 0.1,
    },
    "import_combo": {
        # Composite of phone camera / screenshot import failures.
        # Softened vs earlier 0.28/q50/band14: that recipe fully wiped Arc red
        # to gray (palette 0, unrecoverable without inventing chroma). Real phone
        # imports usually leave residual hue. Still harsh (scale~1/3, JPEG, plate).
        "scale": 0.34,
        "jpeg_q": 58,
        "blur": 0.55,
        "crush": 0.22,
        "plate": 0.45,
        "band": 20,
        "halo": 0.22,
    },
}


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(int(seed) & 0xFFFFFFFF)


def _crush_edges(arr: np.ndarray, amount: float, rng: np.random.Generator) -> np.ndarray:
    """Erode soft alpha at ink boundaries (lost anti-aliased edges)."""
    if amount <= 0:
        return arr
    out = arr.copy()
    a = out[:, :, 3].astype(np.float32)
    # Soften then threshold mid-alphas toward transparent.
    soft = Image.fromarray(a.astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(0.8))
    soft_a = np.asarray(soft, dtype=np.float32)
    mid = (soft_a > 20) & (soft_a < 220)
    kill = mid & (rng.random(a.shape) < amount)
    out[:, :, 3] = np.where(kill, (soft_a * (1.0 - amount)).astype(np.uint8), out[:, :, 3])
    return out


def _dilate_mask(mask: np.ndarray, iterations: int) -> np.ndarray:
    """Cheap binary dilation (no scipy)."""
    out = mask.copy()
    for _ in range(max(0, iterations)):
        padded = np.pad(out, 1, constant_values=False)
        neigh = (
            padded[:-2, 1:-1]
            | padded[2:, 1:-1]
            | padded[1:-1, :-2]
            | padded[1:-1, 2:]
            | padded[:-2, :-2]
            | padded[:-2, 2:]
            | padded[2:, :-2]
            | padded[2:, 2:]
            | out
        )
        out = neigh
    return out


def _add_plate_halo(
    arr: np.ndarray, plate: float, halo: float, rng: np.random.Generator
) -> np.ndarray:
    """Near-white plate + faint dark halo outside ink (scanner/screenshot leftovers)."""
    if plate <= 0 and halo <= 0:
        return arr
    h, w = arr.shape[:2]
    out = arr.copy()
    a = out[:, :, 3]
    ink = a >= 40
    if plate > 0:
        plate_rgb = np.array([250, 250, 252], dtype=np.uint8)
        noise = rng.integers(-4, 5, size=(h, w, 3), dtype=np.int16)
        fill = np.clip(plate_rgb.astype(np.int16) + noise, 0, 255).astype(np.uint8)
        mask = ~ink
        out[mask, :3] = fill[mask]
        out[mask, 3] = max(200, int(230 * plate))
    if halo > 0 and ink.any():
        dil = _dilate_mask(ink, iterations=max(1, int(3 * halo)))
        ring = dil & ~ink
        out[ring, :3] = (
            np.array([32, 32, 36], dtype=np.float32) * min(1.0, halo)
        ).astype(np.uint8)
        out[ring, 3] = max(40, int(120 * halo))
    return out


def _band_colors(arr: np.ndarray, levels: int) -> np.ndarray:
    if levels <= 0:
        return arr
    out = arr.copy()
    step = max(1, 256 // levels)
    out[:, :, :3] = (out[:, :, :3].astype(np.int32) // step) * step
    return out


def degrade(
    src: Path,
    dest: Path,
    recipe: str = "import_combo",
    seed: int = 42,
    recipe_overrides: dict | None = None,
) -> dict:
    if recipe not in RECIPES:
        raise ValueError(f"unknown recipe {recipe!r}; choose from {sorted(RECIPES)}")
    cfg = dict(RECIPES[recipe])
    if recipe_overrides:
        cfg.update(recipe_overrides)

    rng = _rng(seed)
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    scale = float(cfg["scale"])
    nw, nh = max(8, int(w * scale)), max(8, int(h * scale))
    small = im.resize((nw, nh), Image.Resampling.BILINEAR)

    blur = float(cfg.get("blur") or 0)
    if blur > 0:
        small = small.filter(ImageFilter.GaussianBlur(blur))

    arr = np.asarray(small, dtype=np.uint8).copy()
    arr = _crush_edges(arr, float(cfg.get("crush") or 0), rng)
    arr = _add_plate_halo(
        arr, float(cfg.get("plate") or 0), float(cfg.get("halo") or 0), rng
    )
    arr = _band_colors(arr, int(cfg.get("band") or 0))

    # JPEG round-trip (flatten on white plate first if alpha present)
    q = int(cfg.get("jpeg_q") or 90)
    rgb = Image.new("RGB", (arr.shape[1], arr.shape[0]), (255, 255, 255))
    rgba = Image.fromarray(arr, "RGBA")
    rgb.paste(rgba, mask=rgba.split()[-1])
    buf = io.BytesIO()
    rgb.save(buf, format="JPEG", quality=q, optimize=True)
    buf.seek(0)
    jpg = Image.open(buf).convert("RGBA")
    # Re-attach a soft alpha from luminance-vs-plate heuristic so restore sees plate leftovers
    jarr = np.asarray(jpg, dtype=np.uint8).copy()
    lum = jarr[:, :, :3].astype(np.int32).mean(axis=2)
    sat = jarr[:, :, :3].max(axis=2).astype(np.int32) - jarr[:, :, :3].min(axis=2)
    plate_px = (lum > 248) & (sat < 8)
    jarr[:, :, 3] = np.where(plate_px, 255, 255).astype(np.uint8)
    # Keep nearly-white as opaque plate (matches phone screenshot imports)
    out = Image.fromarray(jarr, "RGBA")

    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)

    return {
        "clean": str(src.as_posix()),
        "degraded": str(dest.as_posix()),
        "recipe": recipe,
        "seed": seed,
        "params": cfg,
        "size_in": [w, h],
        "size_out": [out.width, out.height],
    }


def seed_from_clean(
    recipes: list[str] | None = None,
    base_seed: int = 42,
) -> dict:
    """Degrade every clean/*.png with each recipe; write pairs.json."""
    recipes = recipes or ["import_combo", "downscale_jpeg", "plate_halo"]
    CLEAN.mkdir(parents=True, exist_ok=True)
    DEGRADED.mkdir(parents=True, exist_ok=True)
    pairs: list[dict] = []
    for clean in sorted(CLEAN.glob("*.png")):
        slug = clean.stem
        for i, recipe in enumerate(recipes):
            seed = base_seed + i * 17 + (sum(ord(c) for c in slug) % 97)
            dest = DEGRADED / f"{slug}__{recipe}.png"
            meta = degrade(clean, dest, recipe=recipe, seed=seed)
            pairs.append(
                {
                    "id": f"{slug}__{recipe}",
                    "slug": slug,
                    "clean": f"clean/{slug}.png",
                    "degraded": f"degraded/{slug}__{recipe}.png",
                    "recipe": recipe,
                    "seed": seed,
                    "params": meta["params"],
                    "anchor": slug in ("swift_orange", "swift_orange_solid"),
                }
            )
            print(f"wrote {dest.relative_to(ROOT)}", flush=True)

    manifest = {
        "version": 1,
        "description": "Synthetic clean↔degraded pairs for logo restore improve loop",
        "recipes": RECIPES,
        "pairs": pairs,
    }
    PAIRS.parent.mkdir(parents=True, exist_ok=True)
    PAIRS.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"wrote {PAIRS.relative_to(ROOT)} ({len(pairs)} pairs)", flush=True)
    return manifest


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Synthetic logo degradation")
    p.add_argument("input", nargs="?", help="Clean PNG/SVG path (PNG preferred)")
    p.add_argument("--out", help="Output degraded PNG")
    p.add_argument("--recipe", default="import_combo", choices=sorted(RECIPES))
    p.add_argument("--seed", type=int, default=42)
    p.add_argument(
        "--seed-from-clean",
        action="store_true",
        help="Degrade all qa_logos/synthetic/clean/*.png and write pairs.json",
    )
    p.add_argument(
        "--recipes",
        default="import_combo,downscale_jpeg,plate_halo",
        help="Comma list for --seed-from-clean",
    )
    args = p.parse_args(argv)

    if args.seed_from_clean:
        seed_from_clean([r.strip() for r in args.recipes.split(",") if r.strip()], args.seed)
        return 0

    if not args.input or not args.out:
        p.error("input and --out required unless --seed-from-clean")
    src = Path(args.input)
    if not src.is_file():
        # Allow SVG by rasterizing via Pillow if possible; otherwise fail clearly.
        print(f"missing input: {src}", file=sys.stderr)
        return 2
    if src.suffix.lower() == ".svg":
        print("SVG input: rasterize to PNG first (use brand PNG or cairosvg).", file=sys.stderr)
        return 2
    meta = degrade(src, Path(args.out), recipe=args.recipe, seed=args.seed)
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
