"""DEPRECATED: fabricated PIL mockups — do not run for shipping assets.

Real promo stills come from Windows captures processed by
`process_slst_promo_stills.py` (see `.cache/slst/shots/`).

Compose high-res Staging Log promo stills from real brand assets."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
IMG = ROOT / "assets" / "images"
ICON = IMG / "slst_app_icon.png"
MARK = IMG / "slst_mark.png"

BG = (18, 20, 23, 255)
SURFACE = (28, 31, 36, 255)
HEADER = (22, 25, 30, 255)
BORDER = (46, 51, 58, 255)
INK = (242, 240, 236, 255)
MUTED = (163, 162, 156, 255)
ACCENT = (206, 78, 48, 255)
TODAY = (201, 138, 58, 255)
PARTIAL = (90, 140, 170, 255)
RUSH = (196, 72, 72, 255)
OK = (80, 150, 110, 255)


def font(size: int, bold: bool = False):
    for name in (
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
    ):
        p = Path(name)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def rounded(draw, xy, r, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def paste_icon(im: Image.Image, xy, size=72):
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    im.alpha_composite(icon, xy)


def chrome_bar(im: Image.Image, title: str):
    d = ImageDraw.Draw(im)
    rounded(d, (16, 16, im.width - 16, 78), 10, HEADER, BORDER)
    paste_icon(im, (28, 22), 48)
    d.text((88, 26), "SWIFT STAGING & SHIPPING LOG", font=font(13, True), fill=ACCENT)
    d.text((88, 46), title, font=font(20, True), fill=INK)


def save(im: Image.Image, name: str):
    path = IMG / name
    im.convert("RGB").save(path, "PNG", optimize=True)
    print(path, im.size)


def dashboard():
    im = Image.new("RGBA", (1600, 900), BG)
    d = ImageDraw.Draw(im)
    chrome_bar(im, "Dashboard")
    cards = [
        ("RUSH / HOTSHOT", "3", RUSH),
        ("SHIP TODAY", "8", TODAY),
        ("IN STAGING", "24", ACCENT),
        ("SHIPPED TODAY", "11", OK),
    ]
    x = 28
    for label, value, color in cards:
        rounded(d, (x, 100, x + 370, 250), 12, SURFACE, BORDER)
        d.rectangle((x, 100, x + 8, 250), fill=color)
        d.text((x + 28, 122), label, font=font(14, True), fill=MUTED)
        d.text((x + 28, 156), value, font=font(52, True), fill=INK)
        x += 390
    # staging board columns
    cols = [
        ("RUSH", [("SO-4412", "Arc Resources", "A-04")]),
        ("TODAY", [("SO-4418", "GCM", "C-12"), ("SO-4421", "Propak", "STAGE")]),
        ("PARTIAL", [("SO-4420", "Worley", "N-18")]),
        ("AWAITING", [("SO-4390", "Shell", "B-02")]),
    ]
    x = 28
    for title, rows in cols:
        rounded(d, (x, 272, x + 370, 860), 12, SURFACE, BORDER)
        d.text((x + 18, 288), title, font=font(16, True), fill=ACCENT)
        y = 330
        for so, cust, loc in rows:
            rounded(d, (x + 14, y, x + 356, y + 92), 8, HEADER, BORDER)
            d.text((x + 28, y + 14), so, font=font(16, True), fill=INK)
            d.text((x + 28, y + 40), cust, font=font(14), fill=MUTED)
            d.text((x + 28, y + 62), loc, font=font(12, True), fill=ACCENT)
            y += 108
        x += 390
    if MARK.exists():
        mark = Image.open(MARK).convert("RGBA")
        mark.thumbnail((220, 170), Image.Resampling.LANCZOS)
        im.alpha_composite(mark, (im.width - mark.width - 36, im.height - mark.height - 28))
    save(im, "slst_still_dashboard.png")


def staging_log():
    im = Image.new("RGBA", (1600, 900), BG)
    d = ImageDraw.Draw(im)
    chrome_bar(im, "Active Staging Entries Log")
    rounded(d, (20, 96, 1580, 880), 12, SURFACE, BORDER)
    headers = ["SO", "CUSTOMER", "STATUS", "LOCATION", "QTY", "STAGED BY"]
    xs = [40, 220, 520, 820, 1120, 1280]
    for h, xx in zip(headers, xs):
        d.text((xx, 118), h, font=font(13, True), fill=MUTED)
    d.line((36, 150, 1564, 150), fill=BORDER, width=1)
    rows = [
        ("SO-4412", "Arc Resources", "RUSH / HOTSHOT", "A-04-A-1", "2", "Brice", RUSH),
        ("SO-4418", "GCM", "SHIP TODAY", "C-12-B-2", "3", "Jordan", TODAY),
        ("SO-4420", "Propak", "PARTIAL", "STAGE-01", "1", "Brice", PARTIAL),
        ("SO-4424", "Worley Cord", "SHIP TOMORROW", "N-18-C-1", "4", "Alex", ACCENT),
        ("SO-4431", "RETI / Shell", "AWAITING", "B-02-A-1", "2", "Sam", MUTED),
    ]
    y = 168
    for i, (so, cust, st, loc, qty, by, color) in enumerate(rows):
        if i % 2:
            d.rectangle((28, y - 8, 1572, y + 72), fill=HEADER)
        vals = [so, cust, st, loc, qty, by]
        for v, xx in zip(vals, xs):
            fill = color if v == st else INK
            d.text((xx, y + 16), v, font=font(16, True if xx == 40 else False), fill=fill)
        y += 84
    save(im, "slst_still_staging.png")


def warehouse():
    im = Image.new("RGBA", (1600, 1000), BG)
    d = ImageDraw.Draw(im)
    chrome_bar(im, "Warehouse floor map")
    rounded(d, (20, 96, 1580, 980), 12, (69, 75, 85, 255), BORDER)
    aisles = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    seat = 18
    gap = 3
    ox, oy = 56, 140
    occupied = {("A", 4): RUSH, ("C", 12): TODAY, ("N", 18): PARTIAL, ("B", 2): ACCENT}
    for ai, letter in enumerate(aisles):
        y = oy + ai * (seat + gap)
        d.text((28, y), letter, font=font(11, True), fill=INK)
        bays = 12 if letter >= "O" else 30
        for b in range(bays):
            x = ox + b * (seat + gap)
            if letter >= "O" and b > 11:
                continue
            color = occupied.get((letter, b + 1), (90, 96, 106, 255))
            d.rounded_rectangle((x, y, x + seat - 1, y + seat - 1), radius=2, fill=color)
    d.text((56, 940), "Occupied bins from live staging — aisle A–Z / seats 02–30", font=font(14), fill=INK)
    save(im, "slst_still_warehouse.png")


def shipped():
    im = Image.new("RGBA", (1600, 820), BG)
    d = ImageDraw.Draw(im)
    chrome_bar(im, "Shipped Staging Entries Log")
    rounded(d, (20, 96, 1580, 800), 12, SURFACE, BORDER)
    headers = ["SO", "CUSTOMER", "CARRIER", "SHIPPED", "PM"]
    xs = [40, 240, 560, 920, 1280]
    for h, xx in zip(headers, xs):
        d.text((xx, 118), h, font=font(13, True), fill=MUTED)
    d.line((36, 150, 1564, 150), fill=BORDER, width=1)
    rows = [
        ("SO-8849", "GCM", "Murray's Trucking", "Aug 14, 3:10 PM", "Jordan"),
        ("SO-8831", "Arc Resources", "Dunrite", "Aug 14, 11:02 AM", "Brice"),
        ("SO-8804", "Propak", "Day & Ross", "Aug 13, 4:44 PM", "Alex"),
    ]
    y = 172
    for so, cust, car, when, pm in rows:
        for v, xx in zip((so, cust, car, when, pm), xs):
            d.text((xx, y), v, font=font(16, True if xx == 40 else False), fill=INK)
        y += 70
    d.text((40, 430), "Outbound confirmed. Photos and PM email stay on the same record.", font=font(15), fill=MUTED)
    paste_icon(im, (1480, 700), 64)
    save(im, "slst_still_shipped.png")


if __name__ == "__main__":
    dashboard()
    staging_log()
    warehouse()
    shipped()
