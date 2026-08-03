"""Convert Swift Supply logo to white-on-transparent for the app header and brand exports."""

from __future__ import annotations

import base64
import io
import re
import shutil
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = (
    Path.home()
    / ".cursor/projects/c-Users-Brice-OneDrive-Documents-swift-document-generator/assets"
    / "c__Users_Brice_AppData_Roaming_Cursor_User_workspaceStorage_empty-window_images_Picture1-8286020e-676c-4f45-9b4c-ebf312b31051.png"
)
HI_RES_SRC = ROOT / "mobile" / "assets" / "images" / "swift_supply_logo.png"
FALLBACK_SRC = ROOT / "customer_logos" / "swift_supply_logo_opt.png"
OUT = ROOT / "mobile" / "assets" / "images" / "swift_supply_header_white.png"
BRAND_DIR = ROOT / "assets" / "brand"

# 3× the original 743 px header asset — crisp when scaled down in Flutter.
TARGET_WIDTH = 2229
BRAND_TARGET_WIDTH = 3000
PREVIEW_WIDTH = 1200

# App accent from mobile/lib/theme.dart / ShippingLabelPdf.swift
APP_ORANGE_HEX = "#D94B2B"
APP_ORANGE_RGB = (0xD9, 0x4B, 0x2B)

# SWIFT drop shadow sits down-right of the orange letter cores.
SHADOW_DX = (2, 18)
SHADOW_DY = (2, 18)

# Vector trace: upscale raster before tracing for smoother curves and intact thin strokes.
TRACE_UPSCALE = 3
TRACE_BLUR_RADIUS = 1.0
TRACE_ALPHA_THRESHOLD = 80
POTRACE_ALPHAMAX = 1.334
POTRACE_OPTTOLERANCE = 0.5


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


def render_white_logo(src: Path, target_width: int = TARGET_WIDTH) -> Image.Image:
    """Flat white SWIFT+SUPPLY+bars on transparent — no drop shadow."""
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
    outline = _build_outline_mask(px, w, h, letter, supply_rows)
    shadow = _build_shadow_mask(px, w, h, letter, outline, supply_rows)

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_px = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            strength = _logo_strength(r, g, b, a)
            if strength <= 0 or shadow[y][x]:
                continue
            alpha = min(255, max(0, round(strength * 255)))
            if alpha < 12:
                continue
            out_px[x, y] = (255, 255, 255, alpha)

    return _trim_transparent(out)


def recolor_logo(img: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    out = img.copy()
    out_px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            _, _, _, a = out_px[x, y]
            if a:
                out_px[x, y] = (*rgb, a)
    return out


def _preview_png(img: Image.Image, dest: Path, preview_width: int = PREVIEW_WIDTH) -> None:
    if img.width <= preview_width:
        preview = img.copy()
    else:
        scale = preview_width / img.width
        preview = img.resize(
            (preview_width, max(1, round(img.height * scale))),
            Image.Resampling.LANCZOS,
        )
    dest.parent.mkdir(parents=True, exist_ok=True)
    preview.save(dest, optimize=True)


def _is_full_frame_path(d: str, width: int, height: int) -> bool:
    """True when the first subpath spans the entire SVG canvas (inverted stacked trace)."""
    if not d.startswith("M0 0"):
        return False
    first_sub = d.split(" Z")[0] if " Z" in d else d[:500]
    return (
        str(width) in first_sub
        and str(height) in first_sub
        and first_sub.count("C") >= 3
    )


def _prepare_trace_mask(
    img: Image.Image,
) -> tuple[Image.Image, "np.ndarray", tuple[int, int], tuple[int, int]]:
    """Build a high-res trace mask: blur + threshold, no morphological close."""
    import numpy as np

    source_size = img.size
    work = img
    if TRACE_UPSCALE > 1:
        work = img.resize(
            (img.width * TRACE_UPSCALE, img.height * TRACE_UPSCALE),
            Image.Resampling.LANCZOS,
        )

    alpha = np.array(work.split()[3], dtype=np.float32)
    alpha_img = Image.fromarray(alpha.astype(np.uint8))
    if TRACE_BLUR_RADIUS > 0:
        alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(radius=TRACE_BLUR_RADIUS))
    letter = (np.array(alpha_img) > TRACE_ALPHA_THRESHOLD).astype(np.uint8) * 255

    # Potrace: black letterforms on white.
    potrace_binary = Image.fromarray(255 - letter, mode="L")

    # VTracer: black letterforms on white RGB.
    letter_mask = letter >= 128
    vtracer_mask = np.full((letter.shape[0], letter.shape[1], 3), 255, dtype=np.uint8)
    vtracer_mask[letter_mask] = 0
    return potrace_binary, vtracer_mask, work.size, source_size


