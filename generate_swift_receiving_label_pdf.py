"""
Swift Oilfield Supply — Receiving Label (print PDF prototype)

Same Swiss visual language as the Shipping Label (Oswald labels, Calibri Bold
values, brand orange bumpers, solid yellow SO pill). Fields match the warehouse receiving
skid label: Customer, Project, PO, Sales Order, PM, Date Received, Received By.

Not wired into the Flutter app yet — regenerate samples until the layout is
approved, then we can add a generator flow.
"""
from __future__ import annotations

import argparse
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

from app_paths import app_dir, bundle_dir

SWIFT = colors.HexColor("#CE4E30")
BLACK = colors.HexColor("#111111")
LABEL_C = colors.HexColor("#6A6A6A")
RULE = colors.HexColor("#C8C8C8")
RULE_SOFT = colors.HexColor("#E2E2E2")
WHITE = colors.white
SO_BG = colors.HexColor("#FFEB3B")
RECV_BG = colors.HexColor("#F7F0D8")
PIECE_FILL = colors.HexColor("#F7F7F7")
INSTRUCTIONS_ALERT = colors.HexColor("#E53935")

PAGE_W, PAGE_H = landscape(letter)
MX = 0.52 * inch
MY = 0.48 * inch
CONTENT_W = PAGE_W - 2 * MX
GUTTER = 32
COL_W = (CONTENT_W - GUTTER) / 2

ROOT = app_dir()
BUNDLE = bundle_dir()
OUT_PATH = ROOT / "Swift Supply Receiving Label.pdf"
LOGO_PATH = BUNDLE / "assets" / "brand" / "swift_supply_logo_orange.png"
FONTS_DIR = BUNDLE / "fonts"

FONT = "Oswald"
FONT_MED = "Oswald-Medium"
FONT_SEMI = "Oswald-SemiBold"
FONT_BOLD = "Oswald-Bold"
ENTRY = "Calibri"
ENTRY_BOLD = "Calibri-Bold"
ENTRY_SIZE = 18
ENTRY_HERO = 22
ENTRY_SO = 48
ENTRY_MIN = 9
LINE_GAP = 3.0
WRAP_MAX_LINES = 3


def _font_candidates(filename: str) -> list[Path]:
    paths = [FONTS_DIR / filename]
    win = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
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
        f"Missing font: {filename}. Run scripts/sync_calibri_fonts.ps1 or install Oswald under fonts/."
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
    text = (text or "").strip()
    if not text:
        return []
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split(" ") if paragraph else [""]
        cur = ""
        for word in words:
            while stringWidth(word, font, size) > max_w and len(word) > 1:
                fit = 1
                while fit < len(word) and stringWidth(word[: fit + 1], font, size) <= max_w:
                    fit += 1
                chunk, word = word[:fit], word[fit:]
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
        if cur or not lines:
            lines.append(cur)
    return lines


def fit_single_line_size(
    text: str,
    max_w: float,
    preferred: float = ENTRY_SIZE,
    min_size: float = ENTRY_MIN,
    font: str = ENTRY_BOLD,
) -> float:
    text = (text or "").strip()
    if not text:
        return preferred
    size = preferred
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
    text = (text or "").strip()
    if not text:
        return preferred
    size = preferred
    while size > min_size:
        lines = wrap_lines(text, max_w, font, size)
        if len(lines) <= max_lines:
            return size
        size -= 0.5
    return min_size


def field_height_for(
    text: str,
    col_w: float,
    size: float,
    max_lines: int = WRAP_MAX_LINES,
    font: str = ENTRY_BOLD,
    min_h: float = 26,
) -> float:
    lines = wrap_lines(text, col_w - 4, font, size)
    n = min(max(len(lines), 1), max_lines)
    return max(min_h, n * (size + LINE_GAP) + 8)


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
    text_color=BLACK,
) -> None:
    if not text:
        return
    c.setFillColor(text_color)
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


CUSTOMER_LOGO_TARGET_H = 55.0
CUSTOMER_LOGO_GAP = 10.0
CUSTOMER_LOGO_TO_SWIFT_GAP = 12.0


