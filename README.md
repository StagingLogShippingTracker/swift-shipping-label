# Swift Supply — Shipping Label Generator

**Same Flutter UI on Windows and Android.** Pre-fill a shipping label → print-ready PDF. Long PO / Project values wrap and Special Instructions shrinks for print.

**Repo:** https://github.com/StagingLogShippingTracker/swift-shipping-label  
**Version:** `1.0.1` / Android `1.0.1+2`

## Windows (Flutter desktop — no Python UI)

| | |
|--|--|
| App | `dist\Swift Shipping Label\swift_shipping_label.exe` |
| Launch | Double-click **Launch Swift Shipping Label.vbs** or the Desktop shortcut (no console) |
| Build | `.\scripts\build_windows.ps1` |
| Update | Header **Update** → GitHub Releases |
| Writable data | App support under `%LOCALAPPDATA%` (Flutter path_provider) |

```powershell
.\scripts\build_windows.ps1
.\Launch Swift Shipping Label.vbs
```

`fill_shipping_label.py` is only a thin launcher for the Flutter exe (no Tk window).

## Android

```powershell
cd mobile
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Prefer building from `%LOCALAPPDATA%\swift-shipping-label-mobile` when that checkout is in use (avoids OneDrive/Gradle lock fights).

Header **Update** only (no body “Check for updates” card).

## Fonts

| Font | License | In git? |
|------|---------|---------|
| **Oswald** | SIL OFL | Yes (`fonts/`, `mobile/assets/fonts/`) |
| **Calibri** | Microsoft proprietary | **No** — copy from Windows Fonts |

```powershell
.\scripts\sync_calibri_fonts.ps1
```

PDF generation also falls back to `C:\Windows\Fonts\calibri.ttf` / `calibrib.ttf` if bundled Calibri is missing.

## Build portable .exe

```powershell
.\scripts\sync_calibri_fonts.ps1   # once per machine / clone
.\build_exe.ps1
```

Creates `dist\Swift Shipping Label\` — copy that whole folder to any work PC.

## In-app Update (GitHub Releases)

Both clients check:

`https://api.github.com/repos/StagingLogShippingTracker/swift-shipping-label/releases/latest`

| Platform | UI | Asset | Behavior |
|----------|----|-------|----------|
| **Windows** | Header **Update** | `SwiftShippingLabel-windows.zip` | Compares to `version.py` (`1.0.0`). Downloads to `%LOCALAPPDATA%\SwiftShippingLabel\updates\`, extracts, offers to open the folder so you can replace the portable onedir. No admin. |
| **Android** | Header update icon | `SwiftShippingLabel-android.apk` | Compares to `pubspec.yaml` version/build (`1.0.0+1`). Downloads into app-private storage and opens the system package installer. |

If you are already on the latest tag, the UI says you are up to date. **View releases** opens the GitHub releases page in a browser.

## Publish a release

```powershell
.\scripts\publish_release.ps1              # builds + gh release create vX.Y.Z
.\scripts\publish_release.ps1 -Version 1.0.1
.\scripts\publish_release.ps1 -SkipAndroid # Windows zip only
```

The script:

1. Syncs Calibri fonts  
2. Builds Windows onedir and zips it as `SwiftShippingLabel-windows.zip`  
3. Builds the Android release APK as `SwiftShippingLabel-android.apk`  
4. Creates (or refreshes) GitHub Release tag `vX.Y.Z` and uploads assets  

Bump versions by editing `version.py` / `mobile/pubspec.yaml`, or pass `-Version`.

## App features

- Customer presets (save / load / delete)
- Logo folder picker / import
- Desktop shortcut (current user only)
- Flat PDF generation with layout auto-fit
- In-app Update from GitHub Releases

## PDF generator (CLI)

```bash
python generate_swift_shipping_label_pdf.py
python generate_swift_shipping_label_pdf.py --logo path\to\logo.png
```