def _potrace_curve_to_d(curve) -> str:
    parts = [f"M{curve.start_point.x:.2f},{curve.start_point.y:.2f}"]
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
    return "".join(parts)


def _svg_wrapper(
    body: str,
    trace_size: tuple[int, int],
    source_size: tuple[int, int],
) -> str:
    trace_w, trace_h = trace_size
    src_w, src_h = source_size
    return (
        f'<svg style="background:transparent" width="{src_w}" height="{src_h}" '
        f'viewBox="0 0 {trace_w} {trace_h}" xmlns="http://www.w3.org/2000/svg">'
        f"{body}</svg>"
    )


def _trace_with_potrace(
    binary: Image.Image,
    trace_size: tuple[int, int],
    source_size: tuple[int, int],
    fill_hex: str,
) -> str:
    from potrace import POTRACE_TURNPOLICY_MINORITY, Bitmap

    plist = Bitmap(binary, blacklevel=0.5).trace(
        turdsize=0,
        turnpolicy=POTRACE_TURNPOLICY_MINORITY,
        alphamax=POTRACE_ALPHAMAX,
        opticurve=True,
        opttolerance=POTRACE_OPTTOLERANCE,
    )
    path_tags = [
        f'<path fill="{fill_hex}" d="{_potrace_curve_to_d(curve)}"/>'
        for curve in plist
    ]
    if not path_tags:
        raise RuntimeError("potrace produced no paths")
    return _svg_wrapper("".join(path_tags), trace_size, source_size)


def _trace_with_vtracer(
    mask: "np.ndarray",
    trace_size: tuple[int, int],
    source_size: tuple[int, int],
    fill_hex: str,
) -> str:
    import vtracer

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        Image.fromarray(mask).save(tmp_path)
        with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as svg_tmp:
            svg_path = Path(svg_tmp.name)
        try:
            vtracer.convert_image_to_svg_py(
                str(tmp_path),
                str(svg_path),
                colormode="binary",
                hierarchical="cutout",
                mode="spline",
                filter_speckle=0,
                corner_threshold=60,
                length_threshold=3.0,
                splice_threshold=45,
                path_precision=8,
            )
            raw = svg_path.read_text(encoding="utf-8")
        finally:
            svg_path.unlink(missing_ok=True)
    finally:
        tmp_path.unlink(missing_ok=True)

    return _postprocess_traced_svg(raw, fill_hex, source_size=source_size)


def _find_inkscape() -> str | None:
    for name in ("inkscape", "inkscape.exe"):
        found = shutil.which(name)
        if found:
            return found
    for candidate in (
        Path(r"C:\Program Files\Inkscape\bin\inkscape.exe"),
        Path(r"C:\Program Files\Inkscape\inkscape.exe"),
    ):
        if candidate.is_file():
            return str(candidate)
    return None


