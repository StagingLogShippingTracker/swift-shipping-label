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

# Bundle tools/ so the "Recreate" premium vectorizer (Python) is reachable
# from the packaged Windows app. `mobile\lib\logo_recreate.dart` probes for
# tools/logo_vectorizer/__main__.py next to the exe.
$toolsSrc = Join-Path $Root "tools"
$toolsDst = Join-Path $out "tools"
if (Test-Path $toolsSrc) {
    if (Test-Path $toolsDst) { Remove-Item $toolsDst -Recurse -Force }
    Copy-Item $toolsSrc $toolsDst -Recurse -Force
    # Never ship secrets from developer machines into portable/installer builds.
    Get-ChildItem $toolsDst -Recurse -Force -File -Filter ".env" |
        Remove-Item -Force -ErrorAction SilentlyContinue
    # Trim heavy caches so the zip stays small.
    Get-ChildItem $toolsDst -Recurse -Directory -Filter "__pycache__" |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $toolsDst -Recurse -Directory -Filter ".cache" |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Bundled tools/ (customer logo Recreate vectorizer; .env stripped)"
}

# Optional on-device Rust fallback (logo_recreate.dll) when already built.
# Flutter probes next to the exe; without this, offline Windows without
# Python skips straight toward Supabase last-resort.
$dllCandidates = @(
    (Join-Path $Root "native\logo_recreate\target\release\logo_recreate.dll"),
    (Join-Path $Root "native\logo_recreate\target\x86_64-pc-windows-msvc\release\logo_recreate.dll")
)
foreach ($dll in $dllCandidates) {
    if (Test-Path $dll) {
        Copy-Item $dll (Join-Path $out "logo_recreate.dll") -Force
        Write-Host "Bundled logo_recreate.dll from $dll"
        break
    }
}

Write-Host "Windows app: $out\swift_shipping_label.exe"
