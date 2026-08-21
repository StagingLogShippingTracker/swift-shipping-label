"""Shared plate knockout, halo strip, and palette lock for logo engines.

Used by vectorize / ESRGAN / cubic baseline so synthetic scoring and the app
agree on matte cleanup. Score-gated: keep thresholds conservative for Swift.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def load_rgba(path: Path | str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.uint8).copy()


def save_rgba(path: Path | str, arr: np.ndarray) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, "RGBA").save(path)


def _corner_plate_mode(arr: np.ndarray) -> str:
    """Detect outer plate hue from corners: 'white', 'black', or 'none'."""
    h, w = arr.shape[:2]
    coords = [
        (0, 0),
        (0, w - 1),
        (h - 1, 0),
        (h - 1, w - 1),
        (0, w // 2),
        (h - 1, w // 2),
        (h // 2, 0),
        (h // 2, w - 1),
    ]
    white = black = opaque = 0
    for y, x in coords:
        r, g, b, a = [int(v) for v in arr[y, x]]
        if a < 40:
            continue
        opaque += 1
        lum = (r + g + b) / 3.0
        sat = max(r, g, b) - min(r, g, b)
        if lum >= 230 and sat <= 22:
            white += 1
        elif lum <= 28 and sat <= 18:
            black += 1
    if opaque == 0:
        return "none"
    if white >= max(2, opaque // 2):
        return "white"
    if black >= max(2, opaque // 2):
        return "black"
    return "none"


def _plate_mask(arr: np.ndarray) -> np.ndarray:
    """Near-white / near-black low-chroma canvas (JPEG-tolerant).

    Only punches the plate mode present at the corners so Swift black strokes
    that touch a cropped AABB are not treated as a dark plate.
    """
    a = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.int32)
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    mode = _corner_plate_mode(arr)
    # Broadened vs pure 245/12 — Arc/Propak JPEG plates land ~230–244.
    white = (a > 40) & (lum >= 230) & (sat <= 22)
    black = (a > 40) & (lum <= 28) & (sat <= 18)
    if mode == "white":
        return white
    if mode == "black":
        return black
    # Transparent corners already — still clear obvious white JPEG leftovers.
    return white


def knockout_border_plate(arr: np.ndarray) -> np.ndarray:
    """Punch border-connected plate pixels to transparent."""
    out = arr.copy()
    plate = _plate_mask(out)
    h, w = plate.shape
    q: deque[tuple[int, int]] = deque()
    seen = np.zeros((h, w), dtype=bool)
    for x in range(w):
        for y in (0, h - 1):
            if plate[y, x]:
                q.append((x, y))
                seen[y, x] = True
    for y in range(h):
        for x in (0, w - 1):
            if plate[y, x] and not seen[y, x]:
                q.append((x, y))
                seen[y, x] = True
    while q:
        x, y = q.popleft()
        out[y, x, 3] = 0
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            if seen[ny, nx] or not plate[ny, nx]:
                continue
            seen[ny, nx] = True
            q.append((nx, ny))
    return out


def strip_halo_fringe(arr: np.ndarray) -> np.ndarray:
    """Punch light gray JPEG halo between chromatic ink and empty canvas."""
    out = arr.copy()
    r = out[:, :, 0].astype(np.int16)
    g = out[:, :, 1].astype(np.int16)
    b = out[:, :, 2].astype(np.int16)
    a = out[:, :, 3]
    sat = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    lum = (r.astype(np.int32) + g.astype(np.int32) + b.astype(np.int32)) / 3.0
    chromatic = (a >= 80) & (sat > 45)
    empty = (a < 40) | ((lum <= 40) & (sat <= 16) & (a > 0))
    fringe = (a >= 40) & (sat < 42) & (lum > 88)
    # 4-neigh dilate via shifts (no cv2 required).
    def dilate(m: np.ndarray) -> np.ndarray:
        up = np.zeros_like(m)
        dn = np.zeros_like(m)
        lf = np.zeros_like(m)
        rt = np.zeros_like(m)
        up[1:, :] = m[:-1, :]
        dn[:-1, :] = m[1:, :]
        lf[:, 1:] = m[:, :-1]
        rt[:, :-1] = m[:, 1:]
        return m | up | dn | lf | rt

    near_ink = dilate(chromatic)
    near_empty = dilate(empty)
    punch = fringe & near_ink & near_empty
    out[:, :, 3] = np.where(punch, 0, a)
    return out


def crop_to_ink(arr: np.ndarray, pad: int = 2, min_alpha: int = 48) -> np.ndarray:
    ink = arr[:, :, 3] >= min_alpha
    ys, xs = np.where(ink)
    if len(xs) == 0:
        return arr
    h, w = arr.shape[:2]
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(w - 1, x1 + pad), min(h - 1, y1 + pad)
    return arr[y0 : y1 + 1, x0 : x1 + 1].copy()


def is_thin_wordmark(arr: np.ndarray) -> bool:
    """Wide short lockups with sparse ink — Arc/GCM-style wordmarks."""
    h, w = arr.shape[:2]
    if h < 8 or w < 8:
        return False
    if w / float(h) < 2.4:
        return False
    a = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.int32)
    lum = rgb.mean(axis=2)
    ink = (a >= 48) & (lum < 235)
    coverage = float(ink.mean()) if ink.size else 0.0
    return 0.04 <= coverage <= 0.42


def recover_residual_chroma(
    arr: np.ndarray,
    *,
    min_accent_sat: int = 36,
    min_accent_px: int = 24,
) -> np.ndarray:
    """Amplify washed same-hue ink toward strong residual accents.

    Honest: no-op when the source is fully gray / only near-white JPEG pink
    fringe remains. Does not invent brand colors from nothing.
    """
    out = arr.copy()
    rgb = out[:, :, :3].astype(np.float32)
    a = out[:, :, 3]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = mx - mn
    lum = rgb.mean(axis=2)
    plate = (lum >= 230) & (sat <= 22)
    black = (lum <= 28) & (sat <= 18)
    ink = (a >= 48) & ~plate & ~black
    n_ink = int(ink.sum())
    if n_ink < 80:
        return out

    # Scale accent floor with crop size — Arc downscale is ~1.7k ink px; a fixed
    # 24px floor was fine, but tiny Trialta crops need a lower absolute gate.
    accent_px = min(min_accent_px, max(8, n_ink // 80))

    # Real residual chroma (mid-luma, sat above pink-fringe mush).
    strong = ink & (sat >= min_accent_sat) & (lum >= 35) & (lum <= 200)
    if int(strong.sum()) < accent_px:
        # One more chance at slightly washed brand fills (Arc red ~sat 35–40).
        strong = ink & (sat >= max(28, min_accent_sat - 8)) & (lum >= 35) & (lum <= 210)
        if int(strong.sum()) < accent_px:
            return out
    # Need accents to cover a meaningful share of ink — tiny JPEG speckles skip.
    if strong.sum() < max(accent_px, int(n_ink * 0.003)):
        return out

    pix = rgb[strong].astype(np.int32)
    q = pix // 24
    keys = q[:, 0] * 1024 + q[:, 1] * 32 + q[:, 2]
    uniq, counts = np.unique(keys, return_counts=True)
    accents: list[tuple[float, np.ndarray, float]] = []
    for k, c in zip(uniq, counts):
        if int(c) < max(6, int(strong.sum() * 0.03)):
            continue
        ki = int(k)
        r = (ki // 1024) * 24 + 12
        g = ((ki // 32) % 32) * 24 + 12
        b = (ki % 32) * 24 + 12
        sat_c = max(r, g, b) - min(r, g, b)
        lum_c = (r + g + b) / 3.0
        if sat_c < max(28, min_accent_sat - 8) or lum_c > 205 or lum_c < 35:
            continue
        # Reject washed near-white pink JPEG fringe pretending to be brand.
        if lum_c > 175 and sat_c < 70:
            continue
        accents.append(
            (float(c) * sat_c, np.array([r, g, b], dtype=np.float32), float(sat_c))
        )
    if not accents:
        return out
    accents.sort(key=lambda t: -t[0])
    accents = accents[:3]

    work = ink & (lum > 40) & (lum < 230)
    if not work.any():
        return out
    wp = rgb[work]
    wl = lum[work]
    ws = sat[work]
    new = wp.copy()
    for _, accent, a_sat in accents:
        a_mid = float(accent.mean())
        a_ch = accent - a_mid
        want = min(185.0, a_sat * 1.45 + 24.0)
        boosted = np.clip(a_mid + a_ch * (want / max(1.0, a_sat)), 0, 255)
        p_ch = wp - wl[:, None]
        denom = (np.linalg.norm(p_ch, axis=1) + 1e-3) * (
            float(np.linalg.norm(a_ch)) + 1e-3
        )
        cos = (p_ch @ a_ch) / denom
        scale = a_mid / np.maximum(wl, 1.0)
        d = np.abs(wp * scale[:, None] - accent).sum(axis=1)
        match = ((cos > 0.42) & (ws >= 5)) | ((d < 65) & (ws >= 8))
        match &= (cos > 0.18) | (d < 55)
        idxs = np.where(match)[0]
        for i in idxs:
            strength = float(
                np.clip(0.52 + 0.42 * (1.0 - ws[i] / max(a_sat, 1.0)), 0.38, 0.90)
            )
            tgt = boosted.copy()
            tmid = float(tgt.mean())
            if tmid > 1:
                tgt = np.clip(tgt * (wl[i] / tmid), 0, 255)
            new[i] = (1.0 - strength) * wp[i] + strength * tgt

    rgb2 = rgb.copy()
    rgb2[work] = new
    out[:, :, :3] = np.clip(rgb2, 0, 255).astype(np.uint8)
    return out


def prepare_for_engine(arr: np.ndarray) -> np.ndarray:
    """Knockout + halo + residual chroma recover + crop before vectorize / ESRGAN."""
    out = knockout_border_plate(arr)
    out = strip_halo_fringe(out)
    out = recover_residual_chroma(out)
    return crop_to_ink(out)


def _brand_palette(arr: np.ndarray, max_colors: int = 16) -> list[np.ndarray]:
    a = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.int32)
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    ink = (a >= 96) & ~((lum < 28) & (sat < 18)) & ~((lum > 245) & (sat < 12))
    if int(ink.sum()) < 40:
        ink = a >= 96
    if not ink.any():
        return []
    q = (rgb[ink] // 16).astype(np.int32)
    keys = q[:, 0] * 4096 + q[:, 1] * 64 + q[:, 2]
    uniq, counts = np.unique(keys, return_counts=True)
    order = np.argsort(-counts)

    def bin_rgb(k: int) -> tuple[int, int, int, float, int]:
        r = (k // 4096) * 16 + 8
        g = ((k // 64) % 64) * 16 + 8
        b = (k % 64) * 16 + 8
        return r, g, b, (r + g + b) / 3.0, max(r, g, b) - min(r, g, b)

    entries: list[tuple[int, np.ndarray, int]] = []  # sat, rgb, count
    for idx in order:
        k = int(uniq[idx])
        r, g, b, lum_c, sat_c = bin_rgb(k)
        if lum_c >= 240 and sat_c <= 14:
            continue
        if lum_c <= 22 and sat_c <= 14:
            continue
        entries.append((sat_c, np.array([r, g, b], dtype=np.int32), int(counts[idx])))

    if not entries:
        return []

    # Prefer chromatic brand fills when any exist (avoid locking to JPEG gray mush).
    chromatic = [e for e in entries if e[0] >= 28]
    pool = chromatic if chromatic else entries
    # Rank by sat*count so residual Arc red beats washed pink majority bins.
    pool_sorted = sorted(pool, key=lambda e: -(e[0] * e[2]))
    return [e[1] for e in pool_sorted[:max_colors]]


def snap_to_source_palette(
    restored: np.ndarray,
    source: np.ndarray,
    max_dist: int = 56,
) -> np.ndarray:
    """Remap restored ink onto nearest source brand fills (palette lock)."""
    palette = _brand_palette(source)
    if not palette:
        return restored
    pal = np.stack(palette, axis=0)
    out = restored.copy()
    a = out[:, :, 3]
    rgb = out[:, :, :3].astype(np.int32)
    ink = a >= 40
    if not ink.any():
        return out
    pix = rgb[ink]
    lum = pix.mean(axis=1)
    sat = pix.max(axis=1) - pix.min(axis=1)
    # Keep hard black / white marks; snap everything else.
    keep = ((lum < 28) & (sat < 18)) | ((lum > 245) & (sat < 12))
    work = pix[~keep]
    if len(work) == 0:
        return out
    diffs = np.abs(work[:, None, :] - pal[None, :, :]).sum(axis=2)
    best_i = diffs.argmin(axis=1)
    best_d = diffs.min(axis=1)
    snapped = work.copy()
    ok = best_d <= max_dist
    snapped[ok] = pal[best_i[ok]]
    pix2 = pix.copy()
    pix2[~keep] = snapped
    out_rgb = out[:, :, :3].copy()
    out_rgb[ink] = pix2.astype(np.uint8)
    out[:, :, :3] = out_rgb
    return out


def palette_fidelity_vs(
    source: np.ndarray,
    restored: np.ndarray,
    tol: int = 48,
) -> float:
    """Fraction of restored ink near a quantized source brand color."""
    src_clean = knockout_border_plate(source)
    palette = _brand_palette(src_clean) or _brand_palette(source)
    if not palette:
        return 1.0
    pal = np.stack(palette, axis=0)
    dm = restored[:, :, 3] >= 96
    if not dm.any():
        return 0.0
    pix = restored[dm, :3].astype(np.int32)
    diffs = np.abs(pix[:, None, :] - pal[None, :, :]).sum(axis=2)
    best = diffs.min(axis=1)
    return float((best <= tol).mean())


def aspect_drift(src: np.ndarray, dst: np.ndarray) -> float:
    def aabb(mask: np.ndarray) -> tuple[int, int, int, int] | None:
        ys, xs = np.where(mask)
        if len(xs) == 0:
            return None
        return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())

    sa = aabb(src[:, :, 3] >= 96)
    sb = aabb(dst[:, :, 3] >= 96)
    if sa is None or sb is None:
        return 1.0
    aw = max(1, sa[2] - sa[0] + 1)
    ah = max(1, sa[3] - sa[1] + 1)
    bw = max(1, sb[2] - sb[0] + 1)
    bh = max(1, sb[3] - sb[1] + 1)
    aa, ba = aw / ah, bw / bh
    return abs(aa - ba) / max(aa, 0.01)


def _ink_aabb(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def ink_mask_iou(src: np.ndarray, dst: np.ndarray) -> float:
    """Ink-mask IoU after cropping both to opaque AABB, then matching size.

    Same geometry check as the golden suite — used to reject ESRGAN/vectorize
    redraws that collapse thin wordmark strokes (Arc plate_halo).
    """
    def crop(arr: np.ndarray) -> np.ndarray:
        box = _ink_aabb(arr[:, :, 3] >= 96)
        if box is None:
            return arr
        x0, y0, x1, y1 = box
        return arr[y0 : y1 + 1, x0 : x1 + 1]

    sa = crop(src)
    da = crop(dst)
    h, w = sa.shape[:2]
    if h < 1 or w < 1:
        return 0.0
    d = np.asarray(
        Image.fromarray(da, "RGBA").resize((w, h), Image.Resampling.NEAREST)
    )
    a = sa[:, :, 3] >= 96
    b = d[:, :, 3] >= 96
    inter = np.logical_and(a, b).sum()
    union = np.logical_or(a, b).sum()
    return float(inter / union) if union else 0.0


def edge_energy(arr: np.ndarray) -> float:
    """Cheap alpha-weighted gradient energy (oversmooth detector)."""
    gray = arr[:, :, :3].astype(np.float32).mean(axis=2)
    a = arr[:, :, 3].astype(np.float32) / 255.0
    g = gray * a
    gx = np.abs(np.diff(g, axis=1)).mean() if g.shape[1] > 1 else 0.0
    gy = np.abs(np.diff(g, axis=0)).mean() if g.shape[0] > 1 else 0.0
    return float(gx + gy)


def fit_aspect_to_source(restored: np.ndarray, source: np.ndarray) -> np.ndarray:
    """Non-uniform scale restored ink AABB to match source aspect (no chroma invent).

    Used when vectorize/SVG rasterization stretches a lockup (Propak) while the
    prepared source aspect is still trustworthy.
    """
    sa = _ink_aabb(source[:, :, 3] >= 96)
    sb = _ink_aabb(restored[:, :, 3] >= 96)
    if sa is None or sb is None:
        return restored
    aw = max(1, sa[2] - sa[0] + 1)
    ah = max(1, sa[3] - sa[1] + 1)
    bw = max(1, sb[2] - sb[0] + 1)
    bh = max(1, sb[3] - sb[1] + 1)
    aa = aw / float(ah)
    ba = bw / float(bh)
    if abs(aa - ba) / max(aa, 0.01) < 0.04:
        return restored
    # Keep height; adjust width to source aspect.
    target_w = max(1, int(round(bh * aa)))
    if target_w == bw:
        return restored
    x0, y0, x1, y1 = sb
    crop = restored[y0 : y1 + 1, x0 : x1 + 1]
    return np.asarray(
        Image.fromarray(crop, "RGBA").resize(
            (target_w, crop.shape[0]), Image.Resampling.LANCZOS
        )
    )


def finalize_restore(
    restored: np.ndarray,
    source: np.ndarray,
    *,
    min_palette: float = 0.18,
    max_aspect_drift: float = 0.35,
    min_ink_iou: float | None = None,
    fit_aspect: bool = False,
) -> np.ndarray:
    """Plate/halo cleanup + palette lock. Raises if palette/geometry collapsed."""
    out = knockout_border_plate(restored)
    out = strip_halo_fringe(out)
    out = crop_to_ink(out)
    src_clean = knockout_border_plate(source)
    src_clean = strip_halo_fringe(src_clean)
    if fit_aspect:
        out = fit_aspect_to_source(out, src_clean)
        out = crop_to_ink(out)
    out = snap_to_source_palette(out, src_clean)
    fid = palette_fidelity_vs(src_clean, out)
    if fid < min_palette:
        raise RuntimeError(f"palette collapse (fidelity={fid:.3f})")
    drift = aspect_drift(src_clean, out)
    if drift > max_aspect_drift:
        raise RuntimeError(f"aspect warp (drift={drift:.3f})")
    if min_ink_iou is not None:
        iou = ink_mask_iou(src_clean, out)
        if iou < min_ink_iou:
            raise RuntimeError(f"ink geometry collapse (iou={iou:.3f})")
    return out