def _swift_rendered_width(logo_path: Path, max_w: float, max_h: float) -> float:
    if not logo_path.exists():
        return 0.0
    img = ImageReader(str(logo_path))
    iw, ih = img.getSize()
    if iw <= 0 or ih <= 0:
        return 0.0
    scale = min(max_w / iw, max_h / ih)
    return iw * scale


def draw_customer_logo_row(
    c: canvas.Canvas,
    logos: list[Path],
    left_x: float,
    logo_bottom: float,
    band_top: float,
    target_h: float,
    avail_w: float,
    gap: float = CUSTOMER_LOGO_GAP,
) -> None:
    valid = [p for p in logos if p and p.exists()][:2]
    if not valid or avail_w <= 0:
        return

    h = target_h
    widths: list[float] = []
    for path in valid:
        img = ImageReader(str(path))
        iw, ih = img.getSize()
        if iw <= 0 or ih <= 0:
            continue
        widths.append(iw / ih * h)
    if not widths:
        return

    combined = sum(widths) + gap * (len(widths) - 1)
    if combined > avail_w:
        scale = avail_w / combined
        h *= scale
        widths = [w * scale for w in widths]

    band_center = (band_top + logo_bottom) / 2
    y = band_center - h / 2
    x = left_x
    for path, w in zip(valid, widths):
        img = ImageReader(str(path))
        c.drawImage(img, x, y, w, h, mask="auto", preserveAspectRatio=True)
        x += w + gap


def draw_customer_logos_header(
    c: canvas.Canvas,
    logos: list[Path],
    logo_bottom: float,
    band_h: float,
    y_top: float,
    avail_w: float,
) -> None:
    draw_customer_logo_row(
        c,
        logos,
        MX,
        logo_bottom,
        y_top,
        CUSTOMER_LOGO_TARGET_H,
        avail_w,
    )


def draw_header(
    c: canvas.Canvas,
    customer_logo: Path | None = None,
    customer_logo2: Path | None = None,
) -> float:
    """Customer logo left, Swift right — same as shipping. RECEIVING badge on the rule."""
    y_top = PAGE_H - MY - 14
    band_h = 0.92 * inch
    logo_bottom = y_top - band_h

    logos: list[Path] = []
    if customer_logo:
        logos.append(customer_logo)
    if customer_logo2:
        logos.append(customer_logo2)

    swift_max_w = COL_W * 0.95
    swift_max_h = band_h - 4
    swift_w = _swift_rendered_width(LOGO_PATH, swift_max_w, swift_max_h)
    swift_left_x = MX + CONTENT_W - swift_w
    avail_for_customer = (
        swift_left_x - CUSTOMER_LOGO_TO_SWIFT_GAP - MX if swift_w > 0 else CONTENT_W
    )

    if logos:
        draw_customer_logos_header(c, logos, logo_bottom, band_h, y_top, avail_for_customer)
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

    if LOGO_PATH.exists() and swift_w > 0:
        draw_image_fit(
            c, LOGO_PATH, MX + CONTENT_W, logo_bottom + 2, swift_max_w, swift_max_h, right=True
        )

    air_under_logos = 0.36 * inch
    rule_y = logo_bottom - air_under_logos
    c.setFillColor(SWIFT)
    c.roundRect(MX, rule_y - 0.5, CONTENT_W, 2.5, 1.0, stroke=0, fill=1)

    # Small document-type chip so this never reads as a shipping label
    chip = "RECEIVING"
    c.setFont(FONT_BOLD, 9)
    chip_w = stringWidth(chip, FONT_BOLD, 9) + 16
    chip_h = 16
    chip_x = MX + CONTENT_W - chip_w
    chip_y = rule_y + 8
    c.setFillColor(SO_BG)
    c.roundRect(chip_x, chip_y, chip_w, chip_h, 4, stroke=0, fill=1)
    c.setFillColor(SWIFT)
    c.drawCentredString(chip_x + chip_w / 2, chip_y + 4, chip)

    return rule_y - 18


