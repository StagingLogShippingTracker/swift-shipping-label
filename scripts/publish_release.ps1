# Build Windows portable zip + Android APK and publish a GitHub Release.
#
# Usage:
#   .\scripts\publish_release.ps1              # uses version.py / pubspec 1.0.0
#   .\scripts\publish_release.ps1 -Version 1.0.1
#   .\scripts\publish_release.ps1 -SkipAndroid  # Windows asset only
#   .\scripts\publish_release.ps1 -SkipWindows
#
# Assets uploaded:
#   SwiftShippingLabel-windows.zip
#   SwiftShippingLabel-android.apk
#
# Requires: gh auth, Python, Flutter (for Android), network.
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

    $appDataPub = Join-Path $env:LOCALAPPDATA "swift-shipping-label-mobile\pubspec.yaml"
    if (Test-Path $appDataPub) {
        $ad = Get-Content $appDataPub -Raw
        if ($ad -match 'version:\s*([\d.]+)\+(\d+)') {
            $b = [int]$Matches[2] + 1
            $ad = $ad -replace 'version:\s*[\d.]+\+\d+', "version: $ver+$b"
            Set-Content -Path $appDataPub -Value $ad -Encoding UTF8 -NoNewline
        }
    }
}

if (-not $Version) { $Version = Get-VersionFromPy }
# When publishing the same version already in version.py, do not auto-bump pubspec
# unless -Version was explicitly passed. First release keeps 1.0.0+1.
$explicitVersion = $PSBoundParameters.ContainsKey("Version") -and $Version
if ($explicitVersion) {
    Set-VersionEverywhere $Version
} else {
    Write-Host "Using existing version $Version (pass -Version to bump pubspec build)"
}

$tag = "v$Version"
Write-Host "Publishing release $tag"

& (Join-Path $root "scripts\sync_calibri_fonts.ps1")

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$assets = @()

if (-not $SkipWindows) {
    Write-Host "`n=== Windows portable (Flutter) ==="
    & (Join-Path $root "scripts\build_windows.ps1")
    $onedir = Join-Path $dist "Swift Shipping Label"
    $exe = Join-Path $onedir "swift_shipping_label.exe"
    if (-not (Test-Path $exe)) {
        throw "Windows build missing: $exe"
    }
    @"
Swift Supply - Shipping Label (portable Flutter)

- Run: swift_shipping_label.exe
- No install, no admin rights required
- Do not put this folder in C:\Program Files
- Data (presets, logos, PDFs): %LOCALAPPDATA%\SwiftShippingLabel\

Copy this entire folder to any work PC (Documents / Desktop / USB) and run.
"@ | Set-Content -Path (Join-Path $onedir "README-PORTABLE.txt") -Encoding UTF8
    $zip = Join-Path $dist "SwiftShippingLabel-windows.zip"
    if (Test-Path $zip) { Remove-Item -Force $zip }
    Compress-Archive -Path $onedir -DestinationPath $zip -CompressionLevel Optimal
    $assets += $zip
    Write-Host "Windows asset: $zip"
}

if (-not $SkipAndroid) {
    Write-Host "`n=== Android APK ==="
    $mobileRoot = Join-Path $env:LOCALAPPDATA "swift-shipping-label-mobile"
    if (-not (Test-Path (Join-Path $mobileRoot "pubspec.yaml"))) {
        $mobileRoot = Join-Path $root "mobile"
    }
    Write-Host "Building from: $mobileRoot"

    $flutter = $null
    foreach ($c in @(
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
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
        & $flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
        $apkSrc = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $apkSrc)) {
            $apkSrc = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-debug.apk"
        }
        if (-not (Test-Path $apkSrc)) { throw "APK not found under build/app/outputs/flutter-apk" }
        $apkDest = Join-Path $dist "SwiftShippingLabel-android.apk"
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

$title = "Swift Shipping Label $Version"
$notes = @"
## Swift Shipping Label $Version

### What's new
- Auto-save PDFs as SL-/RL- + customer + sales order (with (1), (2) if needed)
- Shipping: ask pallet/crate and box counts, then one page per unit (1 of N)
- Up to 2 customer logos per label (primary + C/O)


### Assets
- SwiftShippingLabel-windows.zip - portable Flutter onedir (no admin). Extract and run swift_shipping_label.exe.
- SwiftShippingLabel-android.apk - Android install package.

### In-app Update
Windows and Android Update buttons check releases/latest and download the host-platform asset.
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
