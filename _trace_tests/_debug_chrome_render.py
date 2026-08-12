import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
svg_text = (ROOT / "_test_orange.svg").read_text(encoding="utf-8")
with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
    f.write(
        "<!DOCTYPE html><html><body style='margin:0;background:#000'>"
        f"{svg_text}</body></html>"
    )
    html = Path(f.name)

out = ROOT / "_test_render.png"
chrome = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
r = subprocess.run(
    [
        str(chrome),
        "--headless=new",
        "--disable-gpu",
        f"--screenshot={out}",
        "--window-size=2987,1045",
        html.as_uri(),
    ],
    capture_output=True,
    text=True,
)
print("rc", r.returncode)
print("stderr", r.stderr[:2000])
print("exists", out.exists(), out.stat().st_size if out.exists() else 0)
