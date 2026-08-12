import re
import sys
import tempfile
from pathlib import Path

import numpy as np
import vtracer
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from process_header_logo import (  # noqa: E402
    _pick_source,
    _prepare_trace_mask,
    render_white_logo,
    BRAND_TARGET_WIDTH,
    _is_full_frame_path,
)

white = render_white_logo(_pick_source(None), BRAND_TARGET_WIDTH)
mask, trace_size, _ = _prepare_trace_mask(white)
with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
    tmp_path = Path(tmp.name)
Image.fromarray(mask).save(tmp_path)
raw_svg = ROOT / "_trace_tests" / "raw_vtracer.svg"
vtracer.convert_image_to_svg_py(
    str(tmp_path),
    str(raw_svg),
    colormode="binary",
    hierarchical="stacked",
    mode="spline",
    filter_speckle=0,
    corner_threshold=120,
    length_threshold=4.0,
    splice_threshold=45,
    path_precision=8,
)
tmp_path.unlink(missing_ok=True)

text = raw_svg.read_text(encoding="utf-8")
tw, th = trace_size
print("raw paths", text.count("<path"))
for index, match in enumerate(re.finditer(r'd="([^"]+)"', text)):
    data = match.group(1)
    first_sub = data.split(" Z")[0] if " Z" in data else data[:500]
    print(
        index,
        "len",
        len(first_sub),
        "C",
        first_sub.count("C"),
        "full?",
        _is_full_frame_path(data, tw, th),
    )
