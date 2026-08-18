"""Scale full-window captures for the promo carousel — no crop, no pad."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
IMG = ROOT / "assets" / "images"
CACHE = ROOT.parent / ".cache" / "slst"
SHOTS = CACHE / "shots"
ICON_SRC = (
    ROOT.parent.parent
    / "Swift-Staging-and-Shipping-Log"
    / "assets"
    / "swift-staging-log-app-icon.png"
)
if not ICON_SRC.is_file():
    ICON_SRC = (
        CACHE
        / "portable"
        / "data"
        / "flutter_assets"
        / "assets"
        / "swift-staging-log-app-icon.png"
    )

TARGET_W = 1600


def scale_full_window(im: Image.Image) -> Image.Image:
    """Keep the entire app window; scale width only so aspect stays native."""
    w, h = im.size
    if w == TARGET_W:
        return im
    scale = TARGET_W / w
    return im.resize((TARGET_W, max(1, int(h * scale))), Image.Resampling.LANCZOS)


def save_still(src: Path, dest_name: str) -> None:
    im = Image.open(src).convert("RGB")
    out = scale_full_window(im)
    path = IMG / dest_name
    out.save(path, "PNG", optimize=True)
    print(f"wrote {path.name} from {src.name} {im.size} -> {out.size} (full window)")


def main() -> None:
    if not ICON_SRC.is_file():
        raise SystemExit(f"Missing app icon: {ICON_SRC}")

    icon_dest = IMG / "slst_app_icon.png"
    icon = Image.open(ICON_SRC).convert("RGBA")
    icon.save(icon_dest, "PNG", optimize=True)
    print(f"wrote {icon_dest.name} from {ICON_SRC.name} ({icon.size[0]}x{icon.size[1]})")

    save_still(SHOTS / "01_initial.png", "slst_still_dashboard.png")
    save_still(SHOTS / "nav_dashboard.png", "slst_still_staging.png")

    warehouse_src = SHOTS / "floor_bay_dialog.png"
    if warehouse_src.is_file():
        save_still(warehouse_src, "slst_still_warehouse.png")
    else:
        save_still(SHOTS / "01_initial.png", "slst_still_warehouse.png")

    save_still(SHOTS / "nav_staging.png", "slst_still_shipped.png")


if __name__ == "__main__":
    main()
