# Build Windows portable zip + Android APK and publish a GitHub Release.
#
# Usage:
#   .\scripts\publish_release.ps1
#   .\scripts\publish_release.ps1 -Version 1.1.0
#
# Assets:
#   SwiftDocumentGenerator-Setup.exe  (preferred for in-app Update)
#   SwiftDocumentGenerator-windows.zip
#   SwiftDocumentGenerator-android.apk
param(
    [string]$Version = "",
    [switch]$SkipWindows,
    [switch]$SkipAndroid,
    [switch]$Draft
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-VersionFromPy {
    $text = Get-Content (Join-Path $root "version.py") -Raw
    if ($text -match '__version__\s*=\s*"([^"]+)"') { return $Matches[1] }
    throw "Could not parse version.py"
}

function Invoke-Flutter([string]$Flutter, [string[]]$CmdArgs) {
    # Gradle/KGP write warnings to stderr; don't treat as terminating errors.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Flutter @CmdArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $_.ToString()
            } else {
                Write-Host $_
            }
        }
        if ($LASTEXITCODE -ne 0) {
            throw "flutter $($CmdArgs -join ' ') failed (exit $LASTEXITCODE)"
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Sync-AppDataMobile {
    $src = Join-Path $root "mobile"
    foreach ($name in @("swift-document-generator-mobile", "swift-shipping-label-mobile")) {
        $dest = Join-Path $env:LOCALAPPDATA $name
        if (-not (Test-Path (Join-Path $dest "pubspec.yaml"))) { continue }
        Write-Host "Syncing $src -> $dest"
        robocopy $src $dest /MIR /XD build .dart_tool .idea /XF *.iml /NFL /NDL /NJH /NJS /NC /NS | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy sync to $dest failed ($LASTEXITCODE)" }
    }
}

function Set-VersionEverywhere([string]$ver) {
    if ($ver -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version must be semver X.Y.Z (got: $ver)"
    }
    $py = Join-Path $root "version.py"
    (Get-Content $py -Raw) -replace '__version__\s*=\s*"[^"]+"', "__version__ = `"$ver`"" |
        Set-Content -Path $py -Encoding UTF8 -NoNewline

    $pub = Join-Path $root "mobile\pubspec.yaml"
    $pubText = Get-Content $pub -Raw
    if ($pubText -match 'version:\s*([\d.]+)\+(\d+)') {
        $build = [int]$Matches[2]
        $newBuild = $build + 1
        $pubText = $pubText -replace 'version:\s*[\d.]+\+\d+', "version: $ver+$newBuild"
        Set-Content -Path $pub -Value $pubText -Encoding UTF8 -NoNewline
        Write-Host "pubspec.yaml -> $ver+$newBuild"
    } else {
        throw "Could not parse mobile/pubspec.yaml version"
    }

    foreach ($name in @("swift-document-generator-mobile", "swift-shipping-label-mobile")) {
        $appDataPub = Join-Path $env:LOCALAPPDATA "$name\pubspec.yaml"
        if (Test-Path $appDataPub) {
            $ad = Get-Content $appDataPub -Raw
            if ($ad -match 'version:\s*([\d.]+)\+(\d+)') {
                $b = [int]$Matches[2] + 1
                $ad = $ad -replace 'version:\s*[\d.]+\+\d+', "version: $ver+$b"
                Set-Content -Path $appDataPub -Value $ad -Encoding UTF8 -NoNewline
            }
        }
    }
}

if (-not $Version) { $Version = Get-VersionFromPy }
$explicitVersion = $PSBoundParameters.ContainsKey("Version") -and $Version
if ($explicitVersion) {
    Set-VersionEverywhere $Version
} else {
    Write-Host "Using existing version $Version (pass -Version to bump pubspec build)"
}

$tag = "v$Version"
Write-Host "Publishing release $tag"

& (Join-Path $root "scripts\sync_calibri_fonts.ps1")
Sync-AppDataMobile

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$assets = @()

if (-not $SkipWindows) {
    Write-Host "`n=== Windows portable (Flutter) ==="
    & (Join-Path $root "scripts\build_windows.ps1")
    $onedir = Join-Path $dist "Swift Document Generator"
    $exe = Join-Path $onedir "swift_shipping_label.exe"
    if (-not (Test-Path $exe)) {
        throw "Windows build missing: $exe"
    }
    @"
Swift Document Generator (portable Flutter)

- Run: swift_shipping_label.exe
- Generators: Shipping Label, Receiving Label, Bill of Lading, Bulk Labels (Propak)
- No install, no admin rights required
- Do not put this folder in C:\Program Files
- Data (presets, logos, PDFs): app documents\swift_document_generator\

Copy this entire folder to any work PC (Documents / Desktop / USB) and run.
"@ | Set-Content -Path (Join-Path $onedir "README-PORTABLE.txt") -Encoding UTF8
    $zip = Join-Path $dist "SwiftDocumentGenerator-windows.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path $onedir -DestinationPath $zip -CompressionLevel Optimal
    $assets += $zip
    Write-Host "Windows asset: $zip"

    Write-Host "`n=== Windows installer (Inno Setup) ==="
    & (Join-Path $root "scripts\build_windows_installer.ps1")
    $setup = Join-Path $dist "SwiftDocumentGenerator-Setup.exe"
    if (-not (Test-Path $setup)) {
        throw "Windows installer missing: $setup"
    }
    $assets += $setup
    Write-Host "Windows installer asset: $setup"
}

if (-not $SkipAndroid) {
    Write-Host "`n=== Android APK ==="
    $mobileRoot = Join-Path $env:LOCALAPPDATA "swift-document-generator-mobile"
    if (-not (Test-Path (Join-Path $mobileRoot "pubspec.yaml"))) {
        $mobileRoot = Join-Path $env:LOCALAPPDATA "swift-shipping-label-mobile"
    }
    if (-not (Test-Path (Join-Path $mobileRoot "pubspec.yaml"))) {
        $mobileRoot = Join-Path $root "mobile"
    }
    Write-Host "Building from: $mobileRoot"

    $flutter = $null
    foreach ($c in @(
        (Join-Path $root ".tools\flutter\bin\flutter.bat"),
        (Join-Path $env:LOCALAPPDATA "swift-staging-tracker\.tools\flutter\bin\flutter.bat"),
        (Join-Path $env:USERPROFILE "Downloads\swift-staging-tracker\.tools\flutter\bin\flutter.bat"),
        "flutter"
    )) {
        if ($c -eq "flutter") { $flutter = "flutter"; break }
        if (Test-Path $c) { $flutter = $c; break }
    }
    if (-not $flutter) { throw "Flutter SDK not found" }

    Push-Location $mobileRoot
    try {
        . (Join-Path $root "scripts\flutter_dart_defines.ps1")
        $dartDefines = Get-FlutterDartDefines -RepoRoot $root
        if ($dartDefines.Count -gt 0) {
            Write-Host "Including $($dartDefines.Count) dart-define(s) from .env"
        }
        Invoke-Flutter $flutter @("pub", "get")
        Invoke-Flutter $flutter (@("build", "apk", "--release") + $dartDefines)
        $apkSrc = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $apkSrc)) {
            $apkSrc = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
        }
        if (-not (Test-Path $apkSrc)) { throw "APK not found under build/app/outputs/flutter-apk" }
        $apkDest = Join-Path $dist "SwiftDocumentGenerator-android.apk"
        Copy-Item -Force $apkSrc $apkDest
        $assets += $apkDest
        Write-Host "Android asset: $apkDest"
    } finally {
        Pop-Location
    }
}

