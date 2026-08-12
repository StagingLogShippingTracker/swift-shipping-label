"""Temporary helper to render SVG previews for trace comparison."""
from __future__ import annotations

from pathlib import Path

from playwright.sync_api import sync_playwright


def svg_to_png(svg_path: Path, png_path: Path, width: int = 2987) -> None:
    svg = svg_path.read_text(encoding="utf-8")
    html = (
        "<!DOCTYPE html><html><body style='margin:0;background:#000'>"
        f"{svg}</body></html>"
    )
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": 1000})
        page.set_content(html)
        element = page.locator("svg").first
        box = element.bounding_box()
        height = int(box["height"] * width / box["width"])
        page.set_viewport_size({"width": width, "height": height})
        element.screenshot(path=str(png_path))
        browser.close()
    print(f"wrote {png_path}")


if __name__ == "__main__":
    outdir = Path(__file__).parent
    root = outdir.parent
    for index in range(3):
        svg_to_png(outdir / f"test_{index}.svg", outdir / f"test_{index}.png")
    svg_to_png(
        root / "assets/brand/swift_supply_logo_orange.svg",
        outdir / "current_orange_svg.png",
    )
