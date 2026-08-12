"""Verify SUPPLY letter count in PNG vs rendered SVG."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from process_header_logo import APP_ORANGE_RGB  # noqa: E402

CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
BRAND = ROOT / "assets" / "brand"


def supply_letter_runs(img: Image.Image) -> list[tuple[int, int]]:
    h = img.height
    supply_y0 = int(h * 0.62)
    supply_y1 = int(h * 0.92)
    band = np.array(img)[supply_y0:supply_y1, :, 3]
    col = band.sum(axis=0)
    threshold = col.max() * 0.15
    in_letter = col > threshold
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for x, active in enumerate(in_letter):
        if active and start is None:
            start = x
        elif not active and start is not None:
            if x - start > 30:
                runs.append((start, x - 1))
            start = None
    if start is not None and img.width - start > 30:
        runs.append((start, img.width - 1))
    return runs


def render_svg(svg_path: Path, png_path: Path, width: int = 2987) -> None:
    svg = svg_path.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp.write(
            "<!DOCTYPE html><html><body style='margin:0;background:#000'>"
            f"{svg}</body></html>"
        )
        html_path = Path(tmp.name)
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            f"--window-size={width},{int(width * 0.35)}",
            f"--screenshot={png_path}",
            html_path.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    html_path.unlink(missing_ok=True)


def main() -> None:
    ref = Image.open(BRAND / "swift_supply_logo_orange.png").convert("RGBA")
    ref_runs = supply_letter_runs(ref)
    print("PNG SUPPLY letters:", len(ref_runs), ref_runs)

    out = ROOT / "_verify_orange_from_svg.png"
    render_svg(BRAND / "swift_supply_logo_orange.svg", out)
    svg_img = Image.open(out).convert("RGBA")
    svg_runs = supply_letter_runs(svg_img)
    print("SVG SUPPLY letters:", len(svg_runs), svg_runs)

    # P is 3rd letter (index 2) — check overlap
    if len(ref_runs) >= 3 and len(svg_runs) >= 3:
        ref_p = ref_runs[2]
        print("PNG P column:", ref_p)
        # Find closest SVG run to P
        for i, r in enumerate(svg_runs):
            overlap = min(ref_p[1], r[1]) - max(ref_p[0], r[0])
            print(f"  SVG run {i} {r} overlap={overlap}")


if __name__ == "__main__":
    main()
