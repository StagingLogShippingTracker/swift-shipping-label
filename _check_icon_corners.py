import io
import subprocess
from pathlib import Path

from PIL import Image


def corner_stats(im: Image.Image) -> str:
    im = im.convert("RGBA")
    w, h = im.size
    corners = [im.getpixel(c)[3] for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    box = max(1, w // 10)
    trans = sum(
        1
        for y in range(box)
        for x in range(box)
        if im.getpixel((x, y))[3] < 128
    )
    return f"size={im.size} corner_a={corners} corner10_trans={trans}/{box*box}"


revs = ["HEAD", "v1.1.64", "v1.1.61", "v1.1.60", "44f8b99", "1db059d", "43be6f8", "841ace5"]
for rev in revs:
    try:
        raw = subprocess.check_output(
            ["git", "show", f"{rev}:mobile/windows/runner/resources/app_icon.ico"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        print(rev, "ico MISSING")
        continue
    im = Image.open(io.BytesIO(raw))
    print(f"{rev} ico bytes={len(raw)} {corner_stats(im)}")

for rev in ["HEAD", "v1.1.61", "v1.1.50", "43be6f8", "841ace5"]:
    try:
        raw = subprocess.check_output(
            ["git", "show", f"{rev}:mobile/assets/images/app_icon_1024.png"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        print(rev, "png MISSING")
        continue
    im = Image.open(io.BytesIO(raw))
    print(f"{rev} png bytes={len(raw)} {corner_stats(im)}")

# Save a preview of current vs apply rounded mask experiment
src = Image.open("mobile/assets/images/app_icon_1024.png").convert("RGBA")
src.resize((256, 256), Image.Resampling.LANCZOS).save("_qa_icon_current_square.png")
print("wrote _qa_icon_current_square.png")
