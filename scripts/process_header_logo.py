"""Convert Swift Supply logo to white-on-transparent for the app header."""

from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = (
    Path.home()
    / ".cursor/projects/c-Users-Brice-OneDrive-Documents-swift-document-generator/assets"
    / "c__Users_Brice_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_Picture1-8286020e-676c-4f45-9b4c-ebf312b31051.png"
)
HI_RES_SRC = ROOT / "mobile" / "assets" / "images" / "swift_supply_logo.png"
FALLBACK_SRC = ROOT / "customer_logos" / "swift_supply_logo_opt.png"
OUT = ROOT / "mobile" / "assets" / "images" / "swift_supply_header_white.png"

# 3× the original 743 px header asset — crisp when scaled down in Flutter.
TARGET_WIDTH = 2229

# SWIFT drop shadow sits down-right of the orange letter cores.
SHADOW_DX = (2, 18)
SHADOW_DY = (2, 18)


def _pick_source(explicit: Path | None) -> Path:
    if explicit and explicit.is_file():
        return explicit
    candidates = [DEFAULT_SRC, HI_RES_SRC, FALLBACK_SRC]
    return max(
        (p for p in candidates if p.is_file()),
        key=lambda p: Image.open(p).size[0],
        default=DEFAULT_SRC,
    )


def _is_background(r: int, g: int, b: int) -> bool:
    return r > 232 and g > 232 and b > 232


def _is_orange(r: int, g: int, b: int) -> bool:
    return r > 130 and g > 40 and b < 150 and r > g and r > b + 25


def _is_dark(r: int, g: int, b: int) -> bool:
    return max(r, g, b) < 110


def _logo_strength(r: int, g: int, b: int, a: int) -> float:
    """0–1 score: how strongly this pixel belongs to the logo mark."""
    if a < 8 or _is_background(r, g, b):
        return 0.0
    if _is_orange(r, g, b):
        sat = min(1.0, (r - max(g, b)) / 100.0)
        lum = min(1.0, max(r, g, b) / 255.0)
        return 0.55 + 0.45 * sat * lum
    if _is_dark(r, g, b):
        # SUPPLY wordmark and SWIFT outlines — solid black letterforms.
        lum = 1.0 - max(r, g, b) / 110.0
        return 0.75 + 0.25 * lum
    # Anti-aliased fringe between orange letterform and white background.
    if r > g and r > b and max(r, g, b) > 90:
        edge = (r - max(g, b)) / 140.0
        if edge > 0.08:
            return min(0.85, edge)
    return 0.0


def _find_supply_rows(
    px, w: int, h: int, letter: list[list[bool]]
) -> tuple[int, int] | None:
    """Rows where SUPPLY lives: mostly dark, little orange (not SWIFT/shadow)."""
    best_start = best_end = 0
    best_score = 0
    run_start: int | None = None
    for y in range(h):
        dark = orange = 0
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16 or _is_background(r, g, b):
                continue
            if _is_dark(r, g, b):
                dark += 1
            elif letter[y][x]:
                orange += 1
        is_supply_row = dark >= 120 and orange <= dark // 4
        if is_supply_row:
            if run_start is None:
                run_start = y
        elif run_start is not None:
            run_len = y - run_start
            if run_len > best_score and run_start > h // 5:
                best_score = run_len
                best_start, best_end = run_start, y - 1
            run_start = None
    if run_start is not None:
        run_len = h - run_start
        if run_len > best_score and run_start > h // 5:
            best_start, best_end = run_start, h - 1
            best_score = run_len
    if best_score < 8:
        return None
    return best_start, best_end


def _build_outline_mask(
    px, w: int, h: int, letter: list[list[bool]], supply_rows: tuple[int, int] | None
) -> list[list[bool]]:
    """Thin black stroke around orange SWIFT cores (not the drop shadow)."""
    outline = [[False] * w for _ in range(h)]
    for y in range(h):
        if _in_supply(y, supply_rows):
            continue
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16 or not _is_dark(r, g, b):
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and letter[ny][nx]:
                        outline[y][x] = True
                        break
                else:
                    continue
                break
    return outline


