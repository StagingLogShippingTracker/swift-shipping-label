"""
Swift Oilfield Supply — Shipping Label
Swiss International Typographic Style (Miedinger / Hoffmann lineage).

Ship-to is the visual hero. Red appears only as page bumpers, the header
rule, the notes rail, and piece-count OF. Same warehouse fields — not a BOL form.
"""
from __future__ import annotations

import os
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from pypdf import PdfReader, PdfWriter
from pypdf.generic import BooleanObject, NameObject

from app_paths import app_dir, bundle_dir

SWIFT = colors.HexColor("#D94B2B")
BLACK = colors.HexColor("#111111")
INK = colors.HexColor("#1A1A1A")
LABEL_C = colors.HexColor("#6A6A6A")
RULE = colors.HexColor("#C8C8C8")
RULE_SOFT = colors.HexColor("#E2E2E2")
NOTES_BG = colors.HexColor("#F7F0D8")
WHITE = colors.white
CLEAR = colors.Color(1, 1, 1, alpha=0)
PIECE_FILL = colors.HexColor("#F7F7F7")

PAGE_W, PAGE_H = landscape(letter)
MX = 0.52 * inch
MY = 0.48 * inch
CONTENT_W = PAGE_W - 2 * MX
GUTTER = 32
COL_W = (CONTENT_W - GUTTER) / 2

ROOT = app_dir()
BUNDLE = bundle_dir()
OUT_PATH = ROOT / "Swift Supply Shipping Label.pdf"
LOGO_PATH = BUNDLE / "assets" / "brand" / "swift_supply_logo_orange.png"
CUSTOMER_LOGO_SAMPLE = ROOT / "sample_customer_logo.png"
if not CUSTOMER_LOGO_SAMPLE.exists():
    alt = BUNDLE / "sample_customer_logo.png"
    if alt.exists():
        CUSTOMER_LOGO_SAMPLE = alt
FONTS_DIR = BUNDLE / "fonts"

# Oswald — structural labels / brand
FONT = "Oswald"
FONT_MED = "Oswald-Medium"
FONT_SEMI = "Oswald-SemiBold"
FONT_BOLD = "Oswald-Bold"

# Calibri — field entry / values (drawn). AcroForm widgets cannot embed
# Calibri (PDF Base-14 limit); blank fillable fields use Helvetica at the
# same point size as a stand-in while typing.
ENTRY = "Calibri"
ENTRY_BOLD = "Calibri-Bold"
ENTRY_SIZE = 18
ENTRY_HERO = 22
ENTRY_SO = 36
ENTRY_NOTES = 18
ENTRY_MIN = 9
LINE_GAP = 3.0
# Max wrap lines for PO / Project before we shrink type instead of growing further
WRAP_MAX_LINES = 2
# Faint orange pill behind Sales Order number
SO_BG = colors.HexColor("#F8EBE7")


def _font_candidates(filename: str) -> list[Path]:
    """Prefer bundled fonts/; Calibri may come from Windows Fonts (not redistributed)."""
    paths = [FONTS_DIR / filename]
    win = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
    # Windows ships calibri.ttf / calibrib.ttf (lowercase names).
    lower = filename.lower()
    if lower == "calibri.ttf":
        paths.append(win / "calibri.ttf")
    elif lower == "calibri-bold.ttf":
        paths.extend([win / "calibrib.ttf", win / "Calibri-Bold.ttf"])
    return paths


def _resolve_font(filename: str) -> Path:
    for path in _font_candidates(filename):
        if path.exists():
            return path
    raise FileNotFoundError(
        f"Missing font: {filename} (checked {[str(p) for p in _font_candidates(filename)]}). "
        "Run scripts/sync_calibri_fonts.ps1 or install Oswald under fonts/."
    )


def _register_fonts() -> None:
    mapping = {
        FONT: "Oswald-Regular.ttf",
        FONT_MED: "Oswald-Medium.ttf",
        FONT_SEMI: "Oswald-SemiBold.ttf",
        FONT_BOLD: "Oswald-Bold.ttf",
        ENTRY: "Calibri.ttf",
        ENTRY_BOLD: "Calibri-Bold.ttf",
    }
    for name, filename in mapping.items():
        path = _resolve_font(filename)
        if name not in pdfmetrics.getRegisteredFontNames():
            pdfmetrics.registerFont(TTFont(name, str(path)))


