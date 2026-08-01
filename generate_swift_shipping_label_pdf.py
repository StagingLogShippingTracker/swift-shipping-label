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
LOGO_PATH = BUNDLE / "swift_supply_logo.png"
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
ENTRY_SIZE = 9
ENTRY_HERO = 15
ENTRY_NOTES = 9
LINE_GAP = 2.5
# Max wrap lines for PO / Project before Special Instructions absorbs the rest
WRAP_MAX_LINES = 2


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


def field_height_for(
    text: str,
    col_w: float,
    font: str = ENTRY,
    size: float = ENTRY_SIZE,
    max_lines: int = WRAP_MAX_LINES,
    reserve_max: bool = False,
    pad: float = 7,
    min_h: float = 16,
) -> float:
    """Height for a value field. Blank fillable templates reserve max wrap lines."""
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
    font_name: str = ENTRY,
    multiline: bool = False,
) -> None:
    """Static Calibri entry value (samples / generated fills)."""
    if not text:
        return
    c.setFillColor(BLACK)
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
        c.drawString(x + 1, y + (h - font_size) / 2 + 1, text)


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


def draw_header(c: canvas.Canvas, customer_logo: Path | None) -> float:
    """
    Logos stay high under the top bumper. The red rule + body start lower
    so logos sit optically centered between top bumper and the rule, and the
    body sits closer to the footer.
    """
    y_top = PAGE_H - MY - 14
    # Logo band height (Swift mark includes its own bumpers)
    band_h = 0.92 * inch
    logo_bottom = y_top - band_h

    if customer_logo and customer_logo.exists():
        draw_image_fit(c, customer_logo, MX, logo_bottom + 10, COL_W * 0.7, band_h - 18)
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
    value_h: float = 18,
    value_size: float = ENTRY_SIZE,
    value_font: str = ENTRY,
    multiline: bool = False,
) -> float:
    micro_label(c, x, y, label)
    y -= 3
    val = sample.get(key, "")
    put_field(
        form,
        key,
        x,
        y - value_h,
        col_w,
        value_h,
        "",
        value_size,
        font_name="Helvetica",
        multiline=multiline,
    )
    if val:
        draw_value(
            c,
            val,
            x,
            y - value_h,
            col_w,
            value_h,
            value_size,
            value_font,
            multiline=multiline,
        )
    hairline(c, x, y - value_h - 1, col_w)
    return y - value_h - 12


def draw_hero(c: canvas.Canvas, form, y: float, sample: dict) -> float:
    rx = MX + COL_W + GUTTER
    micro_label(c, rx, y, "Ship to")
    y -= 5
    hero_h = 28
    put_field(
        form, "ship_to", rx, y - hero_h, COL_W, hero_h, "", ENTRY_HERO, font_name="Helvetica-Bold"
    )
    if sample.get("ship_to"):
        draw_value(c, sample["ship_to"], rx, y - hero_h, COL_W, hero_h, ENTRY_HERO, ENTRY_BOLD)
    c.setStrokeColor(BLACK)
    c.setLineWidth(1.0)
    c.line(rx, y - hero_h - 2, rx + COL_W, y - hero_h - 2)
    y -= hero_h + 12

    micro_label(c, rx, y, "Location")
    y -= 3
    loc_h = 24
    put_field(form, "location", rx, y - loc_h, COL_W, loc_h, "", ENTRY_SIZE, multiline=True)
    if sample.get("location"):
        draw_value(
            c, sample["location"], rx, y - loc_h, COL_W, loc_h, ENTRY_SIZE, ENTRY, multiline=True
        )
    hairline(c, rx, y - loc_h - 1, COL_W)
    y -= loc_h + 12

    micro_label(c, rx, y, "Attn")
    y -= 3
    attn_h = 18
    put_field(form, "attn", rx, y - attn_h, COL_W, attn_h, "", ENTRY_SIZE)
    if sample.get("attn"):
        draw_value(c, sample["attn"], rx, y - attn_h, COL_W, attn_h, ENTRY_SIZE, ENTRY)
    hairline(c, rx, y - attn_h - 1, COL_W)
    return y - attn_h - 12


def draw_identity_pair(c: canvas.Canvas, form, y: float, sample: dict) -> tuple[float, float]:
    """
    Left: Customer / PO / Project — PO & Project wrap up to WRAP_MAX_LINES and
    push Special Instructions down (shrinking its box). Heights follow the
    actual value text so print layout never scrolls/clips.
    Right: Ship-to hero / Location / Attn
    """
    lx = MX

    y_l = field_row(
        c, form, y, "Customer", "customer", lx, COL_W, sample, 18, ENTRY_SIZE, ENTRY
    )

    po_h = field_height_for(sample.get("po_num", ""), COL_W)
    y_l = field_row(
        c,
        form,
        y_l,
        "PO No.",
        "po_num",
        lx,
        COL_W,
        sample,
        po_h,
        ENTRY_SIZE,
        ENTRY,
        multiline=True,
    )

    proj_h = field_height_for(sample.get("project", ""), COL_W)
    y_l = field_row(
        c,
        form,
        y_l,
        "Project",
        "project",
        lx,
        COL_W,
        sample,
        proj_h,
        ENTRY_SIZE,
        ENTRY,
        multiline=True,
    )

    y_r = draw_hero(c, form, y, sample)
    return y_l, y_r


