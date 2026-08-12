"""Measure round-rect radius on historical rounded app icons."""
import io
import subprocess

from PIL import Image


def measure_radius(im: Image.Image) -> int:
    im = im.convert("RGBA")
    w, h = im.size
    # Walk from top-left along first opaque pixel on diagonal-ish: find first
    # opaque pixel on top row from left, then estimate radius as that x.
    for x in range(w):
        if im.getpixel((x, 0))[3] >= 128:
            # Not rounded if edge is opaque
            return 0
    # Find first opaque along left edge from top
    for y in range(h):
        if im.getpixel((0, y))[3] >= 128:
            # radius approx = y (start of solid edge)
            r_edge = y
            break
    else:
        return -1
    # Refine: for each y in 0..r, find first opaque x; expect circle equation
    samples = []
    for y in range(r_edge + 1):
        for x in range(w):
            if im.getpixel((x, y))[3] >= 128:
                samples.append((x, y))
                break
    # Fit circle center (r,r): (x-r)^2 + (y-r)^2 ~= r^2 for boundary
    # Use max x among samples near top as rough estimate via r_edge
    return r_edge


raw = subprocess.check_output(
    ["git", "show", "44f8b99:mobile/windows/runner/resources/app_icon.ico"]
)
im = Image.open(io.BytesIO(raw)).convert("RGBA")
im.save("_qa_icon_old_rounded.png")
print("old ico", im.size, "radius_px", measure_radius(im), "ratio", measure_radius(im) / im.size[0])

raw = subprocess.check_output(
    ["git", "show", "43be6f8:mobile/assets/images/app_icon_1024.png"]
)
png = Image.open(io.BytesIO(raw)).convert("RGBA")
png.resize((256, 256), Image.Resampling.LANCZOS).save("_qa_icon_old_png256.png")
print("old png", png.size, "radius_px", measure_radius(png), "ratio", measure_radius(png) / png.size[0])

# Also check current content - does it have charcoal full bleed?
cur = Image.open("mobile/assets/images/app_icon_1024.png").convert("RGBA")
print("current corner pixel", cur.getpixel((0, 0)), "center", cur.getpixel((512, 512)))
