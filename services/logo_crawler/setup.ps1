# Install Playwright + Chromium for the Swift Find-logo Google Images crawler.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Installing Python deps..."
python -m pip install -r requirements.txt

Write-Host "Installing Chromium for Playwright..."
python -m playwright install chromium

Write-Host "Smoke test: DHV logo"
python crawl_google_images.py --query "DHV logo" --max 24
