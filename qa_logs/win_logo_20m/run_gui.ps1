# Drive REAL Windows app Find-logo UI for ~20 minutes.
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 60,
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
$roundDir = Join-Path $outDir "gui_r1"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null
(Get-Date).ToString("o") | Set-Content (Join-Path $outDir "SESSION_START.txt")

function Get-OrangeCount([string]$Path, [double]$Y0Frac = 0.45, [double]$X0Frac = 0.35) {
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

function Go-Receiving([IntPtr]$Hwnd) {
  Click-Rel -Hwnd $Hwnd -Fx 0.06 -Fy 0.40 | Out-Null
  Start-Sleep -Milliseconds 450
  Click-Rel -Hwnd $Hwnd -Fx 0.55 -Fy 0.12 | Out-Null
  Start-Sleep -Milliseconds 250
}

function Open-FindLogoDialog([IntPtr]$Hwnd) {
  $tmp = Join-Path $roundDir "_dlg.png"
  Go-Receiving $Hwnd
  [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null

  $info = Get-WindowRectInfo -Hwnd $Hwnd
  foreach ($fy in @(255, 270, 285, 300, 240, 315)) {
    [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
    Click-Screen -X ($info.Left + 310) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 450
    Click-Screen -X ($info.Left + 400) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 900
    Capture-WindowShot -Hwnd $Hwnd -Path $tmp | Out-Null
    $sz = Get-OrangeCount $tmp 0.40 0.30
    if ($sz -gt 80) {
      return @{ ok = $true; zone = $sz; method = ("menu_fy={0}" -f $fy) }
    }
    Send-KeysSafe "{ESC}"
    Start-Sleep -Milliseconds 200
  }

  Go-Receiving $Hwnd
  [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
  Send-KeysSafe "^+f"
  Start-Sleep -Milliseconds 1100
  Capture-WindowShot -Hwnd $Hwnd -Path $tmp | Out-Null
  $sz = Get-OrangeCount $tmp 0.40 0.30
  if ($sz -gt 80) { return @{ ok = $true; zone = $sz; method = "hotkey" } }
  return @{ ok = $false; zone = $sz; method = "none" }
}

function Activate-Search([IntPtr]$Hwnd, [string]$Shot) {
  # Prefer clicking orange Search button; fall back to 4x Tab + Enter.
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Shot))
  $bestX = 0; $bestY = 0; $bestN = 0
  try {
    $y0 = [int]($b.Height * 0.72); $x0 = [int]($b.Width * 0.55)
    for ($y = $y0; $y -lt $b.Height - 4; $y += 2) {
      for ($x = $x0; $x -lt $b.Width - 4; $x += 2) {
        $c = $b.GetPixel($x, $y)
        if ($c.R -gt 150 -and $c.G -lt 130 -and ($c.R - $c.G) -gt 50) {
          $n = 0
          for ($dy = -4; $dy -le 4; $dy += 2) {
            for ($dx = -10; $dx -le 10; $dx += 2) {
              $xx = [Math]::Min($b.Width-1, $x+$dx)
              $yy = [Math]::Min($b.Height-1, $y+$dy)
              $c2 = $b.GetPixel($xx, $yy)
              if ($c2.R -gt 150 -and ($c2.R - $c2.G) -gt 50) { $n++ }
            }
          }
          if ($n -gt $bestN) { $bestN = $n; $bestX = $x; $bestY = $y }
        }
      }
    }
  } finally { $b.Dispose() }

  if ($bestN -gt 20) {
    Click-Screen -X ($info.Left + $bestX) -Y ($info.Top + $bestY)
    return ("click={0},{1},n={2}" -f $bestX, $bestY, $bestN)
  }
  Send-KeysSafe "{TAB}{TAB}{TAB}{TAB}{ENTER}"
  return "tabs4"
}

function Classify([string]$Path) {
  $dlg = Get-OrangeCount $Path 0.55 0.35
  if ($dlg -gt 100) { return "dialog_open" }
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0
    for ($y = 140; $y -lt [Math]::Min(750, $b.Height); $y += 3) {
      for ($x = 400; $x -lt [Math]::Min(1250, $b.Width); $x += 3) {
        $c = $b.GetPixel($x, $y)
        if (($c.R -gt 180 -and $c.G -gt 140) -or ($c.R -gt 200 -and $c.G -lt 80) -or (($c.R+$c.G+$c.B) -gt 520)) {
          $bright++
        }
      }
    }
  } finally { $b.Dispose() }
  if ($bright -gt 100) { return "picker_likely" }
  return "idle_or_snackbar"
}

$hwnd = Ensure-AppWindow -W 1500 -H 1040
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "{ESC}{ESC}{ESC}"
Start-Sleep -Milliseconds 400
Go-Receiving $hwnd

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @()
$roundStart = Get-Date
Write-Host ("SESSION START {0} deadline={1}" -f $roundStart, $deadline)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-75)) {
    Write-Host ("TIME BUDGET - stop before {0}" -f $company)
    break
  }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company=$company; ok=$false; notes=""; screenshots=@(); started=(Get-Date).ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1500 -H 1040
    [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
    Send-KeysSafe "{ESC}{ESC}{ESC}"
    Start-Sleep -Milliseconds 400

    $opened = Open-FindLogoDialog $hwnd
    if (-not $opened.ok) { throw ("Could not open Find logo dialog (zone={0})" -f $opened.zone) }

    $shot1 = Join-Path $roundDir ($safe + '_01_dialog.png')
    Capture-WindowShot -Hwnd $hwnd -Path $shot1 | Out-Null
    $entry.screenshots += $shot1
    $entry.notes += ("open={0} zone={1}; " -f $opened.method, $opened.zone)

    Type-Text $company
    Start-Sleep -Milliseconds 400
    $shot2 = Join-Path $roundDir ($safe + '_02_typed.png')
    Capture-WindowShot -Hwnd $hwnd -Path $shot2 | Out-Null
    $entry.screenshots += $shot2

    $how = Activate-Search $hwnd $shot2
    $entry.notes += ("search={0}; " -f $how)
    Start-Sleep -Seconds 3

    $sw = [Diagnostics.Stopwatch]::StartNew(); $cls = "dialog_open"
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 5
      $latest = Join-Path $roundDir ($safe + '_wait.png')
      Capture-WindowShot -Hwnd $hwnd -Path $latest | Out-Null
      $cls = Classify $latest
      Write-Host ("  wait {0:0}s class={1}" -f $sw.Elapsed.TotalSeconds, $cls)
      if ($cls -eq "picker_likely") { break }
      if ($sw.Elapsed.TotalSeconds -gt 28 -and $cls -eq "idle_or_snackbar") { break }
    }
    $shot3 = Join-Path $roundDir ($safe + '_03_result.png')
    Capture-WindowShot -Hwnd $hwnd -Path $shot3 | Out-Null
    $entry.screenshots += $shot3
    $entry.classification = $cls
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.ok = ($cls -eq "picker_likely")
    $entry.notes += ("class={0}; " -f $cls)
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 300
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 300
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Send-KeysSafe "{ESC}{ESC}{ESC}"
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{
    started = $roundStart.ToString('o')
    ended = (Get-Date).ToString('o')
    deadline = $deadline.ToString('o')
    exe = "dist\Swift Document Generator\swift_shipping_label.exe"
    companies = $results
  } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $outDir "gui_r1.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$ok = @($results | Where-Object { $_.ok }).Count
Write-Host ("DONE gui_r1 PASS {0}/{1} elapsed={2}m" -f $ok, $results.Count, (((Get-Date)-$roundStart).TotalMinutes.ToString('0.0')))