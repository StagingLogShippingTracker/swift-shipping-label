# Build SwiftDocumentGenerator-Setup.exe with Inno Setup (requires dist\Swift Document Generator\).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

$sourceDir = Join-Path $Root "dist\Swift Document Generator"
$exe = Join-Path $sourceDir "swift_shipping_label.exe"
if (-not (Test-Path $exe)) {
    throw "Windows release folder missing. Run scripts\build_windows.ps1 first.`nExpected: $exe"
}

function Find-InnoCompiler {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 7\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 7\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe")
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$iscc = Find-InnoCompiler
if (-not $iscc) {
    Write-Host "Inno Setup not found. Installing via winget..."
    winget install JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "winget install Inno Setup failed (exit $LASTEXITCODE)" }
    $iscc = Find-InnoCompiler
    if (-not $iscc) { throw "Inno Setup installed but ISCC.exe not found." }
}

$iss = Join-Path $Root "installer\SwiftDocumentGenerator.iss"
if (-not (Test-Path $iss)) { throw "Missing installer script: $iss" }

Write-Host "Compiling installer with: $iscc"
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compile failed (exit $LASTEXITCODE)" }

$setup = Join-Path $Root "dist\SwiftDocumentGenerator-Setup.exe"
if (-not (Test-Path $setup)) { throw "Installer output missing: $setup" }
Write-Host "Windows installer: $setup"
