# Real Windows-app Find-logo: Tools > Find logo > type > Enter > wait for Choose a logo
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 75,
  [int]$MaxMinutes = 16
)
$ErrorActionPreference = "Stop"
. (Join-Path $Root "qa_logs\win_logo_hour\_win32.ps1")
Add-Type -AssemblyName System.Drawing

$companies = @(
  "Sureus Murphy","BFL","Whitecap","Arjae Design Solutions",
  "Paramount Resources","Suncor","Warren Valve",
  "Shell","ATCO","EPCOR","Arc Resources LTD","DNOW"
)

$outDir = Join-Path $Root "qa_logs\win_logo_20m"
$roundDir = Join-Path $outDir "gui_r3"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Cap([IntPtr]$H, [string]$P) {
  1..2 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 80 }
  Capture-WindowShot -Hwnd $H -Path $P | Out-Null
}

function Open-Find([IntPtr]$H) {
  Click-Rel -Hwnd $H -Fx 0.50 -Fy 0.11 | Out-Null
  Start-Sleep -Milliseconds 200
  $info = Get-WindowRectInfo -Hwnd $H
  foreach ($fy in @(278, 282, 275, 270, 285)) {
    [Win32Qa]::SetForegroundWindow($H) | Out-Null
    Click-Screen -X ($info.Left + 280) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 550
    Click-Screen -X ($info.Left + 400) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 1100
    $tmp = Join-Path $roundDir "_dlg.png"
    Cap $H $tmp
    if ((Get-Item $tmp).Length -ge 140000) { return $true }
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
  }
  return $false
}

function Is-ChooseLogo([string]$Path) {
  # Real picker screenshots are large and have many bright tiles in center.
  if ((Get-Item $Path).Length -lt 140000) { return $false }
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0
    for ($y = [int]($b.Height * 0.15); $y -lt [int]($b.Height * 0.80); $y += 2) {
      for ($x = [int]($b.Width * 0.30); $x -lt [int]($b.Width * 0.90); $x += 2) {
        $c = $b.GetPixel($x, $y)
        if (([int]$c.R + [int]$c.G + [int]$c.B) -gt 480) { $bright++ }
      }
    }
    return ($bright -gt 350)
  } finally { $b.Dispose() }
}

$hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
[Win32Qa]::MoveWindow($hwnd, 40, 40, 1400, 980, $true) | Out-Null
Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 400

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @(); $start = Get-Date
Write-Host ("SESSION {0}" -f $start)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-95)) { Write-Host "TIME BUDGET"; break }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company=$company; ok=$false; notes=""; started=(Get-Date).ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
    1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Milliseconds 120 }
    Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 450
    if (-not (Open-Find $hwnd)) { throw "dialog_open_failed" }
    $s1 = Join-Path $roundDir ($safe + "_01_dialog.png"); Cap $hwnd $s1
    Type-Text $company; Start-Sleep -Milliseconds 350
    $s2 = Join-Path $roundDir ($safe + "_02_typed.png"); Cap $hwnd $s2
    Send-KeysSafe "{ENTER}"
    $entry.notes += "search=Enter; "
    Start-Sleep -Seconds 5
    $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = $false
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 6
      $w = Join-Path $roundDir ($safe + "_wait.png"); Cap $hwnd $w
      if (Is-ChooseLogo $w) { $ok = $true; break }
    }
    $s3 = Join-Path $roundDir ($safe + "_03_result.png"); Cap $hwnd $s3
    $entry.ok = $ok
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.bytes = (Get-Item $s3).Length
    $entry.notes += ("chooseLogo={0}; " -f $ok)
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 400
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 400
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Send-KeysSafe "{ESC}{ESC}{ESC}"
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ started=$start.ToString('o'); ended=(Get-Date).ToString('o'); companies=$results } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "gui_r3.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$pass = @($results | Where-Object ok).Count
Write-Host ("DONE PASS {0}/{1}" -f $pass, $results.Count)
