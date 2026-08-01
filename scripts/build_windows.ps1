# Build Flutter Windows release into dist\Swift Shipping Label\
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Flutter = Join-Path $env:USERPROFILE "Downloads\swift-staging-tracker\.tools\flutter\bin\flutter.bat"
if (-not (Test-Path $Flutter)) { $Flutter = "flutter" }

Set-Location (Join-Path $Root "mobile")
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$built = Join-Path $Root "mobile\build\windows\x64\runner\Release"
$out = Join-Path $Root "dist\Swift Shipping Label"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
Copy-Item $built $out -Recurse
Write-Host "Windows app: $out\swift_shipping_label.exe"
