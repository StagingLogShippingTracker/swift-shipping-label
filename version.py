"""Embedded app version for Windows Update checks (semver)."""

__version__ = "1.0.2"
APP_NAME = "Swift Shipping Label"
GITHUB_OWNER = "StagingLogShippingTracker"
GITHUB_REPO = "swift-shipping-label"
GITHUB_RELEASES_API = (
    f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest"
)
GITHUB_RELEASES_PAGE = (
    f"https://github.com/{GITHUB_OWNER}/{GITHUB_REPO}/releases"
)

# Release asset names (must match scripts/publish_release.ps1)
WINDOWS_ZIP_ASSET = "SwiftShippingLabel-windows.zip"
ANDROID_APK_ASSET = "SwiftShippingLabel-android.apk"
