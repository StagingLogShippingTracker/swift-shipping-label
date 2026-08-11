#!/usr/bin/env python3
"""Deploy master app icon to Flutter asset paths, Android mipmaps, adaptive icons, Windows ICO."""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
# Canonical sharp master lives in-repo as a full-bleed square. Rounded corners
# with transparent outside are applied when exporting Windows ICO / launcher
# bitmaps so the desktop icon is a rounded square again (not a hard square).
MASTER_CANDIDATES = [
    MOBILE / "assets" / "images" / "app_icon_1024.png",
]

# Android density → launcher px
MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Adaptive foreground is typically 108dp canvas with ~72dp safe zone.
ADAPTIVE_FG = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

ACCENT = (0xCE, 0x4E, 0x30, 255)
CHARCOAL = (0x14, 0x16, 0x18, 255)

# Match the pre-regression Windows icon silhouette (git 44f8b99):
# ~4.3% transparent margin + ~28.6% corner radius of the plate (~22% of canvas).
ICON_INSET_RATIO = 0.043
ICON_RADIUS_OF_PLATE = 0.286


def find_master() -> Path:
    for p in MASTER_CANDIDATES:
        if p.is_file():
            return p
    raise SystemExit("No master icon found")


def square_contain(img: Image.Image, size: int, bg=(0, 0, 0, 0)) -> Image.Image:
    img = img.convert("RGBA")
    canvas = Image.new("RGBA", (size, size), bg)
    # Leave ~18% safe padding for adaptive / rounded masks.
    pad = int(size * 0.14)
    inner = size - pad * 2
    fitted = img.copy()
    fitted.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def rounded_square_icon(
    img: Image.Image,
    size: int | None = None,
    *,
    inset_ratio: float = ICON_INSET_RATIO,
    radius_of_plate: float = ICON_RADIUS_OF_PLATE,
) -> Image.Image:
    """Bake a rounded-square silhouette with transparent corners.

    Windows does not round arbitrary .ico files the way Android adaptive icons
    do — the previous sharp icon used transparent rounded corners. Filling the
    master onto an opaque charcoal square removed that silhouette.
    """
    img = img.convert("RGBA")
    if size is not None and img.size != (size, size):
        img = img.resize((size, size), Image.Resampling.LANCZOS)
    w, h = img.size

    # Solid charcoal plate under any existing transparency (tiny-size clarity).
    plate = Image.new("RGBA", (w, h), CHARCOAL)
    plate.paste(img, (0, 0), img)

    inset = max(0, int(round(min(w, h) * inset_ratio)))
    plate_w = w - 2 * inset
    plate_h = h - 2 * inset
    radius = max(1, int(round(min(plate_w, plate_h) * radius_of_plate)))

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (inset, inset, w - 1 - inset, h - 1 - inset),
        radius=radius,
        fill=255,
    )
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(plate, (0, 0), mask)
    return out


def write_ico(src: Image.Image, dest: Path) -> None:
    """Write a multi-resolution rounded ICO (16..256) with transparent corners.

    Pillow's ``append_images`` ICO path often emits only a single 16x16 frame
    (the blurry Windows window/taskbar icon). Passing one large image with an
    explicit ``sizes=`` list is the reliable API.
    """
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    dest.parent.mkdir(parents=True, exist_ok=True)
    icon = rounded_square_icon(src, 256)
    icon.save(dest, format="ICO", sizes=sizes)


def main() -> None:
    master_path = find_master()
    master = Image.open(master_path).convert("RGBA")
    print(f"Master: {master_path} ({master.size})")

    assets = MOBILE / "assets" / "images"
    assets.mkdir(parents=True, exist_ok=True)
    # Keep the 1024 master full-bleed (source of truth for adaptive FG).
    master_out = assets / "app_icon_1024.png"
    master_1024 = master.resize((1024, 1024), Image.Resampling.LANCZOS)
    master_1024.save(master_out, "PNG")
    # Desktop / in-app preview asset uses the rounded silhouette.
    rounded_512 = rounded_square_icon(master, 512)
    rounded_512.save(assets / "app_icon.png", "PNG")
    print(f"Wrote {master_out}")
    print(f"Wrote {assets / 'app_icon.png'} (rounded)")

    branding = ROOT / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    rounded_512.save(branding / "app_icon.png", "PNG")
    print(f"Wrote {branding / 'app_icon.png'} (rounded)")

    res = MOBILE / "android" / "app" / "src" / "main" / "res"

    # Legacy launcher icons — rounded so older launchers match Windows.
    for folder, px in MIPMAPS.items():
        out = res / folder / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        rounded_square_icon(master, px).save(out, "PNG")
        print(f"Wrote {out}")

    # Adaptive background color resource
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#141618</color>\n'
        '    <color name="swift_accent">#CE4E30</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    # Adaptive foreground drawables (padded safe zone; OS applies the mask)
    last_fg: Path | None = None
    for folder, px in ADAPTIVE_FG.items():
        out = res / folder / "ic_launcher_foreground.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        square_contain(master, px, bg=(0, 0, 0, 0)).save(out, "PNG")
        last_fg = out
        print(f"Wrote {out}")
    if last_fg is not None:
        # Default drawable/ used by mipmap-anydpi adaptive XML.
        default_fg = res / "drawable" / "ic_launcher_foreground.png"
        default_fg.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(last_fg, default_fg)
        print(f"Wrote {default_fg}")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    shutil.copy(anydpi / "ic_launcher.xml", anydpi / "ic_launcher_round.xml")
    print(f"Wrote adaptive icons in {anydpi}")

    ico = MOBILE / "windows" / "runner" / "resources" / "app_icon.ico"
    write_ico(master, ico)
    print(f"Wrote {ico} ({ico.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