def _has_orange_offset(
    x: int,
    y: int,
    letter: list[list[bool]],
    w: int,
    h: int,
) -> bool:
    """True when an orange letter core sits up-left (shadow cast direction)."""
    for dy in range(SHADOW_DY[0], SHADOW_DY[1] + 1):
        for dx in range(SHADOW_DX[0], SHADOW_DX[1] + 1):
            ox, oy = x - dx, y - dy
            if 0 <= ox < w and 0 <= oy < h and letter[oy][ox]:
                return True
    return False


def _in_supply(y: int, supply_rows: tuple[int, int] | None) -> bool:
    return bool(supply_rows and supply_rows[0] <= y <= supply_rows[1])


def _build_shadow_mask(
    px,
    w: int,
    h: int,
    letter: list[list[bool]],
    outline: list[list[bool]],
    supply_rows: tuple[int, int] | None,
) -> list[list[bool]]:
    """Morphological shadow mask: dark CCs offset from SWIFT, not letter outlines."""
    shadow = [[False] * w for _ in range(h)]
    seeds: list[tuple[int, int]] = []

    for y in range(h):
        if _in_supply(y, supply_rows):
            continue
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16 or not _is_dark(r, g, b):
                continue
            if outline[y][x]:
                continue
            if _has_orange_offset(x, y, letter, w, h):
                seeds.append((x, y))

    # Flood-fill through dark pixels that are not letter outlines or SUPPLY.
    for sx, sy in seeds:
        if shadow[sy][sx]:
            continue
        q: deque[tuple[int, int]] = deque([(sx, sy)])
        shadow[sy][sx] = True
        while q:
            x, y = q.popleft()
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                if _in_supply(ny, supply_rows) or outline[ny][nx] or shadow[ny][nx]:
                    continue
                r, g, b, a = px[nx, ny]
                if a < 16 or not _is_dark(r, g, b):
                    continue
                shadow[ny][nx] = True
                q.append((nx, ny))

    # Absorb anti-aliased fringe and a thin halo — never swallow orange letter cores.
    for _pass in range(3):
        changed = False
        for y in range(h):
            if _in_supply(y, supply_rows):
                continue
            for x in range(w):
                if shadow[y][x] or outline[y][x]:
                    continue
                r, g, b, a = px[x, y]
                if a < 16 or _is_background(r, g, b) or _is_orange(r, g, b):
                    continue
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and shadow[ny][nx]:
                            shadow[y][x] = True
                            changed = True
                            break
                    else:
                        continue
                    break
        if not changed:
            break

    return shadow


def _trim_transparent(img: Image.Image, pad: int = 3) -> Image.Image:
    bbox = img.getbbox()
    if not bbox:
        return img
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(img.width, x1 + pad)
    y1 = min(img.height, y1 + pad)
    return img.crop((x0, y0, x1, y1))


def _upscale_to_target(img: Image.Image, target_width: int) -> Image.Image:
    if img.width >= target_width:
        return img
    scale = target_width / img.width
    new_h = max(1, round(img.height * scale))
    return img.resize((target_width, new_h), Image.Resampling.LANCZOS)


def process_logo(src: Path, dest: Path, target_width: int = TARGET_WIDTH) -> None:
    img = _upscale_to_target(Image.open(src).convert("RGBA"), target_width)
    w, h = img.size
    px = img.load()

    letter = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16:
                continue
            if _is_orange(r, g, b):
                letter[y][x] = True

    supply_rows = _find_supply_rows(px, w, h, letter)
    if supply_rows:
        print(f"SUPPLY band: rows {supply_rows[0]}-{supply_rows[1]}")

    outline = _build_outline_mask(px, w, h, letter, supply_rows)
    shadow = _build_shadow_mask(px, w, h, letter, outline, supply_rows)
    shadow_count = sum(sum(row) for row in shadow)
    print(f"Shadow pixels removed: {shadow_count}")

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_px = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            strength = _logo_strength(r, g, b, a)
            if strength <= 0:
                continue
            if shadow[y][x]:
                continue

            alpha = min(255, max(0, round(strength * 255)))
            if alpha < 12:
                continue
            out_px[x, y] = (255, 255, 255, alpha)

    out = _trim_transparent(out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest, optimize=True)
    print(f"Wrote {dest} ({out.width}x{out.height}) from {src.name}")


def main() -> int:
    explicit = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    try:
        src = _pick_source(explicit)
    except ValueError:
        print("Source logo not found.", file=sys.stderr)
        return 1
    if not src.is_file():
        print(f"Source logo not found: {src}", file=sys.stderr)
        return 1
    process_logo(src, OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
