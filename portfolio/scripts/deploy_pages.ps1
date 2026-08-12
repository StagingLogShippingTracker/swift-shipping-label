# Redeploy GitHub Pages from local Flutter web builds.
# Usage (from portfolio repo root):
#   .\scripts\deploy_pages.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$flutter = "C:\Users\Brice\OneDrive\Documents\swift_document_generator\.tools\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
  $flutter = "flutter"
}

Push-Location "$root\apps\sdg_web_demo"
& $flutter pub get
& $flutter build web --release --base-href "/portfolio/demos/sdg/"
Pop-Location

Push-Location "$root\apps\slst_web_demo"
& $flutter pub get
& $flutter build web --release --base-href "/portfolio/demos/slst/"
Pop-Location

$site = Join-Path $root "_site"
Remove-Item $site -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$site\demos\sdg", "$site\demos\slst" | Out-Null
Copy-Item "$root\site\index.html" "$site\index.html" -Force
Copy-Item "$root\apps\sdg_web_demo\build\web\*" "$site\demos\sdg\" -Recurse -Force
Copy-Item "$root\apps\slst_web_demo\build\web\*" "$site\demos\slst\" -Recurse -Force

$tmp = Join-Path $env:TEMP "portfolio-gh-pages"
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Copy-Item "$site\*" $tmp -Recurse -Force

Push-Location $tmp
git init
git config user.name "StagingLogShippingTracker"
git config user.email "289869979+StagingLogShippingTracker@users.noreply.github.com"
git checkout -b gh-pages
git add .
git commit -m "Deploy portfolio GitHub Pages site"
git remote add origin https://github.com/StagingLogShippingTracker/portfolio.git
git push -f origin gh-pages
Pop-Location

Write-Host "Published: https://staginglogshippingtracker.github.io/portfolio/"
