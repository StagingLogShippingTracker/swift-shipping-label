"""Render comparison PNGs for potrace sweep."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
WIDTH, HEIGHT = 2987, 910


def render(svg: Path, out: Path) -> None:
    html_body = svg.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp.write(
            "<!DOCTYPE html><html><body style='margin:0;background:#fff'>"
            f"{html_body}</body></html>"
        )
        html = Path(tmp.name)
    subprocess.run(
        [
            str(CHROME), "--headless=new", "--disable-gpu",
            f"--window-size={WIDTH},{HEIGHT}",
            f"--screenshot={out}", html.as_uri(),
        ],
        check=True, capture_output=True,
    )
    html.unlink(missing_ok=True)


def supply_cols(img: Image.Image) -> list[tuple[int, int]]:
    """Detect SUPPLY letter columns using orange-ish pixels."""
    arr = img.convert("RGBA")
    w, h = arr.size
    px = arr.load()
    y0, y1 = int(h * 0.62), int(h * 0.92)
    col = [0] * w
    for y in range(y0, y1):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 16 and r > 100 and r > g and r > b:
                col[x] += 1
    mx = max(col) if col else 1
    thr = mx * 0.15
    runs: list[tuple[int, int]] = []
    start = None
    for x, v in enumerate(col):
        if v > thr and start is None:
            start = x
        elif v <= thr and start is not None:
            if x - start > 30:
                runs.append((start, x - 1))
            start = None
    if start is not None and w - start > 30:
        runs.append((start, w - 1))
    return runs


def main() -> None:
    ref = ROOT / "assets" / "brand" / "swift_supply_logo_orange.png"
    ref_runs = supply_cols(Image.open(ref))
    print("REF", len(ref_runs), ref_runs)
    for svg in sorted((ROOT / "_trace_tests").glob("pot_u3*.svg")):
        out = ROOT / "_trace_tests" / f"vis_{svg.stem}.png"
        render(svg, out)
        runs = supply_cols(Image.open(out))
        print(svg.name, "letters", len(runs), runs)


if __name__ == "__main__":
    main()
