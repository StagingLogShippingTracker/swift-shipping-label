"""
Check GitHub Releases and download the Windows portable zip (per-user).

Mirrors the staging-tracker Settings → Update pattern, adapted for the
portable onedir layout (no installer / no admin).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import urllib.error
import urllib.request
import webbrowser
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from version import (
    ANDROID_APK_ASSET,
    GITHUB_RELEASES_API,
    GITHUB_RELEASES_PAGE,
    WINDOWS_ZIP_ASSET,
    __version__,
)

ProgressCb = Callable[[float], None] | None


@dataclass(frozen=True)
class AppVersion:
    major: int
    minor: int
    patch: int
    build: int = 0

    @classmethod
    def try_parse(cls, raw: str) -> AppVersion | None:
        cleaned = (raw or "").strip()
        if not cleaned:
            return None
        m = re.search(r"(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?", cleaned)
        if not m:
            return None
        return cls(
            int(m.group(1)),
            int(m.group(2)),
            int(m.group(3)),
            int(m.group(4) or 0),
        )

    def compare_to(self, other: AppVersion) -> int:
        for a, b in (
            (self.major, other.major),
            (self.minor, other.minor),
            (self.patch, other.patch),
            (self.build, other.build),
        ):
            if a != b:
                return (a > b) - (a < b)
        return 0

    def is_newer_than(self, other: AppVersion) -> bool:
        return self.compare_to(other) > 0

    def __str__(self) -> str:
        base = f"{self.major}.{self.minor}.{self.patch}"
        return f"{base}+{self.build}" if self.build else base


@dataclass
class ReleaseInfo:
    tag_name: str
    name: str
    html_url: str
    windows_zip_url: str | None = None
    android_apk_url: str | None = None

    @property
    def version(self) -> AppVersion | None:
        return AppVersion.try_parse(self.tag_name) or AppVersion.try_parse(self.name)

    def is_newer_than_installed(self, installed: str) -> bool:
        remote = self.version
        local = AppVersion.try_parse(installed)
        if remote is None or local is None:
            return False
        return remote.is_newer_than(local)


@dataclass
class UpdateCheckResult:
    latest: ReleaseInfo
    update_available: bool
    missing_windows_asset: bool = False


def updates_dir() -> Path:
    local = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    path = Path(local) / "SwiftShippingLabel" / "updates"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _classify_asset(name: str) -> str | None:
    lower = name.strip().lower()
    if not lower:
        return None
    if lower.endswith(".zip") and (
        "windows" in lower or lower == WINDOWS_ZIP_ASSET.lower()
    ):
        return "windows"
    if lower.endswith(".apk") and (
        "android" in lower
        or lower == ANDROID_APK_ASSET.lower()
        or lower == "swiftshippinglabel.apk"
        or "-debug.apk" in lower
        or lower.endswith("-release.apk")
    ):
        return "android"
    return None


def fetch_latest_release() -> ReleaseInfo:
    req = urllib.request.Request(
        GITHUB_RELEASES_API,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "SwiftShippingLabel",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            body = json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            raise RuntimeError("No GitHub releases published yet.") from e
        raise RuntimeError(f"Could not check for updates (HTTP {e.code}).") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Could not reach GitHub: {e.reason}") from e

    if not isinstance(body, dict):
        raise RuntimeError("Unexpected release payload.")

    windows_url = None
    android_url = None
    assets = body.get("assets") or []
    if isinstance(assets, list):
        for raw in assets:
            if not isinstance(raw, dict):
                continue
            name = str(raw.get("name") or "").strip()
            url = str(raw.get("browser_download_url") or "").strip()
            if not name or not url:
                continue
            kind = _classify_asset(name)
            if kind == "windows":
                windows_url = url
            elif kind == "android":
                android_url = url

    return ReleaseInfo(
        tag_name=str(body.get("tag_name") or "").strip(),
        name=str(body.get("name") or body.get("tag_name") or "Latest").strip(),
        html_url=str(body.get("html_url") or GITHUB_RELEASES_PAGE).strip(),
        windows_zip_url=windows_url,
        android_apk_url=android_url,
    )


def check_for_update(installed_version: str | None = None) -> UpdateCheckResult:
    installed = installed_version or __version__
    latest = fetch_latest_release()
    newer = latest.is_newer_than_installed(installed)
    has_win = bool(latest.windows_zip_url)
    return UpdateCheckResult(
        latest=latest,
        update_available=newer and has_win,
        missing_windows_asset=newer and not has_win,
    )


def download_file(
    url: str,
    dest: Path,
    on_progress: ProgressCb = None,
) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        dest.unlink()

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "SwiftShippingLabel"},
    )
    with urllib.request.urlopen(req, timeout=120) as res:
        total = int(res.headers.get("Content-Length") or 0)
        received = 0
        with dest.open("wb") as out:
            while True:
                chunk = res.read(64 * 1024)
                if not chunk:
                    break
                out.write(chunk)
                received += len(chunk)
                if on_progress and total > 0:
                    on_progress(min(1.0, received / total))
        if on_progress:
            on_progress(1.0)

    if not dest.exists() or dest.stat().st_size == 0:
        raise RuntimeError("Download produced an empty file.")
    return dest


def download_windows_update(
    release: ReleaseInfo,
    on_progress: ProgressCb = None,
) -> Path:
    url = release.windows_zip_url
    if not url:
        raise RuntimeError("No Windows zip asset on this release.")

    dest_zip = updates_dir() / WINDOWS_ZIP_ASSET
    download_file(url, dest_zip, on_progress=on_progress)

    extract_root = updates_dir() / f"extracted-{release.tag_name or 'latest'}"
    if extract_root.exists():
        shutil.rmtree(extract_root, ignore_errors=True)
    extract_root.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(dest_zip, "r") as zf:
        zf.extractall(extract_root)

    return extract_root


def open_releases_page(release: ReleaseInfo | None = None) -> None:
    url = (release.html_url if release and release.html_url else GITHUB_RELEASES_PAGE)
    webbrowser.open(url)


def open_folder(path: Path) -> None:
    path = path.resolve()
    if path.is_file():
        path = path.parent
    os.startfile(str(path))  # type: ignore[attr-defined]


def installed_version() -> str:
    return __version__