_register_fonts()


def wrap_lines(text: str, max_w: float, font: str, size: float) -> list[str]:
    """Word-wrap; long unbroken tokens (PO codes) break by character."""
    text = (text or "").strip()
    if not text:
        return []
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split(" ") if paragraph else [""]
        cur = ""
        for word in words:
            # Hard-break oversized tokens
            while stringWidth(word, font, size) > max_w and len(word) > 1:
                fit = 1
                while fit < len(word) and stringWidth(word[: fit + 1], font, size) <= max_w:
                    fit += 1
                chunk = word[:fit]
                word = word[fit:]
                if cur:
                    lines.append(cur)
                    cur = ""
                lines.append(chunk)
            trial = word if not cur else f"{cur} {word}"
            if cur and stringWidth(trial, font, size) > max_w:
                lines.append(cur)
                cur = word
            else:
                cur = trial
        if cur or not paragraph:
            lines.append(cur)
    return lines


def fit_single_line_size(
    text: str,
    max_w: float,
    preferred: float = ENTRY_SIZE,
    min_size: float = ENTRY_MIN,
    font: str = ENTRY_BOLD,
) -> float:
    """Keep preferred size; shrink only when the line would overflow width."""
    text = (text or "").strip()
    if not text:
        return preferred
    size = float(preferred)
    while size > min_size and stringWidth(text, font, size) > max_w:
        size -= 0.5
    return size


def fit_wrapped_size(
    text: str,
    max_w: float,
    preferred: float = ENTRY_SIZE,
    max_lines: int = WRAP_MAX_LINES,
    min_size: float = ENTRY_MIN,
    font: str = ENTRY_BOLD,
) -> float:
    """Wrap up to max_lines at preferred size; shrink only if still overflowing."""
    text = (text or "").strip()
    if not text:
        return preferred
    size = float(preferred)
    while size > min_size:
        lines = wrap_lines(text, max_w, font, size)
        if len(lines) <= max_lines:
            return size
        size -= 0.5
    return min_size


def field_height_for(
    text: str,
    col_w: float,
    font: str = ENTRY_BOLD,
    size: float | None = None,
    max_lines: int = WRAP_MAX_LINES,
    reserve_max: bool = False,
    pad: float = 8,
    min_h: float = 22,
) -> float:
    """Height for a wrapped value field at the given (already-fitted) size."""
    if size is None:
        size = fit_wrapped_size(text, col_w - 4, ENTRY_SIZE, max_lines, font=font)
    if reserve_max:
        n = max_lines
    else:
        lines = wrap_lines(text, col_w - 4, font, size)
        n = min(max(len(lines), 1), max_lines)
    return max(min_h, n * (size + LINE_GAP) + pad)


def _ensure_customer_sample() -> None:
    if CUSTOMER_LOGO_SAMPLE.exists():
        return
    import zipfile

    src = Path(
        r"C:\Users\Brice\Downloads\Shipping Labels-extracted\Shipping Labels"
        r"\Shipping Label- PACIFIC CAMBRIUM.xlsx"
    )
    if src.exists():
        with zipfile.ZipFile(src) as zf:
            CUSTOMER_LOGO_SAMPLE.write_bytes(zf.read("xl/media/image2.png"))


def _pdf_safe(text: str) -> str:
    if not text:
        return ""
    return (
        text.replace("\u2014", "-")
        .replace("\u2013", "-")
        .replace("\u2018", "'")
        .replace("\u2019", "'")
        .replace("\u201c", '"')
        .replace("\u201d", '"')
        .encode("latin-1", errors="replace")
        .decode("latin-1")
    )


def bumper(c: canvas.Canvas, y: float, h: float = 10, r: float = 3.5) -> None:
    c.setFillColor(SWIFT)
    c.roundRect(MX, y, CONTENT_W, h, r, stroke=0, fill=1)


