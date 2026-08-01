# Build Swift Shipping Label as a portable Windows app (NO admin / NO installer)
#
# Output lives under this user-owned project folder:
#   dist\Swift Shipping Label\Swift Shipping Label.exe
#
# Copy that whole folder anywhere the user can write (Documents, Desktop,
# USB). Do NOT install to Program Files.
#
# Runtime data (presets, logos, filled PDFs) goes to:
#   %LOCALAPPDATA%\SwiftShippingLabel\
#
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Running elevated. This build does not need admin - prefer a normal user PowerShell."
}

Write-Host "Installing/updating PyInstaller + deps (user scope)..."
python -m pip install -q --upgrade --user pip pyinstaller reportlab pypdf

Write-Host "Building portable onedir - windowed, no installer..."
python -m PyInstaller --noconfirm "SwiftShippingLabel.spec"
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed with exit code $LASTEXITCODE. Close the app if it is running, then retry."
}

$outDir = Join-Path $PSScriptRoot "dist\Swift Shipping Label"
$exe = Join-Path $outDir "Swift Shipping Label.exe"
if (-not (Test-Path $exe)) {
    throw "Build finished but exe not found: $exe"
}

@"
Swift Supply - Shipping Label (portable)

- Run: Swift Shipping Label.exe
- No install, no admin rights required
- Do not put this folder in C:\Program Files
- Your data (presets, logos, PDFs) is stored in:
  %LOCALAPPDATA%\SwiftShippingLabel\

Copy this entire folder to any work PC (Documents / Desktop / USB) and run.
"@ | Set-Content -Path (Join-Path $outDir "README-PORTABLE.txt") -Encoding UTF8

Write-Host ""
Write-Host "Built portable: $exe"

$desktop = [Environment]::GetFolderPath("Desktop")
if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE "Desktop" }
$link = Join-Path $desktop "Swift Shipping Label.lnk"
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($link)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $outDir
$sc.IconLocation = $exe
$sc.Description = "Swift Supply Shipping Label Generator (portable, per-user)"
$sc.Save()
Write-Host "User Desktop shortcut: $link"
Write-Host "Runtime data: $env:LOCALAPPDATA\SwiftShippingLabel\"
Write-Host "Done - no admin, no Program Files."
