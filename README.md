# Swift Supply — Shipping Label Generator

Windows portable app + Android Flutter client that pre-fills a shipping label and writes a print-ready PDF. Long PO / Project values wrap and Special Instructions shrinks so nothing is hidden when printing.

**Repo:** https://github.com/StagingLogShippingTracker/swift-shipping-label  
**Version:** `1.0.0` (`version.py` / `mobile/pubspec.yaml` `1.0.0+1`)

## No admin / no install (Windows)

| | |
|--|--|
| Install location | **None** — portable folder only |
| Program Files | **Do not use** |
| Elevation | **Not required** |
| Shortcut | Your user Desktop only |
| Writable data | `%LOCALAPPDATA%\SwiftShippingLabel\` |

## Run (dev)

```bash
python fill_shipping_label.py
```

(Dev mode keeps presets/logos/filled PDFs in this project folder.)

Android:

```bash
cd mobile
flutter pub get
flutter run
```

Prefer building from `%LOCALAPPDATA%\swift-shipping-label-mobile` when that checkout is in use (avoids OneDrive/Gradle lock fights).

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
