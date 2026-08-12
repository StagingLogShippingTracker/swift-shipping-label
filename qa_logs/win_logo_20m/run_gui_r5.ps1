# Real Windows-app Find-logo QA (r5): Tools@270 + Down*6 + Enter; strict picker check.
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 80,
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
$roundDir = Join-Path $outDir "gui_r5"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Cap([IntPtr]$H, [string]$P) {
  1..2 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 50 }
  Capture-WindowShot -Hwnd $H -Path $P | Out-Null
}

function Get-ShotStats([string]$Path) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $bright = 0; $mid = 0; $orange = 0
    $x0 = [int]($b.Width * 0.25); $x1 = [int]($b.Width * 0.75)
    $y0 = [int]($b.Height * 0.15); $y1 = [int]($b.Height * 0.85)
    for ($y = $y0; $y -lt $y1; $y += 3) {
      for ($x = $x0; $x -lt $x1; $x += 3) {
        $c = $b.GetPixel($x, $y)
        $s = [int]$c.R + [int]$c.G + [int]$c.B
        if ($s -gt 500) { $bright++ }
        elseif ($s -gt 180 -and $s -lt 480) { $mid++ }
        if ($c.R -gt 160 -and $c.G -lt 110 -and $c.B -lt 90) { $orange++ }
      }
    }
    return [pscustomobject]@{
      bright=$bright; mid=$mid; orange=$orange
      bytes=(Get-Item $Path).Length; w=$b.Width; h=$b.Height
    }
  } finally { $b.Dispose() }
}

function Is-ChooseLogo([string]$Path) {
  $s = Get-ShotStats $Path
  # Real picker: larger PNG, mid-tone tiles dominate (not idle desktop glare).
  if ($s.bytes -lt 230000) { return $false }
  if ($s.mid -lt 3200) { return $false }
  if ($s.mid -le ($s.bright + 200)) { return $false }
  return $true
}

function Is-FindDialog([string]$Path) {
  $s = Get-ShotStats $Path
  # Centered card after fix: more mid in center; clipped old dialog was tiny strip.
  # Accept either centered (orange Search) or clipped-but-open (title area).
  if ($s.bytes -lt 170000) { return $false }
  if ($s.bytes -gt 280000) { return $false } # likely Choose-a-logo leftover / file dialog
  return ($s.mid -gt 400 -or $s.orange -gt 5)
}

function Close-NativeDialogs {
  1..6 | ForEach-Object { Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 120 }
}

function Open-Find([IntPtr]$H) {
  Close-NativeDialogs
  Start-Sleep -Milliseconds 350
  $info = Get-WindowRectInfo -Hwnd $H
  [Win32Qa]::SetForegroundWindow($H) | Out-Null
  # Tools menu label ~ x=270 from window left (verified).
  Click-Screen -X ($info.Left + 270) -Y ($info.Top + 50)
  Start-Sleep -Milliseconds 500
  # 6x Down lands on "Find logo on web…" (verified; 7 = Upload).
  1..6 | ForEach-Object { Send-KeysSafe "{DOWN}"; Start-Sleep -Milliseconds 70 }
  Start-Sleep -Milliseconds 150
  Send-KeysSafe "{ENTER}"
  Start-Sleep -Milliseconds 900
  $tmp = Join-Path $roundDir "_dlg.png"
  Cap $H $tmp
  if (Is-FindDialog $tmp) { return $true }
  # Retry once
  Close-NativeDialogs
  Start-Sleep -Milliseconds 300
  Click-Screen -X ($info.Left + 270) -Y ($info.Top + 50)
  Start-Sleep -Milliseconds 500
  1..6 | ForEach-Object { Send-KeysSafe "{DOWN}"; Start-Sleep -Milliseconds 70 }
  Send-KeysSafe "{ENTER}"
  Start-Sleep -Milliseconds 900
  Cap $H $tmp
  return (Is-FindDialog $tmp)
}

$hwnd = Ensure-AppWindow -W 1500 -H 1000 -X 20 -Y 20
[Win32Qa]::MoveWindow($hwnd, 20, 20, 1500, 1000, $true) | Out-Null
Close-NativeDialogs

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
    1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Milliseconds 80 }
    Close-NativeDialogs
    Start-Sleep -Milliseconds 350
    if (-not (Open-Find $hwnd)) { throw "dialog_open_failed" }
    $s1 = Join-Path $roundDir ($safe + "_01_dialog.png"); Cap $hwnd $s1
    $dstat = Get-ShotStats $s1
    $entry.notes += ("dlg bytes={0} mid={1} orange={2}; " -f $dstat.bytes, $dstat.mid, $dstat.orange)
    Type-Text $company
    Start-Sleep -Milliseconds 400
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
    Close-NativeDialogs
    Start-Sleep -Milliseconds 400
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Close-NativeDialogs
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ started=$start.ToString('o'); ended=(Get-Date).ToString('o'); companies=$results } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "gui_r5.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$pass = @($results | Where-Object ok).Count
Write-Host ("DONE PASS {0}/{1}" -f $pass, $results.Count)
