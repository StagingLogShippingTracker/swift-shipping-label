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

Set-Location (Join-Path $Root "mobile")
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
& $Flutter build windows --release
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
Write-Host "Windows app: $out\swift_shipping_label.exe"
