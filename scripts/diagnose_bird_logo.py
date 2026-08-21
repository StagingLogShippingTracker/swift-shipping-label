"""Diagnose bird logo: black-bg removal vs dark green ink."""
from __future__ import annotations

import shutil
from collections import Counter
from pathlib import Path

from PIL import Image

OUT = Path(r"C:\Users\Brice\Projects\swift_document_generator\filled\bird_diag")
OUT.mkdir(parents=True, exist_ok=True)
logo_src = Path(r"C:\Users\Brice\Projects\swift_document_generator\customer_logos\bird_source.png")
im = Image.open(logo_src).convert("RGBA")
w, h = im.size
print(f"source: {logo_src.name} {w}x{h}")

px = list(im.getdata())


def bucket(p):
    r, g, b, a = p
    if a < 40:
        return "transparent"
    if r < 40 and g < 40 and b < 40:
        return "near_black"
    sat = max(r, g, b) - min(r, g, b)
    if r > 180 and g < 140 and b < 100 and sat > 40:
        return "orange"
    if g >= r and g >= b and g > 30:
        return "greenish"
    if r > 240 and g > 240 and b > 240:
        return "white"
    return "other"


print("buckets:", Counter(bucket(p) for p in px))

# Sample green letter pixels (scan for saturated dark green)
greens = []
blacks = []
oranges = []
for y in range(h):
    for x in range(w):
        r, g, b, a = im.getpixel((x, y))
        if a < 40:
            continue
        sat = max(r, g, b) - min(r, g, b)
        dist_black = max(r, g, b)  # max-channel distance from (0,0,0)
        if r > 180 and g < 140 and b < 100 and sat > 40:
            oranges.append((r, g, b, dist_black, sat))
        elif g >= r and g >= b and g > 25 and sat > 15:
            greens.append((r, g, b, dist_black, sat))
        elif r < 40 and g < 40 and b < 40:
            blacks.append((r, g, b, dist_black, sat))

print(f"green samples: {len(greens)}  orange: {len(oranges)}  black: {len(blacks)}")
if greens:
    # percentiles of distance-from-black
    dists = sorted(g[3] for g in greens)
    sats = sorted(g[4] for g in greens)
    print(
        "green dist_black min/p10/med/p90/max:",
        dists[0],
        dists[len(dists) // 10],
        dists[len(dists) // 2],
        dists[9 * len(dists) // 10],
        dists[-1],
    )
    print(
        "green sat min/med/max:",
        sats[0],
        sats[len(sats) // 2],
        sats[-1],
    )
    print("example greens:", greens[len(greens) // 4], greens[len(greens) // 2])
    within_26 = sum(1 for g in greens if g[3] <= 26)
    within_40 = sum(1 for g in greens if g[3] <= 40)
    print(f"green pixels with dist_black<=26: {within_26}/{len(greens)}")
    print(f"green pixels with dist_black<=40: {within_40}/{len(greens)}")

# Simulate current Dart logic: bg=black, remove if dist<=26 OR near-black when bg black
TOL = 26


def is_empty(p, bg=(0, 0, 0)):
    r, g, b, a = p
    if a < 12:
        return True
    if r >= 240 and g >= 240 and b >= 240:
        return True
    dist = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
    if dist <= TOL:
        return True
    if bg[0] <= 32 and bg[1] <= 32 and bg[2] <= 32 and r <= 32 and g <= 32 and b <= 32:
        return True
    return False


surv = Image.new("RGBA", (w, h), (0, 0, 0, 0))
kept = 0
for y in range(h):
    for x in range(w):
        p = im.getpixel((x, y))
        if not is_empty(p):
            surv.putpixel((x, y), p)
            kept += 1
surv.save(OUT / "bird_after_black_remove_sim.png")
print(f"kept after black-remove sim: {kept}/{w*h}")
# bbox of kept
xs, ys = [], []
for y in range(h):
    for x in range(w):
        if surv.getpixel((x, y))[3] >= 96:
            xs.append(x)
            ys.append(y)
if xs:
    print(f"surviving bbox: {min(xs)},{min(ys)} -> {max(xs)},{max(ys)} size {max(xs)-min(xs)+1}x{max(ys)-min(ys)+1}")
    crop = surv.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    crop.save(OUT / "bird_surviving_crop.png")
    print("surviving crop aspect", round(crop.size[0] / crop.size[1], 3))
else:
    print("NOTHING survived")