def hairline(c: canvas.Canvas, x: float, y: float, w: float, col=RULE, lw: float = 0.6) -> None:
    c.setStrokeColor(col)
    c.setLineWidth(lw)
    c.line(x, y, x + w, y)


def micro_label(c: canvas.Canvas, x: float, y: float, text: str) -> None:
    c.setFillColor(LABEL_C)
    c.setFont(FONT_MED, 7.5)
    cx = x
    for ch in text.upper():
        c.drawString(cx, y, ch)
        cx += stringWidth(ch, FONT_MED, 7.5) + 0.7


def put_field(
    form,
    name: str,
    x: float,
    y: float,
    w: float,
    h: float,
    value: str = "",
    font_size: float = ENTRY_SIZE,
    fill=CLEAR,
    multiline: bool = False,
    font_name: str = "Helvetica",
) -> None:
    """AcroForm widget — optional only. Prefer flat generated PDFs for print."""
    if form is None or w < 4 or h < 4:
        return
    std = "Helvetica-Bold" if "Bold" in font_name or font_name.endswith("Bold") else "Helvetica"
    flags = []
    if multiline:
        # doNotScroll: wrap inside the box; never hide text behind a scrollbar
        flags.append("multiline")
        flags.append("doNotScroll")
    kwargs = dict(
        name=name,
        tooltip=name.replace("_", " ").title(),
        x=x,
        y=y,
        width=w,
        height=h,
        borderStyle="underlined",
        borderWidth=0,
        forceBorder=False,
        fillColor=fill,
        textColor=BLACK,
        fontSize=font_size,
        value=_pdf_safe(value),
        fontName=std,
        maxlen=500,
    )
    if flags:
        kwargs["fieldFlags"] = " ".join(flags)
    form.textfield(**kwargs)


def draw_value(
    c: canvas.Canvas,
    text: str,
    x: float,
    y: float,
    w: float,
    h: float,
    font_size: float = ENTRY_SIZE,
    font_name: str = ENTRY_BOLD,
    multiline: bool = False,
    color=BLACK,
    centered: bool = False,
) -> None:
    """Static Calibri Bold entry value (samples / generated fills)."""
    if not text:
        return
    c.setFillColor(color)
    c.setFont(font_name, font_size)
    if multiline:
        lines = wrap_lines(str(text), w - 4, font_name, font_size)
        yy = y + h - font_size - 2
        for line in lines:
            if yy < y - 1:
                break
            c.drawString(x + 1, yy, line)
            yy -= font_size + LINE_GAP
    else:
        tx = x + (w - stringWidth(text, font_name, font_size)) / 2 if centered else x + 1
        c.drawString(tx, y + (h - font_size) / 2 + 1, text)


def draw_image_fit(
    c: canvas.Canvas,
    path: Path,
    x: float,
    y: float,
    max_w: float,
    max_h: float,
    right: bool = False,
) -> tuple[float, float]:
    if not path.exists():
        return 0.0, 0.0
    img = ImageReader(str(path))
    iw, ih = img.getSize()
    scale = min(max_w / iw, max_h / ih)
    w, h = iw * scale, ih * scale
    draw_x = x - w if right else x
    c.drawImage(img, draw_x, y, w, h, mask="auto", preserveAspectRatio=True)
    return w, h


def draw_image_in_box(
    c: canvas.Canvas,
    path: Path,
    x: float,
    y: float,
    max_w: float,
    max_h: float,
) -> tuple[float, float]:
    if not path.exists():
        return 0.0, 0.0
    img = ImageReader(str(path))
    iw, ih = img.getSize()
    scale = min(max_w / iw, max_h / ih)
    w, h = iw * scale, ih * scale
    c.drawImage(img, x + (max_w - w) / 2, y + (max_h - h) / 2, w, h, mask="auto", preserveAspectRatio=True)
    return w, h


def _uniform_logo_height(logos: list[Path], slot_w: float, max_h: float) -> float:
    common_h = max_h
    for path in logos:
        if not path.exists():
            continue
        img = ImageReader(str(path))
        iw, ih = img.getSize()
        scale = min(slot_w / iw, max_h / ih)
        h = ih * scale
        if h < common_h:
            common_h = h
    return common_h


