# Build Flutter Windows release into dist\Swift Document Generator\
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Flutter = $null
foreach ($c in @(
    (Join-Path $Root ".tools\flutter\bin\flutter.bat"),
    (Join-Path $env:LOCALAPPDATA "swift-staging-tracker\.tools\flutter\bin\flutter.bat"),
    (Join-Path $env:USERPROFILE "Downloads\swift-staging-tracker\.tools\flutter\bin\flutter.bat"),
    "flutter"
)) {
    if ($c -eq "flutter") { $Flutter = "flutter"; break }
    if (Test-Path $c) { $Flutter = $c; break }
}
if (-not $Flutter) { throw "Flutter SDK not found (install to $Root\.tools\flutter or PATH)" }

. (Join-Path $Root "scripts\flutter_dart_defines.ps1")
$dartDefines = Get-FlutterDartDefines -RepoRoot $Root
if ($dartDefines.Count -gt 0) {
    Write-Host "Including $($dartDefines.Count) dart-define(s) from .env"
}

Set-Location (Join-Path $Root "mobile")
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
& $Flutter build windows --release @dartDefines
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$built = Join-Path $Root "mobile\build\windows\x64\runner\Release"
$out = Join-Path $Root "dist\Swift Document Generator"
# Kill running app if locking files
Get-Process -Name "swift_shipping_label" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
# Also remove legacy dist folder name
$legacy = Join-Path $Root "dist\Swift Shipping Label"
if (Test-Path $legacy) { Remove-Item $legacy -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
Copy-Item $built $out -Recurse

# Bundle logo_restorer.py next to the exe for Windows RealESRGAN restore.
$restorerSrc = Join-Path $Root "logo_restorer.py"
if (Test-Path $restorerSrc) {
    Copy-Item $restorerSrc (Join-Path $out "logo_restorer.py") -Force
    Write-Host "Bundled logo_restorer.py"
}

Write-Host "Windows app: $out\swift_shipping_label.exe"
