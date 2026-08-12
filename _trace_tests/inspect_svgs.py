import re
from pathlib import Path

for name in ["test_0.svg", "test_1.svg"]:
    text = (Path(__file__).parent / name).read_text(encoding="utf-8")
    dim = re.search(r'width="(\d+)"\s+height="(\d+)"', text)
    print(name, "dim", dim.groups() if dim else None, "paths", text.count("<path"))
    for index, match in enumerate(re.finditer(r'transform="translate\(([^)]+)\)"', text)):
        print(" ", index, match.group(1)[:50])
