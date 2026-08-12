# REAL Windows-app Find-logo QA only (ASCII).
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 65,
  [int]$MaxMinutes = 20
)
$ErrorActionPreference = "Stop"
. (Join-Path $Root "qa_logs\win_logo_hour\_win32.ps1")
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$companies = @(
  "Sureus Murphy",
  "BFL",
  "Whitecap",
  "Arjae Design Solutions",
  "Paramount Resources",
  "Suncor",
  "Warren Valve",
  "Shell",
  "ATCO",
  "EPCOR",
  "Arc Resources LTD",
  "DNOW"
)

$outDir = Join-Path $Root "qa_logs\win_logo_20m"
$roundDir = Join-Path $outDir "gui_live"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null
(Get-Date).ToString("o") | Set-Content (Join-Path $outDir "SESSION_START.txt")

function Get-OrangeCount([string]$Path, [double]$Y0Frac, [double]$X0Frac) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $n = 0
    $y0 = [int]($b.Height * $Y0Frac)
    $x0 = [int]($b.Width * $X0Frac)
    for ($y = $y0; $y -lt $b.Height; $y += 2) {
      for ($x = $x0; $x -lt $b.Width; $x += 2) {
        $c = $b.GetPixel($x, $y)
        if ($c.R -gt 150 -and $c.G -lt 140 -and ($c.R - $c.G) -gt 40) { $n++ }
      }
    }
    return $n
  } finally { $b.Dispose() }
}

function Find-SearchButton([IntPtr]$Hwnd, [string]$Shot) {
  # Largest orange blob in lower-right = Search button
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Shot))
  $bestX = 0; $bestY = 0; $bestN = 0
  try {
    $y0 = [int]($b.Height * 0.55); $x0 = [int]($b.Width * 0.45)
    for ($y = $y0; $y -lt $b.Height - 6; $y += 2) {
      for ($x = $x0; $x -lt $b.Width - 6; $x += 2) {
        $c = $b.GetPixel($x, $y)
        if ($c.R -gt 150 -and ($c.R - $c.G) -gt 45 -and $c.G -lt 140) {
          $n = 0
          for ($dy = -6; $dy -le 6; $dy += 2) {
            for ($dx = -14; $dx -le 14; $dx += 2) {
              $xx = [Math]::Min($b.Width - 1, $x + $dx)
              $yy = [Math]::Min($b.Height - 1, $y + $dy)
              $c2 = $b.GetPixel($xx, $yy)
              if ($c2.R -gt 150 -and ($c2.R - $c2.G) -gt 45) { $n++ }
            }
          }
          if ($n -gt $bestN) { $bestN = $n; $bestX = $x; $bestY = $y }
        }
      }
    }
  } finally { $b.Dispose() }
  if ($bestN -lt 20) { return $null }
  Click-Screen -X ($info.Left + $bestX) -Y ($info.Top + $bestY)
  return ("{0},{1},n={2}" -f $bestX, $bestY, $bestN)
}

function Open-FindLogo([IntPtr]$Hwnd) {
  $tmp = Join-Path $roundDir "_dlg.png"
  Click-Rel -Hwnd $Hwnd -Fx 0.50 -Fy 0.11 | Out-Null
  Start-Sleep -Milliseconds 200
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  foreach ($fy in @(278, 282, 275, 285)) {
    [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
    Click-Rel -Hwnd $Hwnd -Fx 0.50 -Fy 0.11 | Out-Null
    Start-Sleep -Milliseconds 120
    Click-Screen -X ($info.Left + 280) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 550
    Click-Screen -X ($info.Left + 400) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 1000
    Capture-WindowShot -Hwnd $Hwnd -Path $tmp | Out-Null
    $sz = Get-OrangeCount $tmp 0.55 0.45
    $bytes = (Get-Item $tmp).Length
    if ($sz -gt 60 -and $bytes -ge 109000) {
      return @{ ok = $true; zone = $sz; method = ("menu_fy={0}" -f $fy) }
    }
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
  }
  return @{ ok = $false; zone = 0; method = "none" }
}

function Classify-Result([string]$Path) {
  # Find-logo entry dialog still open?
  $dlgOrange = Get-OrangeCount $Path 0.60 0.50
  if ($dlgOrange -gt 200) { return "dialog_open" }

  # Choose-a-logo picker: many bright tiles in center modal
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0
    $yMin = [int]($b.Height * 0.18); $yMax = [int]($b.Height * 0.78)
    $xMin = [int]($b.Width * 0.28); $xMax = [int]($b.Width * 0.85)
    for ($y = $yMin; $y -lt $yMax; $y += 3) {
      for ($x = $xMin; $x -lt $xMax; $x += 3) {
        $c = $b.GetPixel($x, $y)
        $sum = [int]$c.R + [int]$c.G + [int]$c.B
        if ($sum -gt 480 -or ($c.R -gt 200 -and $c.G -lt 90) -or ($c.R -gt 170 -and $c.G -gt 150)) {
          $bright++
        }
      }
    }
  } finally { $b.Dispose() }

  # Require strong tile signal; idle forms alone should not match
  if ($bright -gt 280) { return "picker_likely" }
  if ($bright -gt 120) { return "maybe_picker" }
  return "idle_or_snackbar"
}