def _draw_logo_at_height(
    c: canvas.Canvas,
    path: Path,
    slot_x: float,
    slot_y: float,
    slot_w: float,
    slot_h: float,
    target_h: float,
) -> None:
    if not path.exists():
        return
    img = ImageReader(str(path))
    iw, ih = img.getSize()
    scale = target_h / ih
    w, h = iw * scale, target_h
    if w > slot_w:
        scale = slot_w / iw
        w, h = slot_w, ih * scale
    c.drawImage(
        img,
        slot_x + (slot_w - w) / 2,
        slot_y + (slot_h - h),
        w,
        h,
        mask="auto",
        preserveAspectRatio=True,
    )


def draw_customer_logos_header(
    c: canvas.Canvas,
    logos: list[Path],
    logo_bottom: float,
    band_h: float,
) -> None:
    logos = [p for p in logos if p and p.exists()][:2]
    if not logos:
        return
    # Match Swift header mark: y = logo_bottom + 2, height = band_h - 4 (62.24 pt).
    swift_y_offset = 2
    swift_logo_h = band_h - 4
    pad = 4
    dual_gap = 8
    area_w = COL_W * 0.95
    area_x = MX + pad
    area_y = logo_bottom + swift_y_offset
    area_h = swift_logo_h
    inner_w = area_w - pad * 2

    if len(logos) == 1:
        _draw_logo_at_height(c, logos[0], area_x, area_y, inner_w, area_h, swift_logo_h)
        return

    slot_w = (inner_w - dual_gap) / len(logos)
    for i, path in enumerate(logos):
        _draw_logo_at_height(
            c,
            path,
            area_x + i * (slot_w + dual_gap),
            area_y,
            slot_w,
            area_h,
            swift_logo_h,
        )


def draw_header(c: canvas.Canvas, customer_logo: Path | None = None, customer_logo2: Path | None = None) -> float:
    """
    Logos stay high under the top bumper. The red rule + body start lower
    so logos sit optically centered between top bumper and the rule, and the
    body sits closer to the footer.
    """
    y_top = PAGE_H - MY - 14
    # Logo band height (Swift mark includes its own bumpers)
    band_h = 0.92 * inch
    logo_bottom = y_top - band_h

    logos: list[Path] = []
    if customer_logo:
        logos.append(customer_logo)
    if customer_logo2:
        logos.append(customer_logo2)
    if logos:
        draw_customer_logos_header(c, logos, logo_bottom, band_h)
    else:
        c.setStrokeColor(RULE_SOFT)
        c.setDash(2, 2)
        c.setLineWidth(0.7)
        ph_w, ph_h = 1.85 * inch, 0.5 * inch
        c.roundRect(MX, logo_bottom + 14, ph_w, ph_h, 3, stroke=1, fill=0)
        c.setDash()
        c.setFillColor(LABEL_C)
        c.setFont(FONT_MED, 7.5)
        c.drawCentredString(MX + ph_w / 2, logo_bottom + 14 + ph_h / 2 - 3, "CUSTOMER LOGO")

    if LOGO_PATH.exists():
        draw_image_fit(
            c, LOGO_PATH, MX + CONTENT_W, logo_bottom + 2, COL_W * 0.95, band_h - 4, right=True
        )

    # Happy middle: more air than original, less than the over-correction
    air_under_logos = 0.40 * inch
    rule_y = logo_bottom - air_under_logos
    c.setFillColor(SWIFT)
    c.roundRect(MX, rule_y - 0.5, CONTENT_W, 2.5, 1.0, stroke=0, fill=1)
    return rule_y - 14


def field_row(
    c: canvas.Canvas,
    form,
    y: float,
    label: str,
    key: str,
    x: float,
    col_w: float,
    sample: dict,
    value_h: float | None = None,
    value_size: float | None = None,
    value_font: str = ENTRY_BOLD,
    multiline: bool = False,
    preferred_size: float = ENTRY_SIZE,
) -> float:
    micro_label(c, x, y, label)
    y -= 3
    val = sample.get(key, "")
    if multiline:
        size = (
            value_size
            if value_size is not None
            else fit_wrapped_size(val, col_w - 4, preferred_size)
        )
        vh = value_h if value_h is not None else field_height_for(val, col_w, size=size)
    else:
        size = (
            value_size
            if value_size is not None
            else fit_single_line_size(val, col_w - 4, preferred_size)
        )
        vh = value_h if value_h is not None else max(size + 10, 26)

    put_field(
        form,
        key,
        x,
        y - vh,
        col_w,
        vh,
        "",
        size,
        font_name="Helvetica-Bold",
        multiline=multiline,
    )
    if val:
        draw_value(c, val, x, y - vh, col_w, vh, size, value_font, multiline=multiline)
    hairline(c, x, y - vh - 1, col_w)
    return y - vh - 12


