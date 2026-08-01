"""
Launch the Swift Shipping Label Windows app (Flutter desktop).

No Tk UI, no console window. Falls back to building if the Release exe
is missing.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MOBILE = ROOT / "mobile"
EXE_CANDIDATES = [
    ROOT
    / "dist"
    / "Swift Shipping Label"
    / "swift_shipping_label.exe",
    MOBILE
    / "build"
    / "windows"
    / "x64"
    / "runner"
    / "Release"
    / "swift_shipping_label.exe",
]


def _find_exe() -> Path | None:
    for p in EXE_CANDIDATES:
        if p.is_file():
            return p
    return None


def main() -> int:
    exe = _find_exe()
    if exe is None:
        # Dev convenience: run Flutter Windows (may show a brief console)
        flutter = (
            Path.home()
            / "Downloads"
            / "swift-staging-tracker"
            / ".tools"
            / "flutter"
            / "bin"
            / "flutter.bat"
        )
        if not flutter.is_file():
            print("Swift Shipping Label.exe not found. Build with:")
            print("  cd mobile && flutter build windows --release")
            return 1
        return subprocess.call(
            [str(flutter), "run", "-d", "windows", "--release"],
            cwd=str(MOBILE),
        )

    # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP — no console parent
    flags = 0x00000008 | 0x00000200
    subprocess.Popen(
        [str(exe)],
        cwd=str(exe.parent),
        close_fds=True,
        creationflags=flags,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
