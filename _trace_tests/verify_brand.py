"""Verify regenerated brand SVG against source PNG."""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from process_header_logo import APP_ORANGE_HEX  # noqa: E402

CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
BRAND = ROOT / "assets" / "brand"


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
    orange_svg = BRAND / "swift_supply_logo_orange.svg"
    text = orange_svg.read_text(encoding="utf-8")
    dim = re.search(r'width="(\d+)"\s+height="(\d+)"', text)
    view = re.search(r'viewBox="([^"]+)"', text)
    print("svg width/height", dim.groups() if dim else None)
    print("viewBox", view.group(1) if view else None)
    print("paths", text.count("<path"), "bytes", orange_svg.stat().st_size)
    print("fill", APP_ORANGE_HEX, "count", text.count(APP_ORANGE_HEX))

    out = ROOT / "_verify_orange_from_svg.png"
    render_svg(orange_svg, out)
    print("rendered", out, out.stat().st_size)


if __name__ == "__main__":
    main()