def draw_sales_order_row(
    c: canvas.Canvas, form, y: float, x: float, col_w: float, sample: dict
) -> float:
    """Sales Order — Calibri Bold 36 in a faint orange rounded pill; shrink only if needed."""
    micro_label(c, x, y, "Swift Sales Order No.")
    y -= 4
    val = (sample.get("sales_order") or "").strip()
    pad_x, pad_y = 12, 8
    size = fit_single_line_size(val, col_w - 2 * pad_x, ENTRY_SO, min_size=14)
    text_w = stringWidth(val, ENTRY_BOLD, size) if val else size * 2
    pill_w = min(col_w, text_w + 2 * pad_x)
    pill_h = size + 2 * pad_y
    row_h = max(pill_h, 44)

    c.setFillColor(SO_BG)
    c.roundRect(x, y - pill_h, pill_w, pill_h, 8, stroke=0, fill=1)

    put_field(
        form,
        "sales_order",
        x + pad_x,
        y - pill_h + pad_y - 2,
        max(pill_w - 2 * pad_x, 20),
        size + 4,
        "",
        size,
        font_name="Helvetica-Bold",
    )
    if val:
        draw_value(
            c,
            val,
            x + pad_x,
            y - pill_h + pad_y - 2,
            max(pill_w - 2 * pad_x, 20),
            size + 4,
            size,
            ENTRY_BOLD,
        )
    hairline(c, x, y - row_h - 1, col_w)
    return y - row_h - 12


def draw_hero(c: canvas.Canvas, form, y: float, sample: dict) -> float:
    rx = MX + COL_W + GUTTER
    micro_label(c, rx, y, "Ship to")
    y -= 5
    ship = sample.get("ship_to", "")
    ship_size = fit_single_line_size(ship, COL_W - 4, ENTRY_HERO, min_size=12)
    hero_h = max(ship_size + 12, 30)
    put_field(
        form,
        "ship_to",
        rx,
        y - hero_h,
        COL_W,
        hero_h,
        "",
        ship_size,
        font_name="Helvetica-Bold",
    )
    if ship:
        draw_value(c, ship, rx, y - hero_h, COL_W, hero_h, ship_size, ENTRY_BOLD)
    c.setStrokeColor(BLACK)
    c.setLineWidth(1.0)
    c.line(rx, y - hero_h - 2, rx + COL_W, y - hero_h - 2)
    y -= hero_h + 12

    loc = sample.get("location", "")
    loc_size = fit_wrapped_size(loc, COL_W - 4, ENTRY_SIZE, max_lines=2)
    loc_h = field_height_for(loc, COL_W, size=loc_size)
    micro_label(c, rx, y, "Location")
    y -= 3
    put_field(
        form, "location", rx, y - loc_h, COL_W, loc_h, "", loc_size, multiline=True,
        font_name="Helvetica-Bold",
    )
    if loc:
        draw_value(c, loc, rx, y - loc_h, COL_W, loc_h, loc_size, ENTRY_BOLD, multiline=True)
    hairline(c, rx, y - loc_h - 1, COL_W)
    y -= loc_h + 12

    attn = sample.get("attn", "")
    attn_size = fit_single_line_size(attn, COL_W - 4, ENTRY_SIZE)
    attn_h = max(attn_size + 10, 26)
    micro_label(c, rx, y, "Attn")
    y -= 3
    put_field(form, "attn", rx, y - attn_h, COL_W, attn_h, "", attn_size, font_name="Helvetica-Bold")
    if attn:
        draw_value(c, attn, rx, y - attn_h, COL_W, attn_h, attn_size, ENTRY_BOLD)
    hairline(c, rx, y - attn_h - 1, COL_W)
    return y - attn_h - 12


