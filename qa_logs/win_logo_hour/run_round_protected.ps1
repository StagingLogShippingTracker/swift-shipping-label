# Protected QA runner (do not overwrite) — Tools menu + search-zone dialog detect
param(
  [int]$Round = 3,
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 42
)
$ErrorActionPreference = "Stop"
. "$Root\qa_logs\win_logo_hour\_win32.ps1"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$companies = @(
  "Mastec Purnell","Shell","Flint Energy","Strike Group","5Blue Process Equipment",
  "ATCO","Arc Resources LTD","CDE Engineering LTD","EPCOR","DNOW","Comco","Apex Valves"
)
$outDir = Join-Path $Root "qa_logs\win_logo_hour"
$roundDir = Join-Path $outDir ("round{0}" -f $Round)
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Get-SearchZoneOrange([string]$Path) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $n = 0
    $y0 = [int]($b.Height * 0.82); $x0 = [int]($b.Width * 0.62)
    for ($y = $y0; $y -lt $b.Height; $y += 2) {
      for ($x = $x0; $x -lt $b.Width; $x += 2) {
        $c = $b.GetPixel($x, $y)
        if ($c.R -gt 150 -and $c.G -lt 130 -and $c.B -lt 110 -and ($c.R - $c.G) -gt 50) { $n++ }
      }
    }
    return $n
  } finally { $b.Dispose() }
}

function Open-Dialog([IntPtr]$Hwnd) {
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  foreach ($fy in @(280, 270, 290, 300, 260)) {
    [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
    Click-Rel -Hwnd $Hwnd -Fx 0.06 -Fy 0.28 | Out-Null
    Start-Sleep -Milliseconds 250
    Click-Screen -X ($info.Left + 280) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 450
    Click-Screen -X ($info.Left + 370) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 750
    $tmp = Join-Path $roundDir "_dlg.png"
    Capture-WindowShot -Hwnd $Hwnd -Path $tmp | Out-Null
    $sz = Get-SearchZoneOrange $tmp
    if ($sz -gt 200) { return @{ ok = $true; zone = $sz; fy = $fy } }
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
  }
  return @{ ok = $false; zone = 0; fy = 0 }
}

function Click-Search([IntPtr]$Hwnd, [string]$Shot) {
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Shot))
  $bestX = 1140; $bestY = 835; $bestN = 0
  try {
    $y0 = [int]($b.Height * 0.82); $x0 = [int]($b.Width * 0.62)
    for ($y = $y0; $y -lt $b.Height - 4; $y += 2) {
      for ($x = $x0; $x -lt $b.Width - 4; $x += 2) {
        $c = $b.GetPixel($x, $y)
        if ($c.R -gt 150 -and $c.G -lt 130 -and ($c.R - $c.G) -gt 50) {
          $n = 0
          for ($dy = -4; $dy -le 4; $dy += 2) {
            for ($dx = -10; $dx -le 10; $dx += 2) {
              $c2 = $b.GetPixel([Math]::Min($b.Width-1,$x+$dx), [Math]::Min($b.Height-1,$y+$dy))
              if ($c2.R -gt 150 -and ($c2.R - $c2.G) -gt 50) { $n++ }
            }
          }
          if ($n -gt $bestN) { $bestN = $n; $bestX = $x; $bestY = $y }
        }
      }
    }
  } finally { $b.Dispose() }
  Click-Screen -X ($info.Left + $bestX) -Y ($info.Top + $bestY)
  return "$bestX,$bestY,n=$bestN"
}

function Classify([string]$Path) {
  if ((Get-SearchZoneOrange $Path) -gt 150) { return "dialog_open" }
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    # Picker: title area + image tiles — look for non-dark mid-panel clusters
    $bright = 0
    for ($y = 180; $y -lt 650; $y += 3) {
      for ($x = 500; $x -lt 1100; $x += 3) {
        $c = $b.GetPixel($x, $y)
        # Logo tiles often have saturated brand colors, not just white
        if (($c.R -gt 180 -and $c.G -gt 140) -or ($c.R -gt 200 -and $c.G -lt 80) -or (($c.R+$c.G+$c.B) -gt 520)) {
          $bright++
        }
      }
    }
  } finally { $b.Dispose() }
  if ($bright -gt 150) { return "picker_likely" }
  return "idle_or_snackbar"
}

$hwnd = Ensure-AppWindow -W 1440 -H 900
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "{ESC}{ESC}"
Click-Rel -Hwnd $hwnd -Fx 0.06 -Fy 0.28 | Out-Null
Start-Sleep -Milliseconds 400
foreach ($fy in @(0.40, 0.48, 0.56)) {
  Click-Rel -Hwnd $hwnd -Fx 0.38 -Fy $fy | Out-Null
  Send-KeysSafe "^a{BACKSPACE}"; Start-Sleep -Milliseconds 60
}

$results = @(); $roundStart = Get-Date
foreach ($company in $companies) {
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host "=== R$Round $company ==="
  $entry = [ordered]@{ company=$company; ok=$false; notes=""; screenshots=@(); started=(Get-Date).ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1440 -H 900
    [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
    Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 400
    $opened = Open-Dialog $hwnd
    if (-not $opened.ok) { throw "Could not open dialog" }
    $shot1 = Join-Path $roundDir "${safe}_01_dialog.png"
    Capture-WindowShot -Hwnd $hwnd -Path $shot1 | Out-Null
    $entry.screenshots += $shot1
    $entry.notes += "zone=$($opened.zone) fy=$($opened.fy); "

    Type-Text $company
    Start-Sleep -Milliseconds 300
    $shot2 = Join-Path $roundDir "${safe}_02_typed.png"
    Capture-WindowShot -Hwnd $hwnd -Path $shot2 | Out-Null
    $entry.screenshots += $shot2
    if ((Get-SearchZoneOrange $shot2) -lt 100) { throw "Dialog lost after type" }

    $sc = Click-Search $hwnd $shot2
    $entry.notes += "search=$sc; "
    Start-Sleep -Seconds 2

    $sw = [Diagnostics.Stopwatch]::StartNew(); $cls = ""
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 5
      $latest = Join-Path $roundDir "${safe}_wait.png"
      Capture-WindowShot -Hwnd $hwnd -Path $latest | Out-Null
      $cls = Classify $latest
      if ($cls -eq "picker_likely") { break }
      if ($sw.Elapsed.TotalSeconds -gt 20 -and $cls -eq "idle_or_snackbar") { break }
    }
    $shot3 = Join-Path $roundDir "${safe}_03_result.png"
    Capture-WindowShot -Hwnd $hwnd -Path $shot3 | Out-Null
    $entry.screenshots += $shot3
    $entry.classification = $cls
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.ok = ($cls -eq "picker_likely")
    $entry.notes += "class=$cls; "
    # Dismiss without import
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ round=$Round; started=$roundStart.ToString('o'); ended=(Get-Date).ToString('o'); companies=$results } |
    ConvertTo-Json -Depth 8 | Set-Content (Join-Path $outDir ("round{0}.json" -f $Round))
}
Write-Host "DONE round $Round"
