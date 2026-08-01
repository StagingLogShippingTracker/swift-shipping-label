"""
Resolve bundled assets vs writable app data (dev + frozen .exe).

Portable / per-user only — never Program Files, never admin elevation.
Writable data always lives under the current user's profile.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

APP_DATA_NAME = "SwiftShippingLabel"


def bundle_dir() -> Path:
    """Read-only assets shipped with the app (fonts, Swift logo)."""
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent


def exe_dir() -> Path:
    """Folder containing the .exe (or project root in dev). For launching only."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def data_dir() -> Path:
    """
    Writable per-user data: presets, logos, filled PDFs.

    Frozen: %LOCALAPPDATA%\\SwiftShippingLabel\\
    Dev: project folder (convenient for development)
    Override: SWIFT_LABEL_DATA env var
    """
    override = os.environ.get("SWIFT_LABEL_DATA", "").strip()
    if override:
        return Path(override).expanduser()

    if getattr(sys, "frozen", False):
        local = os.environ.get("LOCALAPPDATA") or str(
            Path.home() / "AppData" / "Local"
        )
        return Path(local) / APP_DATA_NAME

    return Path(__file__).resolve().parent


# Back-compat alias used by PDF generator for writable outputs
def app_dir() -> Path:
    return data_dir()


def user_desktop() -> Path:
    """Current user's Desktop only (never all-users)."""
    try:
        import ctypes.wintypes

        CSIDL_DESKTOP = 0
        SHGFP_TYPE_CURRENT = 0
        buf = ctypes.create_unicode_buffer(ctypes.wintypes.MAX_PATH)
        ctypes.windll.shell32.SHGetFolderPathW(
            None, CSIDL_DESKTOP, None, SHGFP_TYPE_CURRENT, buf
        )
        p = Path(buf.value)
        if p.is_dir():
            return p
    except Exception:
        pass
    for candidate in (
        Path.home() / "Desktop",
        Path.home() / "OneDrive" / "Desktop",
    ):
        if candidate.is_dir():
            return candidate
    return Path.home() / "Desktop"


def ensure_data_dirs() -> dict[str, Path]:
    root = data_dir()
    logos = root / "customer_logos"
    filled = root / "filled"
    presets = root / "presets.json"
    logos.mkdir(parents=True, exist_ok=True)
    filled.mkdir(parents=True, exist_ok=True)
    return {
        "app": root,
        "data": root,
        "exe": exe_dir(),
        "bundle": bundle_dir(),
        "logos": logos,
        "filled": filled,
        "presets": presets,
    }
