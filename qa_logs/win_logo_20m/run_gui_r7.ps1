# Real Windows-app Find-logo QA (r7): always Tools+Down*6+Enter; click field; strict picker.
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 70,
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
$roundDir = Join-Path $outDir "gui_r7"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Cap([IntPtr]$H, [string]$P) {
  1..2 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 40 }
  Capture-WindowShot -Hwnd $H -Path $P | Out-Null
}

function Get-ShotStats([string]$Path) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0; $mid = 0
    $x0 = [int]($b.Width * 0.25); $x1 = [int]($b.Width * 0.75)
    $y0 = [int]($b.Height * 0.15); $y1 = [int]($b.Height * 0.85)
    for ($y = $y0; $y -lt $y1; $y += 3) {
      for ($x = $x0; $x -lt $x1; $x += 3) {
        $c = $b.GetPixel($x, $y)
        $s = [int]$c.R + [int]$c.G + [int]$c.B
        if ($s -gt 500) { $bright++ }
        elseif ($s -gt 180 -and $s -lt 480) { $mid++ }
      }
    }
    return [pscustomobject]@{ bright=$bright; mid=$mid; bytes=(Get-Item $Path).Length }
  } finally { $b.Dispose() }
}

function Is-ChooseLogo([string]$Path) {
  $s = Get-ShotStats $Path
  if ($s.bytes -lt 230000) { return $false }
  if ($s.mid -lt 3000) { return $false }
  if ($s.mid -le ($s.bright + 200)) { return $false }
  return $true
}

function Close-All {
  1..8 | ForEach-Object { Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 100 }
}

function Open-Find([IntPtr]$H) {
  Close-All
  Start-Sleep -Milliseconds 400
  $info = Get-WindowRectInfo -Hwnd $H
  [Win32Qa]::SetForegroundWindow($H) | Out-Null
  Click-Screen -X ($info.Left + 270) -Y ($info.Top + 50)
  Start-Sleep -Milliseconds 550
  1..6 | ForEach-Object { Send-KeysSafe "{DOWN}"; Start-Sleep -Milliseconds 75 }
  Start-Sleep -Milliseconds 120
  Send-KeysSafe "{ENTER}"
  Start-Sleep -Milliseconds 1200
  # Do NOT click the window center — that hits the dismiss barrier and
  # steals focus to the form (Special Instructions). Rely on TextField autofocus.
  return $true
}

$hwnd = Ensure-AppWindow -W 1500 -H 1000 -X 20 -Y 20
[Win32Qa]::MoveWindow($hwnd, 20, 20, 1500, 1000, $true) | Out-Null
Close-All

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @(); $start = Get-Date
Write-Host ("SESSION {0}" -f $start)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-95)) { Write-Host "TIME BUDGET"; break }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company=$company; ok=$false; notes=""; started=(Get-Date).ToString('o'); real_choose=$false }
  try {
    $hwnd = Ensure-AppWindow -W 1500 -H 1000 -X 20 -Y 20
    1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Milliseconds 80 }
    Open-Find $hwnd | Out-Null
    $s1 = Join-Path $roundDir ($safe + "_01_dialog.png"); Cap $hwnd $s1
    $entry.notes += ("dlg_bytes={0}; " -f (Get-Item $s1).Length)
    Type-Text $company
    Start-Sleep -Milliseconds 450
    $s2 = Join-Path $roundDir ($safe + "_02_typed.png"); Cap $hwnd $s2
    Send-KeysSafe "{ENTER}"
    $entry.notes += "search=Enter; "
    Start-Sleep -Seconds 8
    $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = $false
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 7
      $w = Join-Path $roundDir ($safe + "_wait.png"); Cap $hwnd $w
      $st = Get-ShotStats $w
      Write-Host ("  wait t={0:n0}s bytes={1} mid={2} bright={3}" -f $sw.Elapsed.TotalSeconds, $st.bytes, $st.mid, $st.bright)
      if (Is-ChooseLogo $w) { $ok = $true; break }
    }
    $s3 = Join-Path $roundDir ($safe + "_03_result.png"); Cap $hwnd $s3
    $rst = Get-ShotStats $s3
    $entry.ok = $ok
    $entry.real_choose = $ok
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.bytes = $rst.bytes
    $entry.notes += ("chooseLogo={0} mid={1} bright={2}; " -f $ok, $rst.mid, $rst.bright)
    Close-All
    Start-Sleep -Milliseconds 500
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Close-All
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ started=$start.ToString('o'); ended=(Get-Date).ToString('o'); companies=$results } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "gui_r7.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$pass = @($results | Where-Object ok).Count
Write-Host ("DONE PASS {0}/{1}" -f $pass, $results.Count)

