# Swift Document Generator

Swift Oilfield Supply warehouse documents for **Windows** and **Android**:

1. **Shipping Label** — Swiss print PDF; multi-page piece counts  
2. **Receiving Label** — staging skid label  
3. **Bill of Lading** — straight BOL (3 copies), ported from `generate_swift_bol_pdf.py`

## Run (Windows)

| | |
|--|--|
| App | `dist\Swift Document Generator\swift_shipping_label.exe` |
| Launch | **Launch Swift Document Generator.vbs** (no console) |

```powershell
.\scripts\build_windows.ps1
.\Launch Swift Document Generator.vbs
```

## Update

In-app **Update** downloads from GitHub Releases:

- `SwiftDocumentGenerator-windows.zip`
- `SwiftDocumentGenerator-android.apk`

## Publish

```powershell
.\scripts\publish_release.ps1
```

Android builds prefer `%LOCALAPPDATA%\swift-document-generator-mobile` (synced from `mobile/`), falling back to `swift-shipping-label-mobile` or the repo `mobile/` tree.

## BOL source

Python reference generator (also in this repo):

`C:\Users\Brice\OneDrive\Documents\generate_swift_bol_pdf.py` → copied as `generate_swift_bol_pdf.py`

## Data

Presets, logos, and filled PDFs live under the app documents folder  
`swift_document_generator\` (migrated automatically from `swift_shipping_label\` when present).

Filenames: `SL-` / `RL-` / `BOL-` + customer + sales order, with `(1)`, `(2)` on collision.
