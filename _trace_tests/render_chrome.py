"""Render SVG to PNG using headless Chrome."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")


def svg_to_png(svg_path: Path, png_path: Path, width: int = 2987) -> None:
    svg = svg_path.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp.write(
            "<!DOCTYPE html><html><body style='margin:0;background:#000'>"
            f"{svg}</body></html>"
        )
        html_path = Path(tmp.name)
    png_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            f"--window-size={width},1000",
            f"--screenshot={png_path}",
            html_path.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    html_path.unlink(missing_ok=True)
    print(f"wrote {png_path} ({png_path.stat().st_size} bytes)")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    out = root / "_trace_tests"
    cases = [
        out / "sweep_u2_c1_cutout_fs0_ct120.svg",
        out / "sweep_u3_c1_cutout_fs0_ct120.svg",
        root / "assets/brand/swift_supply_logo_orange.svg",
    ]
    for svg in cases:
        if svg.is_file():
            svg_to_png(svg, out / f"render_{svg.stem}.png")
