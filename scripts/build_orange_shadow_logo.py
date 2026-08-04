"""Build the multi-color orange Swift Supply logo with SUPPLY in black and a hard
black drop shadow behind SWIFT.

Reads the existing single-color silhouette at
``assets/brand/swift_supply_logo_orange.png`` (SWIFT + SUPPLY + top/bottom bars, all
orange, alpha-cut), then:

1. Splits it into row bands (top bar / SWIFT / SUPPLY / bottom bar).
2. Keeps the bars in the app orange (#CE4E30).
3. Recolors the SUPPLY rows to solid black.
4. Composites a hard-edge black drop shadow (offset bottom-right) behind SWIFT and
   paints SWIFT in orange on top of it.

Writes the same PNG path back and regenerates the base64 embed-PNG SVG so the whole
document pipeline (PDFs, Flutter, previews) picks up the new artwork with no other
changes.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable, List, Tuple

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SILHOUETTE_PNG = ROOT / "assets" / "brand" / "swift_supply_logo_orange_silhouette.png"
ORANGE_PNG = ROOT / "assets" / "brand" / "swift_supply_logo_orange.png"
ORANGE_SVG = ROOT / "assets" / "brand" / "swift_supply_logo_orange.svg"
ORANGE_PREVIEW = ROOT / "assets" / "brand" / "swift_supply_logo_orange_preview.png"
ORANGE_CHAT = ROOT / "assets" / "brand" / "swift_supply_logo_orange_chat.png"
MOBILE_PNG = ROOT / "mobile" / "assets" / "images" / "swift_supply_logo_orange.png"

APP_ORANGE = (0xCE, 0x4E, 0x30)
BLACK = (0, 0, 0)

# Hard-edge shadow offset for SWIFT — bottom-right, ~8% of SWIFT letter height on
# the 910 px tall master. That matches the visual weight of the reference lockup
# without swallowing the letterforms.
SHADOW_DX = 28
SHADOW_DY = 28

# Row-band detection thresholds tuned to the current 2987×910 silhouette but
# expressed as fractions so re-runs at different sizes still work.
BAR_COVERAGE = 0.85          # a row is a "bar" if ≥85% of the width is opaque
MIN_TEXT_COVERAGE = 0.02     # a row is a text row if it has any real ink

Row = int
Band = Tuple[Row, Row]


def _row_ink(px, width: int, height: int) -> List[int]:
    """Number of opaque pixels per row."""
    counts: List[int] = []
    for y in range(height):
        n = 0
        for x in range(width):
            if px[x, y][3] >= 16:
                n += 1
        counts.append(n)
    return counts


def _find_bars(row_ink: List[int], width: int) -> List[Band]:
    """Return (start, end_inclusive) for every solid horizontal bar band."""
    thresh = int(width * BAR_COVERAGE)
    bands: List[Band] = []
    start = None
    for y, n in enumerate(row_ink):
        is_bar = n >= thresh
        if is_bar and start is None:
            start = y
        elif not is_bar and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, len(row_ink) - 1))
    return bands


def _find_text_bands(
    row_ink: List[int], width: int, exclude: Iterable[Band]
) -> List[Band]:
    """Contiguous runs of rows that carry ink but are not solid bars."""
    excl = list(exclude)
    thresh = max(1, int(width * MIN_TEXT_COVERAGE))
    bar_thresh = int(width * BAR_COVERAGE)
    bands: List[Band] = []
    start = None
    for y, n in enumerate(row_ink):
        in_excl = any(a <= y <= b for a, b in excl)
        is_ink = (n >= thresh) and (n < bar_thresh) and not in_excl
        if is_ink and start is None:
            start = y
        elif not is_ink and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, len(row_ink) - 1))
    return bands


def _paint(
    dst: Image.Image,
    src: Image.Image,
    color: Tuple[int, int, int],
    y0: int,
    y1: int,
    dx: int = 0,
    dy: int = 0,
) -> None:
    """Paint the alpha silhouette from ``src[y0..y1]`` onto ``dst`` at (+dx, +dy).

    Any silhouette pixel above the ink threshold is written as a fully opaque fill
    so layered passes (e.g. orange SWIFT over its black shadow) never show through.
    """
    w, h = src.size
    src_px = src.load()
    dst_px = dst.load()
    new_r, new_g, new_b = color
    for y in range(y0, y1 + 1):
        yd = y + dy
        if yd < 0 or yd >= h:
            continue
        for x in range(w):
            if src_px[x, y][3] < 16:
                continue
            xd = x + dx
            if xd < 0 or xd >= w:
                continue
            dst_px[xd, yd] = (new_r, new_g, new_b, 255)


def build_shadowed_orange_logo(
    src_png: Path,
    dst_png: Path,
    *,
    shadow_dx: int = SHADOW_DX,
    shadow_dy: int = SHADOW_DY,
) -> Tuple[Band, Band, List[Band]]:
    """Compose SWIFT (orange + hard shadow) + SUPPLY (black) + bars (orange)."""
    src = Image.open(src_png).convert("RGBA")
    w, h = src.size
    px = src.load()

    row_ink = _row_ink(px, w, h)
    bars = _find_bars(row_ink, w)
    if len(bars) < 2:
        raise RuntimeError(
            f"Expected two horizontal bars in {src_png}, found {len(bars)}: {bars}"
        )
    top_bar, bottom_bar = bars[0], bars[-1]
    text = _find_text_bands(row_ink, w, exclude=bars)
    if len(text) < 2:
        raise RuntimeError(
            f"Expected SWIFT and SUPPLY text bands in {src_png}, found {text}"
        )
    swift_band = text[0]
    supply_band = text[-1]

    print(f"  top bar    : rows {top_bar[0]}..{top_bar[1]}")
    print(f"  SWIFT band : rows {swift_band[0]}..{swift_band[1]}")
    print(f"  SUPPLY band: rows {supply_band[0]}..{supply_band[1]}")
    print(f"  bottom bar : rows {bottom_bar[0]}..{bottom_bar[1]}")
    print(f"  shadow     : dx={shadow_dx}, dy={shadow_dy}")

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    _paint(out, src, APP_ORANGE, top_bar[0], top_bar[1])
    _paint(out, src, APP_ORANGE, bottom_bar[0], bottom_bar[1])

    _paint(out, src, BLACK, swift_band[0], swift_band[1], dx=shadow_dx, dy=shadow_dy)
    _paint(out, src, APP_ORANGE, swift_band[0], swift_band[1])

    _paint(out, src, BLACK, supply_band[0], supply_band[1])

    dst_png.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst_png, optimize=True)
    print(f"Wrote {dst_png} ({out.width}x{out.height})")
    return swift_band, supply_band, bars


def _write_preview(src_png: Path, dst_png: Path, target_width: int = 1200) -> None:
    img = Image.open(src_png).convert("RGBA")
    if img.width > target_width:
        scale = target_width / img.width
        img = img.resize(
            (target_width, max(1, round(img.height * scale))),
            Image.Resampling.LANCZOS,
        )
    dst_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst_png, optimize=True)
    print(f"Wrote {dst_png}")


def _sync_svg_and_previews(src_png: Path) -> None:
    from tools.logo_vectorizer.embed import write_embedded_png_svg

    w, hh = write_embedded_png_svg(src_png, ORANGE_SVG)
    print(f"Wrote {ORANGE_SVG} (embed-png {w}x{hh})")

    _write_preview(src_png, ORANGE_PREVIEW)
    _write_preview(src_png, ORANGE_CHAT)

    if MOBILE_PNG.parent.exists():
        MOBILE_PNG.write_bytes(src_png.read_bytes())
        print(f"Synced       -> {MOBILE_PNG}")


def main() -> int:
    import sys

    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))

    if not SILHOUETTE_PNG.is_file():
        # First run — assume the current colored PNG has not been shadowed yet
        # and archive it as the silhouette source of truth.
        SILHOUETTE_PNG.write_bytes(ORANGE_PNG.read_bytes())
        print(f"Archived silhouette -> {SILHOUETTE_PNG}")

    build_shadowed_orange_logo(SILHOUETTE_PNG, ORANGE_PNG)
    _sync_svg_and_previews(ORANGE_PNG)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
