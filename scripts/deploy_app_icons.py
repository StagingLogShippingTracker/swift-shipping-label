#!/usr/bin/env python3
"""Deploy master app icon to Flutter asset paths, Android mipmaps, adaptive icons, Windows ICO."""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile"
MASTER_CANDIDATES = [
    Path(
        r"C:\Users\Brice\.cursor\projects\c-Users-Brice-OneDrive-Documents-swift-document-generator\assets\app_icon_refined_1024.png"
    ),
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


def write_ico(src: Image.Image, dest: Path) -> None:
    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []
    for s in sizes:
        layer = Image.new("RGBA", (s, s), CHARCOAL)
        icon = src.convert("RGBA")
        icon.thumbnail((s, s), Image.Resampling.LANCZOS)
        x = (s - icon.width) // 2
        y = (s - icon.height) // 2
        layer.paste(icon, (x, y), icon)
        images.append(layer)
    dest.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(
        dest,
        format="ICO",
        sizes=[(im.width, im.height) for im in images],
        append_images=images[1:],
    )


def main() -> None:
    master_path = find_master()
    master = Image.open(master_path).convert("RGBA")
    print(f"Master: {master_path} ({master.size})")

    assets = MOBILE / "assets" / "images"
    assets.mkdir(parents=True, exist_ok=True)
    master_out = assets / "app_icon_1024.png"
    master.resize((1024, 1024), Image.Resampling.LANCZOS).save(master_out, "PNG")
    master.resize((512, 512), Image.Resampling.LANCZOS).save(
        assets / "app_icon.png", "PNG"
    )
    print(f"Wrote {master_out}")

    res = MOBILE / "android" / "app" / "src" / "main" / "res"

    # Legacy launcher icons (full bleed)
    for folder, px in MIPMAPS.items():
        out = res / folder / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        master.resize((px, px), Image.Resampling.LANCZOS).save(out, "PNG")
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

    # Adaptive foreground drawables (padded safe zone)
    for folder, px in ADAPTIVE_FG.items():
        out = res / folder / "ic_launcher_foreground.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        square_contain(master, px, bg=(0, 0, 0, 0)).save(out, "PNG")
        print(f"Wrote {out}")

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
    print(f"Wrote {ico}")


if __name__ == "__main__":
    main()
