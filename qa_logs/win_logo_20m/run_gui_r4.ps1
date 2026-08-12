# Real Windows-app Find-logo QA (r4): stricter picker detection; Dialog UX rebuild.
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 85,
  [int]$MaxMinutes = 17
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
$roundDir = Join-Path $outDir "gui_r4"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Cap([IntPtr]$H, [string]$P) {
  1..2 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 60 }
  Capture-WindowShot -Hwnd $H -Path $P | Out-Null
}

function Get-ShotStats([string]$Path) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0; $mid = 0; $orange = 0
    # Sample center band where a centered Dialog / Choose-a-logo lives.
    $x0 = [int]($b.Width * 0.28); $x1 = [int]($b.Width * 0.72)
    $y0 = [int]($b.Height * 0.18); $y1 = [int]($b.Height * 0.82)
    for ($y = $y0; $y -lt $y1; $y += 3) {
      for ($x = $x0; $x -lt $x1; $x += 3) {
        $c = $b.GetPixel($x, $y)
        $s = [int]$c.R + [int]$c.G + [int]$c.B
        if ($s -gt 500) { $bright++ }
        elseif ($s -gt 180 -and $s -lt 480) { $mid++ }
        # Accent Search button / logo oranges
        if ($c.R -gt 160 -and $c.G -lt 110 -and $c.B -lt 90) { $orange++ }
      }
    }
    return [pscustomobject]@{
      bright = $bright; mid = $mid; orange = $orange
      bytes = (Get-Item $Path).Length; w = $b.Width; h = $b.Height
    }
  } finally { $b.Dispose() }
}

function Is-FindDialog([string]$Path) {
  # Centered Find-logo Dialog: mid-tone card, some orange Search, not idle.
  $s = Get-ShotStats $Path
  return ($s.mid -gt 1800 -and $s.orange -gt 8 -and $s.bytes -ge 170000 -and $s.bytes -lt 260000)
}

function Is-ChooseLogo([string]$Path) {
  # Real picker: many mid tiles (thumbnails), larger PNG, not idle desktop glare.
  # Idle false+ had high bright + low mid; real pickers reverse that and are bigger.
  $s = Get-ShotStats $Path
  if ($s.bytes -lt 230000) { return $false }
  if ($s.mid -lt 3500) { return $false }
  if ($s.mid -le $s.bright) { return $false }
  return $true
}

function Open-Find([IntPtr]$H) {
  Send-KeysSafe "{ESC}{ESC}{ESC}"
  Start-Sleep -Milliseconds 500
  $info = Get-WindowRectInfo -Hwnd $H
  # Tools menu ~ fx 0.42 on 1400-wide chrome, then Find logo item.
  foreach ($toolsX in @(520, 480, 560, 440)) {
    foreach ($fy in @(278, 270, 285, 295, 260)) {
      [Win32Qa]::SetForegroundWindow($H) | Out-Null
      Click-Screen -X ($info.Left + $toolsX) -Y ($info.Top + 48)
      Start-Sleep -Milliseconds 450
      Click-Screen -X ($info.Left + ($toolsX + 80)) -Y ($info.Top + $fy)
      Start-Sleep -Milliseconds 900
      $tmp = Join-Path $roundDir "_dlg.png"
      Cap $H $tmp
      if (Is-FindDialog $tmp) { return $true }
      # Also accept if Search orange is present even if classifier borderline
      $st = Get-ShotStats $tmp
      if ($st.orange -gt 20 -and $st.mid -gt 1500) { return $true }
      Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
    }
  }
  return $false
}

$hwnd = Ensure-AppWindow -W 1500 -H 1000 -X 20 -Y 20
[Win32Qa]::MoveWindow($hwnd, 20, 20, 1500, 1000, $true) | Out-Null
Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 400

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @(); $start = Get-Date
Write-Host ("SESSION {0}" -f $start)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-100)) { Write-Host "TIME BUDGET"; break }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company=$company; ok=$false; notes=""; started=(Get-Date).ToString('o'); real_choose=$false }
  try {
    $hwnd = Ensure-AppWindow -W 1500 -H 1000 -X 20 -Y 20
    1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Milliseconds 100 }
    Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 500
    if (-not (Open-Find $hwnd)) { throw "dialog_open_failed" }
    $s1 = Join-Path $roundDir ($safe + "_01_dialog.png"); Cap $hwnd $s1
    $dstat = Get-ShotStats $s1
    $entry.notes += ("dlg mid={0} orange={1}; " -f $dstat.mid, $dstat.orange)
    Type-Text $company; Start-Sleep -Milliseconds 400
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
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 500
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 500
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Send-KeysSafe "{ESC}{ESC}{ESC}"
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ started=$start.ToString('o'); ended=(Get-Date).ToString('o'); companies=$results } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "gui_r4.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$pass = @($results | Where-Object ok).Count
Write-Host ("DONE PASS {0}/{1}" -f $pass, $results.Count)
