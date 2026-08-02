"""Convert Swift Supply logo to white-on-transparent for the app header."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = (
    Path.home()
    / ".cursor/projects/c-Users-Brice-OneDrive-Documents-swift-document-generator/assets"
    / "c__Users_Brice_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_Picture1-8286020e-676c-4f45-9b4c-ebf312b31051.png"
)
FALLBACK_SRC = ROOT / "customer_logos" / "swift_supply_logo_opt.png"
OUT = ROOT / "mobile" / "assets" / "images" / "swift_supply_header_white.png"

SHADOW_DX = (2, 12)
SHADOW_DY = (2, 12)


def _is_background(r: int, g: int, b: int) -> bool:
    return r > 235 and g > 235 and b > 235


def _is_orange(r: int, g: int, b: int) -> bool:
    return r > 140 and g > 45 and b < 140 and r > g and r > b + 30


def _is_dark(r: int, g: int, b: int) -> bool:
    return max(r, g, b) < 100


def _is_shadow_pixel(x: int, y: int, letter: list[list[bool]], w: int, h: int) -> bool:
    for dy in range(SHADOW_DY[0], SHADOW_DY[1] + 1):
        for dx in range(SHADOW_DX[0], SHADOW_DX[1] + 1):
            ox, oy = x - dx, y - dy
            if 0 <= ox < w and 0 <= oy < h and letter[oy][ox]:
                return True
    return False


def _trim_transparent(img: Image.Image, pad: int = 2) -> Image.Image:
    bbox = img.getbbox()
    if not bbox:
        return img
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(img.width, x1 + pad)
    y1 = min(img.height, y1 + pad)
    return img.crop((x0, y0, x1, y1))


def process_logo(src: Path, dest: Path) -> None:
    img = Image.open(src).convert("RGBA")
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

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_px = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 16 or _is_background(r, g, b):
                continue

            # Drop shadow pixels (dark offset from orange letter cores).
            if _is_dark(r, g, b) and _is_shadow_pixel(x, y, letter, w, h):
                continue

            out_px[x, y] = (255, 255, 255, 255)

    out = _trim_transparent(out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest, optimize=True)
    print(f"Wrote {dest} ({out.width}x{out.height}) from {src.name}")


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.is_file():
        src = FALLBACK_SRC
    if not src.is_file():
        print(f"Source logo not found: {src}", file=sys.stderr)
        return 1
    process_logo(src, OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