$hwnd = Ensure-AppWindow -W 1500 -H 1100
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "{ESC}{ESC}{ESC}"
Start-Sleep -Milliseconds 400
# Prefer Receiving via Document menu hotkey Ctrl+2 after blur
Click-Rel -Hwnd $hwnd -Fx 0.50 -Fy 0.11 | Out-Null
Start-Sleep -Milliseconds 200
Send-KeysSafe "^2"
Start-Sleep -Milliseconds 600

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @()
$roundStart = Get-Date
Write-Host ("SESSION START {0} deadline={1}" -f $roundStart, $deadline)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-80)) {
    Write-Host ("TIME BUDGET - stop before {0}" -f $company)
    break
  }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company = $company; ok = $false; notes = ""; screenshots = @(); started = (Get-Date).ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1500 -H 1100
    [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
    Send-KeysSafe "{ESC}{ESC}{ESC}"
    Start-Sleep -Milliseconds 450
    Click-Rel -Hwnd $hwnd -Fx 0.50 -Fy 0.11 | Out-Null
    Start-Sleep -Milliseconds 200
    Send-KeysSafe "^2"
    Start-Sleep -Milliseconds 500

    $opened = Open-FindLogo $hwnd
    if (-not $opened.ok) { throw ("Could not open Find logo dialog zone={0}" -f $opened.zone) }
    $shot1 = Join-Path $roundDir ($safe + "_01_dialog.png")
    Capture-WindowShot -Hwnd $hwnd -Path $shot1 | Out-Null
    $entry.screenshots += $shot1
    $entry.notes += ("open={0} zone={1}; " -f $opened.method, $opened.zone)

    Type-Text $company
    Start-Sleep -Milliseconds 400
    $shot2 = Join-Path $roundDir ($safe + "_02_typed.png")
    Capture-WindowShot -Hwnd $hwnd -Path $shot2 | Out-Null
    $entry.screenshots += $shot2

    $sc = Find-SearchButton $hwnd $shot2
    if ($null -eq $sc) {
      Send-KeysSafe "{TAB}{TAB}{TAB}{TAB}{ENTER}"
      $entry.notes += "search=4tab+enter; "
    } else {
      $entry.notes += ("search=click({0}); " -f $sc)
    }
    Start-Sleep -Seconds 3

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cls = "dialog_open"
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 5
      $latest = Join-Path $roundDir ($safe + "_wait.png")
      Capture-WindowShot -Hwnd $hwnd -Path $latest | Out-Null
      $cls = Classify-Result $latest
      if ($cls -eq "picker_likely") { break }
      if ($sw.Elapsed.TotalSeconds -gt 35 -and $cls -eq "idle_or_snackbar") { break }
    }
    $shot3 = Join-Path $roundDir ($safe + "_03_result.png")
    Capture-WindowShot -Hwnd $hwnd -Path $shot3 | Out-Null
    $entry.screenshots += $shot3
    $entry.classification = $cls
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.ok = ($cls -eq "picker_likely" -or $cls -eq "maybe_picker")
    $entry.notes += ("class={0}; " -f $cls)
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 300
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 300
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Send-KeysSafe "{ESC}{ESC}{ESC}"
  }
  $entry.ended = (Get-Date).ToString("o")
  $results += [pscustomobject]$entry
  @{
    started = $roundStart.ToString("o")
    ended = (Get-Date).ToString("o")
    deadline = $deadline.ToString("o")
    companies = $results
  } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $outDir "gui_live.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$okN = @($results | Where-Object { $_.ok }).Count
Write-Host ("DONE gui_live PASS {0}/{1} elapsed={2}m" -f $okN, $results.Count, (((Get-Date) - $roundStart).TotalMinutes.ToString("0.0")))
