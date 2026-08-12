import io
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


def analyze(label: str, im: Image.Image) -> None:
    im = im.convert("RGBA")
    w, h = im.size
    # Bounding box of non-transparent pixels
    bbox = im.split()[-1].getbbox()
    print(f"{label}: size={w}x{h} opaque_bbox={bbox}")
    if not bbox:
        print("  fully transparent")
        return
    # Sample alpha along top of opaque region
    x0, y0, x1, y1 = bbox
    # Find radius: from (x0,y0) walk until solid interior
    # For each offset d from corner along axes
    # Check when diagonal from corner becomes opaque
    def alpha(x, y):
        if x < 0 or y < 0 or x >= w or y >= h:
            return 0
        return im.getpixel((x, y))[3]

    # Estimate radius from top-left of bbox: find max r where (x0+r, y0) and (x0, y0+r)
    # are near transparent boundary of a round rect
    # Walk top edge of bbox from left until fully opaque row of several pixels
    r_est = 0
    for r in range(1, min(w, h) // 2):
        # point on quarter-circle should be near opaque threshold
        # simpler: count transparent pixels in r x r corner of bbox
        trans = sum(
            1
            for yy in range(y0, y0 + r)
            for xx in range(x0, x0 + r)
            if alpha(xx, yy) < 128
        )
        if trans == 0:
            break
        r_est = r
    print(f"  corner_radius_est~={r_est} ({r_est / w:.3f} of width)")
    # Save with checker to see transparency
    preview = Image.new("RGBA", (w, h), (200, 200, 200, 255))
    preview.paste(im, (0, 0), im)
    preview.save(f"_qa_{label}_on_gray.png")


raw = subprocess.check_output(
    ["git", "show", "44f8b99:mobile/windows/runner/resources/app_icon.ico"]
)
analyze("old_ico", Image.open(io.BytesIO(raw)))

raw = subprocess.check_output(
    ["git", "show", "43be6f8:mobile/assets/images/app_icon_1024.png"]
)
analyze("old_png", Image.open(io.BytesIO(raw)))

analyze("current", Image.open("mobile/assets/images/app_icon_1024.png"))

# Visualize applying Win11-ish round rect (~22% radius common for rounded app icons)
src = Image.open("mobile/assets/images/app_icon_1024.png").convert("RGBA")
# Fill outside roundrect with transparency; keep charcoal inside
size = 256
base = src.resize((size, size), Image.Resampling.LANCZOS)
for ratio in (0.18, 0.22, 0.25):
    r = int(size * ratio)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    # checker preview
    chk = Image.new("RGBA", (size, size), (180, 180, 180, 255))
    chk.paste(out, (0, 0), out)
    chk.save(f"_qa_icon_round_{int(ratio*100)}.png")
    print("wrote", f"_qa_icon_round_{int(ratio*100)}.png", "r", r)