def draw_identity_pair(c: canvas.Canvas, form, y: float, sample: dict) -> tuple[float, float]:
    """
    Left: Customer / PO / Project — PO & Project wrap up to WRAP_MAX_LINES and
    push Special Instructions down. Shrink type only after wrap limit is hit.
    Right: Ship-to hero / Location / Attn
    """
    lx = MX

    y_l = field_row(c, form, y, "Customer", "customer", lx, COL_W, sample)

    po = sample.get("po_num", "")
    po_size = fit_wrapped_size(po, COL_W - 4, ENTRY_SIZE)
    po_h = field_height_for(po, COL_W, size=po_size)
    y_l = field_row(
        c, form, y_l, "PO No.", "po_num", lx, COL_W, sample, po_h, po_size, multiline=True
    )

    proj = sample.get("project", "")
    proj_size = fit_wrapped_size(proj, COL_W - 4, ENTRY_SIZE)
    proj_h = field_height_for(proj, COL_W, size=proj_size)
    y_l = field_row(
        c, form, y_l, "Project", "project", lx, COL_W, sample, proj_h, proj_size, multiline=True
    )

    y_r = draw_hero(c, form, y, sample)
    return y_l, y_r


def draw_notes_and_meta(
    c: canvas.Canvas, form, y_left: float, y_right: float, sample: dict, band_bottom: float
) -> float:
    """
    Left notes + right meta share the band down to band_bottom (piece-count ceiling).
    Sales Order gets a tall orange pill; other meta rows share the remaining space.
    """
    lx = MX
    rx = MX + COL_W + GUTTER

    # Reserve space for the large SO pill, then distribute the rest
    so_reserve = 56
    usable = max(y_right - (band_bottom + 20), 100)
    other_slots = 3
    other_band = max(usable - so_reserve, 72)
    slot = other_band / other_slots

    y = y_right
    y = field_row(c, form, y, "Carrier", "carrier", rx, COL_W, sample)
    y = min(y, y_right - slot)

    y = field_row(c, form, y, "Swift Packing Slip No.", "packing_slip", rx, COL_W, sample)
    # Pull packing slip into its slot floor if air remains
    pack_floor = y_right - 2 * slot
    if y > pack_floor:
        y = pack_floor

    y = draw_sales_order_row(c, form, y, rx, COL_W, sample)

    contact_top = band_bottom + 20 + slot
    if y > contact_top:
        y = contact_top
    field_row(c, form, y, "Swift Contact", "swift_contact", rx, COL_W, sample)

    # Notes fill leftover left band after PO/Project wrap pushed y_left down
    micro_label(c, lx, y_left, "Special Instructions")
    notes_top = y_left - 4
    notes_floor = band_bottom + 20
    notes_h = max(notes_top - notes_floor, 48)
    c.setFillColor(NOTES_BG)
    c.rect(lx, notes_top - notes_h, COL_W, notes_h, stroke=0, fill=1)
    c.setFillColor(SWIFT)
    c.rect(lx, notes_top - notes_h, 3.5, notes_h, stroke=0, fill=1)

    notes_val = sample.get("special_instructions", "")
    notes_box_h = notes_h - 8
    # Fit notes in the available box: wrap freely, shrink only if needed
    notes_size = ENTRY_NOTES
    while notes_size > ENTRY_MIN:
        lines = wrap_lines(notes_val, COL_W - 18, ENTRY_BOLD, notes_size)
        need = len(lines) * (notes_size + LINE_GAP) + 4
        if need <= notes_box_h or not notes_val:
            break
        notes_size -= 0.5

    put_field(
        form,
        "special_instructions",
        lx + 10,
        notes_top - notes_h + 4,
        COL_W - 14,
        notes_box_h,
        "",
        notes_size,
        fill=CLEAR,
        multiline=True,
        font_name="Helvetica-Bold",
    )
    if notes_val:
        draw_value(
            c,
            notes_val,
            lx + 10,
            notes_top - notes_h + 4,
            COL_W - 14,
            notes_box_h,
            notes_size,
            ENTRY_BOLD,
            multiline=True,
        )
    return band_bottom


