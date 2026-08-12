import re
from pathlib import Path

for name in ["white_on_black_stacked_u2.svg", "white_on_black_cutout_u2.svg"]:
    text = (Path(__file__).parent / name).read_text(encoding="utf-8")
    print(name, "paths", text.count("<path"))
    for index, match in enumerate(re.finditer(r"<path[^>]+/>", text)):
        tag = match.group(0)
        d = re.search(r'd="([^"]{0,60})', tag)
        t = re.search(r'transform="([^"]+)"', tag)
        print(" ", index, "t", t.group(1)[:30] if t else "-", "d", d.group(1) if d else "")
