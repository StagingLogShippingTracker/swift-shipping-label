"""Report transparency stats for a set of PNGs."""

import sys
from pathlib import Path
from PIL import Image


def stats(path: Path) -> None:
    with Image.open(path) as im:
        im = im.convert("RGBA")
        w, h = im.size
        a = im.getchannel("A")
        pixels = w * h
        transparent = sum(1 for v in a.getdata() if v < 32)
        pct = 100.0 * transparent / pixels
        print(f"{path.name:35s}  {w:5d}x{h:<5d}  {pct:6.2f}% transparent")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        stats(Path(arg))