def draw_piece_band(c: canvas.Canvas, form, y: float, sample: dict) -> float:
    """Two aligned counters — labels live inside the cells."""
    row_h = 38
    gap = 12
    half = (CONTENT_W - gap) / 2

    def cell(x: float, label: str, prefix: str) -> None:
        c.setFillColor(PIECE_FILL)
        c.roundRect(x, y - row_h, half, row_h, 4, stroke=0, fill=1)
        c.setStrokeColor(RULE_SOFT)
        c.setLineWidth(0.6)
        c.roundRect(x, y - row_h, half, row_h, 4, stroke=1, fill=0)

        # Tracked micro-label, vertically centered on the left
        c.setFillColor(LABEL_C)
        c.setFont(FONT_MED, 7.5)
        cx = x + 12
        cell_mid = y - row_h / 2
        label_mid_y = cell_mid - 2.5
        for ch in label.upper():
            c.drawString(cx, label_mid_y, ch)
            cx += stringWidth(ch, FONT_MED, 7.5) + 0.7

        box = 34
        of_w = 28
        block_w = box * 2 + of_w
        fx = x + (half - block_w) / 2

        value_h = 20
        value_y = cell_mid - value_h / 2
        underline_y = value_y - 1

        num_sz = fit_single_line_size(
            sample.get(f"{prefix}_num", ""), box - 4, ENTRY_SIZE, min_size=11
        )
        put_field(
            form, f"{prefix}_num", fx, value_y, box, value_h, "", num_sz, fill=WHITE,
            font_name="Helvetica-Bold",
        )
        if sample.get(f"{prefix}_num"):
            draw_value(
                c, sample[f"{prefix}_num"], fx, value_y, box, value_h, num_sz, ENTRY_BOLD, centered=True
            )
        hairline(c, fx, underline_y, box, RULE)

        c.setFillColor(SWIFT)
        c.setFont(FONT_BOLD, 11)
        c.drawCentredString(fx + box + of_w / 2, label_mid_y, "OF")

        of_sz = fit_single_line_size(
            sample.get(f"{prefix}_of", ""), box - 4, ENTRY_SIZE, min_size=11
        )
        put_field(
            form, f"{prefix}_of", fx + box + of_w, value_y, box, value_h, "", of_sz, fill=WHITE,
            font_name="Helvetica-Bold",
        )
        if sample.get(f"{prefix}_of"):
            draw_value(
                c,
                sample[f"{prefix}_of"],
                fx + box + of_w,
                value_y,
                box,
                value_h,
                of_sz,
                ENTRY_BOLD,
                centered=True,
            )
        hairline(c, fx + box + of_w, underline_y, box, RULE)

    cell(MX, "Pallet / Crate", "pallet")
    cell(MX + half + gap, "Box", "box")
    return y - row_h


def draw_label_page(
    c: canvas.Canvas, form, sample: dict | None = None,
    customer_logo: Path | None = None, customer_logo2: Path | None = None,
) -> None:
    sample = sample or {}
    _ensure_customer_sample()

    bumper(c, PAGE_H - MY + 4, h=10, r=3.5)

    # Footer anchored to bottom bumper; piece band sits above with a clear breath
    foot_y = MY + 6
    piece_top = foot_y + 70

    y = draw_header(c, customer_logo, customer_logo2)
    y_l, y_r = draw_identity_pair(c, form, y, sample)
    # Notes stretch down to just above the piece band
    draw_notes_and_meta(c, form, y_l, y_r, sample, band_bottom=piece_top + 4)

    hairline(c, MX, piece_top + 8, CONTENT_W, RULE_SOFT)
    draw_piece_band(c, form, piece_top, sample)

    c.setFillColor(LABEL_C)
    c.setFont(FONT, 7)
    c.drawString(MX, foot_y, "SWIFT OILFIELD SUPPLY  ·  NISKU, AB  ·  780-423-6979")
    c.drawRightString(MX + CONTENT_W, foot_y, "ONE LABEL PER UNIT  ·  MATCH BOL PIECE COUNT")

    bumper(c, MY - 12, h=10, r=3.5)