if ($assets.Count -eq 0) { throw "No assets to publish" }

Write-Host "`n=== GitHub Release $tag ==="
$releaseExists = $false
try {
    gh release view $tag 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $releaseExists = $true }
} catch {
    $releaseExists = $false
}

$title = "Swift Document Generator $Version"
$notes = @"
## Swift Document Generator $Version

### What's new (v1.1.77)
- **MORE APPS:** rail footer title (not Operations apps); tile stays under Shipping / Receiving / BOL / Bulk on Windows and Android

### What's new (v1.1.76)
- **MORE APPS:** expanded side rail advertises Swift Staging & Shipping Log — launch if installed, otherwise download Setup/APK and start install
- **Address book:** OSM fills missing city/province/postal; same ship-to with different couriers stays as separate rows
- **History:** prune deletes snapshot-less rows and their PDFs (and logos) from Supabase Storage

### What's new (v1.1.75)
- **OA fill:** Shipping, Receiving, and BOL can upload a Swift Order Acknowledgement under Customer preset
- **Fields:** sales order, customer PO / project, Bill To customer; packing list stays blank
- **Ship-to:** Delivery Instructions when present; otherwise Use OA Ship To or enter manually

### What's new (v1.1.74)
- **Address book:** lists Z–A by Ship To Name; duplicate places merge in the cloud
- **History logos:** each saved version opens the PDF (and logo) that was actually generated
- **Also:** high-res logo restore targets height; square logos crop empty padding

### What's new (v1.1.73)
- **Logo search:** Serper.dev image API (no Google/Bing HTML scraping); Clearbit/Brandfetch still run in parallel
- **High-res logos:** checkbox to convert a low-res customer photo to 3000px+ (replaces Recreate)
- **Templates:** Shipping/Receiving no longer re-prompt on Generate; prompt stays after entering the customer name
- **History:** generated PDFs older than 90 days are deleted from the app cache and Supabase

### Also in recent releases
- Gemini logo restore (Windows/Android); local Python RealESRGAN offline; Recreate/vectorizer removed
- Bulk OA CPO LINE parsing, looser customer-name matching
- Android portrait Chrome-like header; landscape Windows-style rail layout

### Assets
- SwiftDocumentGenerator-Setup.exe - Windows installer (per-user, no admin; Start Menu, uninstaller). Preferred for in-app Update.
- SwiftDocumentGenerator-windows.zip - portable Flutter onedir. Run swift_shipping_label.exe.
- SwiftDocumentGenerator-android.apk - Android install package.

### In-app Update
Windows: downloads Setup.exe and launches it.
Android: downloads and opens the APK installer.
"@

if ($releaseExists) {
    Write-Host "Release $tag exists - uploading/replacing assets..."
    foreach ($a in $assets) {
        gh release upload $tag $a --clobber
    }
} else {
    $createArgs = @("release", "create", $tag) + $assets + @("--title", $title, "--notes", $notes)
    if ($Draft) { $createArgs += "--draft" }
    & gh @createArgs
}

Write-Host ""
Write-Host "Published: https://github.com/StagingLogShippingTracker/swift-shipping-label/releases/tag/$tag"
Write-Host "Latest API: https://api.github.com/repos/StagingLogShippingTracker/swift-shipping-label/releases/latest"