def _trace_with_inkscape(
    binary: Image.Image,
    trace_size: tuple[int, int],
    source_size: tuple[int, int],
    fill_hex: str,
) -> str | None:
    inkscape = _find_inkscape()
    if not inkscape:
        return None

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        bmp_path = tmp / "trace.png"
        svg_path = tmp / "trace.svg"
        binary.save(bmp_path)
        actions = (
            "select-all;selection-trace;export-type:svg;export-filename:trace.svg"
        )
        result = subprocess.run(
            [
                inkscape,
                str(bmp_path),
                f"--actions={actions}",
                "--batch-process",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0 or not svg_path.is_file():
            return None
        raw = svg_path.read_text(encoding="utf-8")
    return _postprocess_traced_svg(raw, fill_hex, source_size=source_size)


def _supply_p_x_range(img: Image.Image) -> tuple[int, int] | None:
    """Approximate x-span of the first P in SUPPLY from the flat PNG."""
    import numpy as np

    arr = np.array(img.convert("RGBA"))
    h = arr.shape[0]
    y0, y1 = int(h * 0.68), int(h * 0.86)
    band = arr[y0:y1, :, 3]
    col = band.sum(axis=0)
    if col.max() == 0:
        return None
    thr = col.max() * 0.15
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for x, value in enumerate(col):
        if value > thr and start is None:
            start = x
        elif value <= thr and start is not None:
            if x - start > 30:
                runs.append((start, x - 1))
            start = None
    if start is not None and img.width - start > 30:
        runs.append((start, img.width - 1))
    if len(runs) < 3:
        return None
    return runs[2]


def _svg_covers_p_column(
    svg: str,
    p_range: tuple[int, int],
    trace_size: tuple[int, int],
    source_size: tuple[int, int],
) -> bool:
    trace_w, _ = trace_size
    src_w, _ = source_size
    scale = trace_w / src_w
    x0 = p_range[0] * scale * 0.85
    x1 = p_range[1] * scale * 1.15
    in_band = 0
    for d_attr in re.findall(r'd="([^"]+)"', svg):
        nums = re.findall(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", d_attr)
        xs = [float(nums[i]) for i in range(0, len(nums) - 1, 2)]
        in_band += sum(1 for x in xs if x0 <= x <= x1)
    return in_band >= 12 and svg.count("<path") >= 20


def _verify_traced_svg(svg: str, ref_img: Image.Image, trace_size: tuple[int, int]) -> bool:
    p_range = _supply_p_x_range(ref_img)
    if not p_range:
        return svg.count("<path") >= 20
    return _svg_covers_p_column(svg, p_range, trace_size, ref_img.size)


def _write_embedded_png_svg(img: Image.Image, fill_hex: str) -> str:
    """Pixel-perfect SVG wrapping the HD transparent PNG."""
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    w, h = img.size
    note = (
        "<!-- Vector autotrace did not pass verification; "
        "embedded PNG for pixel-perfect display. "
        "Manual Bézier cleanup in a design tool may still be desired. -->"
    )
    return (
        f"{note}\n"
        f'<svg style="background:transparent" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" xmlns="http://www.w3.org/2000/svg" '
        f'xmlns:xlink="http://www.w3.org/1999/xlink">'
        f'<image width="{w}" height="{h}" href="data:image/png;base64,{b64}"/></svg>'
    )


def _postprocess_traced_svg(
    svg: str,
    fill_hex: str,
    source_size: tuple[int, int] | None = None,
) -> str:
    dim = re.search(r'width="(\d+)"\s+height="(\d+)"', svg)
    trace_width = int(dim.group(1)) if dim else 0
    trace_height = int(dim.group(2)) if dim else 0

    def _fix_path(match: re.Match[str]) -> str:
        tag = match.group(0)
        d_match = re.search(r'\sd="([^"]+)"', tag)
        if d_match and _is_full_frame_path(d_match.group(1), trace_width, trace_height):
            return ""
        if 'fill="' in tag:
            tag = re.sub(r'fill="[^"]*"', f'fill="{fill_hex}"', tag)
        elif "fill=" not in tag:
            tag = tag.replace("<path ", f'<path fill="{fill_hex}" ', 1)
        return tag

    svg = re.sub(r"<path\s[^>]+/>", _fix_path, svg)
    svg = re.sub(r"<path\s[^>]+>", _fix_path, svg)

    if source_size and trace_width and trace_height:
        src_w, src_h = source_size
        if (src_w, src_h) != (trace_width, trace_height):
            if 'viewBox="' not in svg:
                svg = svg.replace(
                    "<svg ",
                    f'<svg viewBox="0 0 {trace_width} {trace_height}" ',
                    1,
                )
            svg = re.sub(
                rf'width="{trace_width}"\s+height="{trace_height}"',
                f'width="{src_w}" height="{src_h}"',
                svg,
                count=1,
            )

    if 'style="background:' not in svg:
        svg = svg.replace("<svg ", '<svg style="background:transparent" ', 1)
    return svg


def _trace_mask_to_svg(img: Image.Image, dest: Path, fill_hex: str) -> str:
    """Trace logo mask to SVG; returns method name used."""
    potrace_binary, vtracer_mask, trace_size, source_size = _prepare_trace_mask(img)

    attempts: list[tuple[str, str | None]] = []

    inkscape_svg = _trace_with_inkscape(
        potrace_binary, trace_size, source_size, fill_hex
    )
    if inkscape_svg:
        attempts.append(("inkscape", inkscape_svg))

    try:
        attempts.append(
            (
                "potrace",
                _trace_with_potrace(
                    potrace_binary, trace_size, source_size, fill_hex
                ),
            )
        )
    except Exception as exc:
        print(f"potrace failed: {exc}", file=sys.stderr)

    try:
        attempts.append(
            (
                "vtracer",
                _trace_with_vtracer(
                    vtracer_mask, trace_size, source_size, fill_hex
                ),
            )
        )
    except Exception as exc:
        print(f"vtracer failed: {exc}", file=sys.stderr)

    for method, svg in attempts:
        if svg and _verify_traced_svg(svg, img, trace_size):
            dest.write_text(svg, encoding="utf-8")
            return method

    svg = _write_embedded_png_svg(img, fill_hex)
    dest.write_text(svg, encoding="utf-8")
    return "embedded-png"


def _svg_to_preview_png(svg_path: Path, dest: Path, preview_width: int = PREVIEW_WIDTH) -> None:
    import cairosvg

    cairosvg.svg2png(
        url=str(svg_path),
        write_to=str(dest),
        output_width=preview_width,
    )


def export_brand_assets(src: Path) -> dict[str, Path]:
    """Write high-res brand PNG/SVG exports plus chat-friendly previews."""
    white = render_white_logo(src, BRAND_TARGET_WIDTH)
    orange = recolor_logo(white, APP_ORANGE_RGB)

    BRAND_DIR.mkdir(parents=True, exist_ok=True)
    outputs: dict[str, Path] = {
        "white_png": BRAND_DIR / "swift_supply_logo_white.png",
        "white_svg": BRAND_DIR / "swift_supply_logo_white.svg",
        "orange_png": BRAND_DIR / "swift_supply_logo_orange.png",
        "orange_svg": BRAND_DIR / "swift_supply_logo_orange.svg",
        "white_preview": BRAND_DIR / "swift_supply_logo_white_preview.png",
        "orange_preview": BRAND_DIR / "swift_supply_logo_orange_preview.png",
    }

    white.save(outputs["white_png"], optimize=True)
    orange.save(outputs["orange_png"], optimize=True)
    print(
        f"Wrote {outputs['white_png']} ({white.width}x{white.height}) "
        f"from {src.name}"
    )
    print(
        f"Wrote {outputs['orange_png']} ({orange.width}x{orange.height}) "
        f"fill {APP_ORANGE_HEX}"
    )

    white_method = _trace_mask_to_svg(white, outputs["white_svg"], "#FFFFFF")
    orange_method = _trace_mask_to_svg(orange, outputs["orange_svg"], APP_ORANGE_HEX)
    print(f"Wrote {outputs['white_svg']} ({outputs['white_svg'].stat().st_size} bytes) via {white_method}")
    print(f"Wrote {outputs['orange_svg']} ({outputs['orange_svg'].stat().st_size} bytes) via {orange_method}")

    _preview_png(white, outputs["white_preview"])
    _preview_png(orange, outputs["orange_preview"])
    print(f"Wrote {outputs['white_preview']}")
    print(f"Wrote {outputs['orange_preview']}")

    return outputs


def process_logo(src: Path, dest: Path, target_width: int = TARGET_WIDTH) -> None:
    out = render_white_logo(src, target_width)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest, optimize=True)
    print(f"Wrote {dest} ({out.width}x{out.height}) from {src.name}")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    brand_mode = "--brand" in sys.argv

    explicit = Path(args[0]) if args else None
    try:
        src = _pick_source(explicit)
    except ValueError:
        print("Source logo not found.", file=sys.stderr)
        return 1
    if not src.is_file():
        print(f"Source logo not found: {src}", file=sys.stderr)
        return 1

    if brand_mode:
        export_brand_assets(src)
        return 0

    process_logo(src, OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