def build_pdf(
    sample: dict | None = None,
    out_path: Path | None = None,
    customer_logo: Path | None = None,
    customer_logo2: Path | None = None,
    fillable: bool = False,
) -> Path:
    """
    Build a shipping-label PDF.

    Default is a *flat* print PDF: values are drawn in Calibri and PO/Project
    wrap pushes Special Instructions. Use fill_shipping_label.py to enter data.

    fillable=True adds AcroForm widgets (not recommended for long PO/Project —
    PDF viewers scroll inside fixed boxes and hide text when printing).
    """
    out_path = out_path or OUT_PATH
    sample = sample or {}
    tmp = out_path.with_suffix(".tmp.pdf")
    c = canvas.Canvas(str(tmp), pagesize=landscape(letter))
    c.setTitle("Swift Oilfield Supply — Shipping Label")
    c.setAuthor("Swift Oilfield Supply")
    form = c.acroForm if fillable else None
    draw_label_page(c, form, sample, customer_logo, customer_logo2)
    c.save()

    if form is None:
        tmp.replace(out_path)
        return out_path

    reader = PdfReader(str(tmp))
    writer = PdfWriter()
    writer.append(reader)
    if "/AcroForm" in writer._root_object:
        writer._root_object["/AcroForm"].get_object()[
            NameObject("/NeedAppearances")
        ] = BooleanObject(True)
    with open(out_path, "wb") as f:
        writer.write(f)
    tmp.unlink(missing_ok=True)
    return out_path


SAMPLE = {
    "customer": "PACIFIC CANBRIAM",
    "ship_to": "STRAIT PROJECTS",
    "po_num": "PCE-112124-03690 / RELEASE 2 / FORT ST JOHN DELIVERY WINDOW / RUSH / CONFIRM DOCK",
    "location": "12341 271 RD, FORT ST. JOHN, BC",
    "project": "B35 PIPE AND FITTINGS - NORTH PAD STAGING AND HOOKUP MATERIALS FOR WELLSITE PACKAGE",
    "carrier": "WILLYS",
    "special_instructions": "Call before delivery. Staging bay 3.",
    "attn": "RICK SHUMAN / JEREMY PLATZ",
    "pallet_num": "1",
    "pallet_of": "2",
    "box_num": "",
    "box_of": "",
    "packing_slip": "1224618",
    "sales_order": "SO-88421",
    "swift_contact": "J. SMITH",
}


def main() -> None:
    import argparse

    p = argparse.ArgumentParser(
        description=(
            "Swift Supply shipping label PDF (flat / print-ready). "
            "For data entry with PO/Project wrap, run: python fill_shipping_label.py"
        )
    )
    p.add_argument(
        "--logo",
        type=Path,
        help="Customer logo image (PNG/JPG), baked into the PDF",
    )
    p.add_argument(
        "--logo2",
        type=Path,
        help="Optional second customer logo (C/O)",
    )
    p.add_argument(
        "--out",
        type=Path,
        help="Output PDF path",
    )
    p.add_argument(
        "--sample",
        action="store_true",
        help="Also write the Pacific Canbriam sample PDF",
    )
    p.add_argument(
        "--fillable",
        action="store_true",
        help="(Not recommended) AcroForm widgets — long text scrolls and may not print",
    )
    args = p.parse_args()

    _ensure_customer_sample()

    if args.logo:
        out = args.out or (ROOT / f"Swift Supply Shipping Label - {args.logo.stem}.pdf")
        print(build_pdf(out_path=out, customer_logo=args.logo, customer_logo2=args.logo2, fillable=args.fillable))
    else:
        print(
            build_pdf(
                out_path=args.out or OUT_PATH,
                fillable=args.fillable,
            )
        )

    if args.sample or not args.logo:
        print(
            build_pdf(
                SAMPLE,
                ROOT / "Swift Supply Shipping Label - Sample (Pacific Canbriam).pdf",
                customer_logo=CUSTOMER_LOGO_SAMPLE if CUSTOMER_LOGO_SAMPLE.exists() else None,
            )
        )


if __name__ == "__main__":
    main()