def draw_labeled_value(
    c: canvas.Canvas,
    y: float,
    label: str,
    value: str,
    x: float,
    col_w: float,
    *,
    preferred: float = ENTRY_SIZE,
    hero: bool = False,
    multiline: bool = False,
    max_lines: int = WRAP_MAX_LINES,
    alert_when_nonempty: bool = False,
) -> float:
    micro_label(c, x, y, label)
    y -= 4
    val = (value or "").strip()
    alert_fill = alert_when_nonempty and bool(val)
    if multiline:
        size = fit_wrapped_size(value, col_w - 4, preferred, max_lines=max_lines)
        vh = field_height_for(value, col_w, size, max_lines=max_lines)
        if alert_fill:
            c.setFillColor(INSTRUCTIONS_ALERT)
            c.rect(x, y - vh, col_w, vh, stroke=0, fill=1)
        draw_value(
            c,
            value,
            x,
            y - vh,
            col_w,
            vh,
            size,
            ENTRY_BOLD,
            multiline=True,
            text_color=WHITE if alert_fill else BLACK,
        )
    else:
        size = fit_single_line_size(
            value, col_w - 4, ENTRY_HERO if hero else preferred, min_size=12 if hero else ENTRY_MIN
        )
        vh = max(size + 12, 30 if hero else 26)
        if alert_fill:
            c.setFillColor(INSTRUCTIONS_ALERT)
            c.rect(x, y - vh, col_w, vh, stroke=0, fill=1)
        draw_value(
            c,
            value,
            x,
            y - vh,
            col_w,
            vh,
            size,
            ENTRY_BOLD,
            text_color=WHITE if alert_fill else BLACK,
        )
    hairline(c, x, y - vh - 1, col_w)
    return y - vh - 14


def draw_sales_order_pill(c: canvas.Canvas, y: float, x: float, col_w: float, value: str) -> float:
    micro_label(c, x, y, "Swift Sales Order No.")
    y -= 4
    val = (value or "").strip()
    pad_x, pad_y = 12, 8
    size = fit_single_line_size(val, col_w - 2 * pad_x, ENTRY_SO, min_size=14)
    text_w = stringWidth(val, ENTRY_BOLD, size) if val else size * 2
    pill_w = min(col_w, text_w + 2 * pad_x)
    pill_h = size + 2 * pad_y
    row_h = max(pill_h, 48)

    c.setFillColor(SO_BG)
    c.roundRect(x, y - pill_h, pill_w, pill_h, 8, stroke=0, fill=1)
    if val:
        text_box_h = size + 4
        text_y = y - pill_h + (pill_h - text_box_h) / 2
        draw_value(
            c,
            val,
            x + pad_x,
            text_y,
            max(pill_w - 2 * pad_x, 20),
            text_box_h,
            size,
            ENTRY_BOLD,
        )
    hairline(c, x, y - row_h - 1, col_w)
    return y - row_h - 14


def draw_received_band(c: canvas.Canvas, y: float, sample: dict) -> float:
    """Replaces the pink stamp: soft amber band with Date Received + Received By."""
    row_h = 56
    gap = 12
    half = (CONTENT_W - gap) / 2

    c.setFillColor(RECV_BG)
    c.roundRect(MX, y - row_h, CONTENT_W, row_h, 6, stroke=0, fill=1)
    c.setFillColor(SWIFT)
    c.roundRect(MX, y - row_h, 3.5, row_h, 0, stroke=0, fill=1)

    def half_cell(x: float, label: str, key: str) -> None:
        micro_label(c, x + 14, y - 14, label)
        val = (sample.get(key) or "").strip()
        size = fit_single_line_size(val, half - 28, ENTRY_HERO, min_size=12)
        draw_value(c, val, x + 14, y - row_h + 8, half - 28, size + 6, size, ENTRY_BOLD)

    half_cell(MX, "Date Received", "date_received")
    half_cell(MX + half + gap, "Received By", "received_by")
    return y - row_h


