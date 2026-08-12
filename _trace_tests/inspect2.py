import re
from pathlib import Path

text = Path(r"C:\Users\Brice\OneDrive\Documents\swift_document_generator\_trace_tests\sweep_u2_c1_cutout_fs0_ct120.svg").read_text(encoding="utf-8")
print("dim", re.search(r'width="(\d+)"\s+height="(\d+)"', text).groups())
print("paths", text.count("<path"))
for i, m in enumerate(re.finditer(r"<path[^>]+/>", text)):
    tag = m.group(0)
    d = re.search(r'd="([^"]{0,80})', tag)
    t = re.search(r'transform="([^"]+)"', tag)
    fill = re.search(r'fill="([^"]+)"', tag)
    print(i, "transform", t.group(1) if t else None, "fill", fill.group(1) if fill else None, "d", (d.group(1) if d else "")[:60])
