"""Compare trace candidates against reference PNG."""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "_trace_tests"))

from verify_supply_letters import supply_letter_runs  # noqa: E402

CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
WIDTH = 2987
HEIGHT = 910


def render(svg_path: Path, png_path: Path) -> None:
    svg = svg_path.read_text(encoding="utf-8")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tmp:
        tmp.write(
            "<!DOCTYPE html><html><body style='margin:0;background:#000'>"
            f"{svg}</body></html>"
        )
        html_path = Path(tmp.name)
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            f"--window-size={WIDTH},{HEIGHT}",
            f"--screenshot={png_path}",
            html_path.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    html_path.unlink(missing_ok=True)


def main() -> None:
    ref = Image.open(ROOT / "assets" / "brand" / "swift_supply_logo_orange.png").convert("RGBA")
    ref_runs = supply_letter_runs(ref)
    print("REF", len(ref_runs), ref_runs)

    candidates = [
        ROOT / "assets" / "brand" / "swift_supply_logo_orange.svg",
        ROOT / "_trace_tests" / "vtracer_cutout_u3_proc.svg",
        ROOT / "_trace_tests" / "potrace_test.svg",
        ROOT / "_trace_tests" / "sweep_u3_c1_cutout_fs0_ct120.svg",
    ]
    for svg in candidates:
        if not svg.is_file():
            continue
        out = ROOT / "_trace_tests" / f"cmp_{svg.stem}.png"
        render(svg, out)
        runs = supply_letter_runs(Image.open(out).convert("RGBA"))
        p_ok = len(runs) >= 3 and abs(runs[2][0] - ref_runs[2][0]) < 120
        print(
            svg.name,
            "letters",
            len(runs),
            "P_ok" if p_ok else "P_MISSING",
            "runs",
            runs[:6],
        )


if __name__ == "__main__":
    main()