def draw_notes_and_meta(
    c: canvas.Canvas, form, y_left: float, y_right: float, sample: dict, band_bottom: float
) -> float:
    """
    Left notes + right meta share the band down to band_bottom (piece-count ceiling).
    Right fields are evenly distributed so no dead air above the piece band.
    """
    lx = MX
    rx = MX + COL_W + GUTTER

    meta = [
        ("Carrier", "carrier", 18, ENTRY_SIZE),
        ("Swift Packing Slip No.", "packing_slip", 18, ENTRY_SIZE),
        ("Swift Sales Order No.", "sales_order", 18, ENTRY_SIZE),
        ("Swift Contact", "swift_contact", 18, ENTRY_SIZE),
    ]
    usable = max(y_right - (band_bottom + 20), 90)
    slot = usable / len(meta)
    y = y_right
    for label, key, vh, vs in meta:
        field_row(c, form, y, label, key, rx, COL_W, sample, vh, vs)
        y -= slot

    # Notes fill leftover left band after PO/Project wrap pushed y_left down
    micro_label(c, lx, y_left, "Special Instructions")
    notes_top = y_left - 4
    notes_floor = band_bottom + 20
    notes_h = max(notes_top - notes_floor, 48)
    c.setFillColor(NOTES_BG)
    c.rect(lx, notes_top - notes_h, COL_W, notes_h, stroke=0, fill=1)
    c.setFillColor(SWIFT)
    c.rect(lx, notes_top - notes_h, 3.5, notes_h, stroke=0, fill=1)
    put_field(
        form,
        "special_instructions",
        lx + 10,
        notes_top - notes_h + 4,
        COL_W - 14,
        notes_h - 8,
        "",
        ENTRY_NOTES,
        fill=CLEAR,
        multiline=True,
    )
    if sample.get("special_instructions"):
        draw_value(
            c,
            sample["special_instructions"],
            lx + 10,
            notes_top - notes_h + 4,
            COL_W - 14,
            notes_h - 8,
            ENTRY_NOTES,
            ENTRY,
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
        mid_y = y - row_h / 2 - 2.5
        for ch in label.upper():
            c.drawString(cx, mid_y, ch)
            cx += stringWidth(ch, FONT_MED, 7.5) + 0.7

        box = 34
        of_w = 28
        fx = x + half - 12 - box * 2 - of_w

        put_field(form, f"{prefix}_num", fx, y - row_h + 7, box, 24, "", ENTRY_SIZE + 2, fill=WHITE)
        if sample.get(f"{prefix}_num"):
            draw_value(
                c, sample[f"{prefix}_num"], fx, y - row_h + 7, box, 24, ENTRY_SIZE + 2, ENTRY_BOLD
            )
        hairline(c, fx, y - row_h + 6, box, RULE)

        c.setFillColor(SWIFT)
        c.setFont(FONT_BOLD, 11)
        c.drawCentredString(fx + box + of_w / 2, mid_y, "OF")

        put_field(form, f"{prefix}_of", fx + box + of_w, y - row_h + 7, box, 24, "", ENTRY_SIZE + 2, fill=WHITE)
        if sample.get(f"{prefix}_of"):
            draw_value(
                c,
                sample[f"{prefix}_of"],
                fx + box + of_w,
                y - row_h + 7,
                box,
                24,
                ENTRY_SIZE + 2,
                ENTRY_BOLD,
            )
        hairline(c, fx + box + of_w, y - row_h + 6, box, RULE)

    cell(MX, "Pallet / Crate", "pallet")
    cell(MX + half + gap, "Box", "box")
    return y - row_h


def draw_label_page(
    c: canvas.Canvas, form, sample: dict | None = None, customer_logo: Path | None = None
) -> None:
    sample = sample or {}
    _ensure_customer_sample()

    bumper(c, PAGE_H - MY + 4, h=10, r=3.5)

    # Footer anchored to bottom bumper; piece band sits above with a clear breath
    foot_y = MY + 6
    piece_top = foot_y + 70

    y = draw_header(c, customer_logo)
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
    draw_label_page(c, form, sample, customer_logo)
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
        print(build_pdf(out_path=out, customer_logo=args.logo, fillable=args.fillable))
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
