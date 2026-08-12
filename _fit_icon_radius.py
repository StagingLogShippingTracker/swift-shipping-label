import io
import math
import subprocess

from PIL import Image


def fit_radius(im: Image.Image) -> float:
    im = im.convert("RGBA")
    a = im.split()[-1]
    bbox = a.getbbox()
    assert bbox
    x0, y0, x1, y1 = bbox
    # Content is roughly square
    # Walk from top-left content corner: for y = y0.. find first opaque x
    # For a round rect of radius r inset at (x0,y0), boundary satisfies
    # for t in 0..r: opaque starts near x0 + r - sqrt(r^2 - (r-t)^2)
    pts = []
    for t in range(0, min(x1 - x0, y1 - y0) // 3):
        y = y0 + t
        row_start = None
        for x in range(x0, x1):
            if a.getpixel((x, y)) >= 128:
                row_start = x
                break
        if row_start is None:
            continue
        pts.append((t, row_start - x0))
    # Fit r: for each t, expected inset = r - sqrt(r^2 - (r-t)^2) when t<=r else 0
    best_r, best_err = 0, 1e18
    max_r = min(x1 - x0, y1 - y0) // 2
    for r in range(8, max_r):
        err = 0.0
        n = 0
        for t, inset in pts:
            if t > r:
                expected = 0.0
            else:
                expected = r - math.sqrt(max(0.0, r * r - (r - t) * (r - t)))
            err += (inset - expected) ** 2
            n += 1
        err /= max(n, 1)
        if err < best_err:
            best_err = err
            best_r = r
    w = im.size[0]
    content_w = x1 - x0
    return best_r, best_err, best_r / w, best_r / content_w, bbox


raw = subprocess.check_output(
    ["git", "show", "44f8b99:mobile/windows/runner/resources/app_icon.ico"]
)
im = Image.open(io.BytesIO(raw))
print("old_ico", fit_radius(im))

raw = subprocess.check_output(
    ["git", "show", "43be6f8:mobile/assets/images/app_icon_1024.png"]
)
im = Image.open(io.BytesIO(raw))
print("old_png", fit_radius(im))