def draw_label_page(
    c: canvas.Canvas,
    sample: dict,
    customer_logo: Path | None = None,
    customer_logo2: Path | None = None,
) -> None:
    bumper(c, PAGE_H - MY + 4, h=10, r=3.5)

    foot_y = MY + 6
    recv_top = foot_y + 78

    y = draw_header(c, customer_logo, customer_logo2)

    lx = MX
    rx = MX + COL_W + GUTTER

    # Left: identity (matches skid label order)
    y_l = draw_labeled_value(
        c, y, "Customer", sample.get("customer", ""), lx, COL_W, hero=True
    )
    y_l = draw_labeled_value(
        c,
        y_l,
        "Project",
        sample.get("project", ""),
        lx,
        COL_W,
        multiline=True,
        max_lines=3,
    )
    y_l = draw_labeled_value(
        c, y_l, "PO Number", sample.get("po_num", ""), lx, COL_W, multiline=True, max_lines=2
    )

    # Right: warehouse keys — Sales Order is the visual hero (like shipping)
    y_r = draw_sales_order_pill(c, y, rx, COL_W, sample.get("sales_order", ""))
    y_r = draw_labeled_value(c, y_r, "PM", sample.get("pm", ""), rx, COL_W, hero=False)

    # Full-width Special Instructions after PO — 2 lines, same style as other fields
    y_mid = min(y_l, y_r)
    y_mid = draw_labeled_value(
        c,
        y_mid,
        "Special Instructions",
        sample.get("special_instructions", ""),
        MX,
        CONTENT_W,
        multiline=True,
        max_lines=2,
        alert_when_nonempty=True,
    )

    hairline(c, MX, recv_top + 10, CONTENT_W, RULE_SOFT)
    draw_received_band(c, recv_top, sample)

    c.setFillColor(LABEL_C)
    c.setFont(FONT, 7)
    c.drawString(MX, foot_y, "SWIFT OILFIELD SUPPLY  ·  NISKU, AB  ·  780-423-6979")
    c.drawRightString(
        MX + CONTENT_W, foot_y, "STAGED  ·  AWAITING SHIP INSTRUCTIONS"
    )

    bumper(c, MY - 12, h=10, r=3.5)


def build_pdf(
    sample: dict | None = None,
    out_path: Path | None = None,
    customer_logo: Path | None = None,
    customer_logo2: Path | None = None,
) -> Path:
    out_path = out_path or OUT_PATH
    sample = sample or {}
    c = canvas.Canvas(str(out_path), pagesize=landscape(letter))
    c.setTitle("Swift Oilfield Supply — Receiving Label")
    c.setAuthor("Swift Oilfield Supply")
    draw_label_page(c, sample, customer_logo, customer_logo2)
    c.save()
    return out_path


# From warehouse photo 20260801_124511 (ConocoPhillips skid)
SAMPLE = {
    "customer": "CONOCOPHILLIPS CANADA (BRC) PARTNERSHIP",
    "project": "Gateway Pipelines & CBR Pad 107 Lateral FEL3",
    "po_num": "278-07-31 - 0009",
    "sales_order": "1380380",
    "pm": "CHRIS ACORN",
    "date_received": "May 1st, 2026",
    "received_by": "Keith Blackman",
    "special_instructions": "Hold on dock until ship confirm. Do not break skid.",
}


def main() -> None:
    p = argparse.ArgumentParser(description="Swift Supply receiving label PDF (prototype).")
    p.add_argument("--logo", type=Path, help="Customer logo image (PNG/JPG)")
    p.add_argument("--logo2", type=Path, help="Optional second customer logo")
    p.add_argument("--out", type=Path, help="Output PDF path")
    p.add_argument(
        "--blank",
        action="store_true",
        help="Write a blank template (labels + lines only, no sample values)",
    )
    args = p.parse_args()

    if args.blank:
        out = args.out or (ROOT / "Swift Supply Receiving Label.pdf")
        print(build_pdf({}, out_path=out, customer_logo=args.logo, customer_logo2=args.logo2))
    else:
        out = args.out or (
            ROOT / "Swift Supply Receiving Label - Sample (ConocoPhillips).pdf"
        )
        print(build_pdf(SAMPLE, out_path=out, customer_logo=args.logo, customer_logo2=args.logo2))
        # Also write empty template beside it
        print(build_pdf({}, out_path=ROOT / "Swift Supply Receiving Label.pdf", customer_logo=args.logo, customer_logo2=args.logo2))


if __name__ == "__main__":
    main()
