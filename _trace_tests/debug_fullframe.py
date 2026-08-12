import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from process_header_logo import _is_full_frame_path

text = Path(__file__).parent.joinpath("sweep_u2_c1_cutout_fs0_ct120.svg").read_text(encoding="utf-8")
for index, match in enumerate(re.finditer(r'd="([^"]+)"', text)):
    data = match.group(1)
    print(
        index,
        "fullframe",
        _is_full_frame_path(data, 5974, 1820),
        "starts M0 0",
        data.startswith("M0 0"),
        "has5974",
        "5974" in data[:500],
        "C count",
        data[:500].count("C"),
    )
