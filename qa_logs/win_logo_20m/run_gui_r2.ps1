# Drive rebuilt Windows app Find-logo: Tools menu + type + Enter (onSubmitted Search)
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$WaitSec = 70,
  [int]$MaxMinutes = 18
)
$ErrorActionPreference = "Stop"
. (Join-Path $Root "qa_logs\win_logo_hour\_win32.ps1")
Add-Type -AssemblyName System.Drawing

$companies = @(
  "Sureus Murphy","BFL","Whitecap","Arjae Design Solutions",
  "Paramount Resources","Suncor","Warren Valve",
  "Shell","ATCO","EPCOR"
)

$outDir = Join-Path $Root "qa_logs\win_logo_20m"
$roundDir = Join-Path $outDir "gui_r2"
New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

function Capture([IntPtr]$Hwnd, [string]$Path) {
  [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
  Start-Sleep -Milliseconds 100
  Capture-WindowShot -Hwnd $Hwnd -Path $Path | Out-Null
}

function Open-Find([IntPtr]$Hwnd) {
  Click-Rel -Hwnd $Hwnd -Fx 0.50 -Fy 0.11 | Out-Null
  Start-Sleep -Milliseconds 200
  $info = Get-WindowRectInfo -Hwnd $Hwnd
  foreach ($fy in @(278, 282, 275, 270, 285)) {
    [Win32Qa]::SetForegroundWindow($Hwnd) | Out-Null
    Click-Screen -X ($info.Left + 280) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 550
    Click-Screen -X ($info.Left + 400) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 1000
    $tmp = Join-Path $roundDir "_dlg.png"
    Capture $Hwnd $tmp
    $bytes = (Get-Item $tmp).Length
    if ($bytes -ge 150000) { return @{ ok = $true; fy = $fy; bytes = $bytes } }
    # Also accept if orange company field present
    $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $tmp))
    $n = 0
    try {
      for ($y = [int]($b.Height * 0.45); $y -lt $b.Height; $y += 3) {
        for ($x = [int]($b.Width * 0.40); $x -lt $b.Width; $x += 3) {
          $c = $b.GetPixel($x, $y)
          if ($c.R -gt 150 -and ($c.R - $c.G) -gt 45) { $n++ }
        }
      }
    } finally { $b.Dispose() }
    if ($n -gt 80) { return @{ ok = $true; fy = $fy; bytes = $bytes; orange = $n } }
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 250
  }
  return @{ ok = $false }
}

function Is-Picker([string]$Path) {
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    # Center modal with many bright tiles
    $bright = 0
    for ($y = [int]($b.Height * 0.20); $y -lt [int]($b.Height * 0.75); $y += 2) {
      for ($x = [int]($b.Width * 0.25); $x -lt [int]($b.Width * 0.80); $x += 2) {
        $c = $b.GetPixel($x, $y)
        $sum = [int]$c.R + [int]$c.G + [int]$c.B
        if ($sum -gt 500) { $bright++ }
      }
    }
    # Require strong tile density (Choose a logo grid)
    return ($bright -gt 400)
  } finally { $b.Dispose() }
}

$hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
[Win32Qa]::ShowWindow($hwnd, 9) | Out-Null
[Win32Qa]::MoveWindow($hwnd, 40, 40, 1400, 980, $true) | Out-Null
[Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 400

$deadline = (Get-Date).AddMinutes($MaxMinutes)
$results = @(); $start = Get-Date
Write-Host ("SESSION {0}" -f $start)

foreach ($company in $companies) {
  if ((Get-Date) -gt $deadline.AddSeconds(-90)) { Write-Host "TIME BUDGET"; break }
  $safe = ($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')
  Write-Host ("=== {0} {1} ===" -f $company, (Get-Date -Format 'HH:mm:ss'))
  $entry = [ordered]@{ company = $company; ok = $false; notes = ""; started = (Get-Date).ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
    1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null; Start-Sleep -Milliseconds 150 }
    Send-KeysSafe "{ESC}{ESC}{ESC}"; Start-Sleep -Milliseconds 400
    $opened = Open-Find $hwnd
    if (-not $opened.ok) { throw "dialog_open_failed" }
    $shot1 = Join-Path $roundDir ($safe + "_01_dialog.png")
    Capture $hwnd $shot1
    Type-Text $company
    Start-Sleep -Milliseconds 350
    $shot2 = Join-Path $roundDir ($safe + "_02_typed.png")
    Capture $hwnd $shot2
    # Enter submits Search via onSubmitted
    Send-KeysSafe "{ENTER}"
    $entry.notes += "search=Enter; "
    Start-Sleep -Seconds 4
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $picker = $false
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      Start-Sleep -Seconds 6
      $wait = Join-Path $roundDir ($safe + "_wait.png")
      Capture $hwnd $wait
      if (Is-Picker $wait) { $picker = $true; break }
    }
    $shot3 = Join-Path $roundDir ($safe + "_03_result.png")
    Capture $hwnd $shot3
    $entry.ok = $picker
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.notes += ("picker={0}; " -f $picker)
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 350
    Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 350
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    Send-KeysSafe "{ESC}{ESC}{ESC}"
  }
  $entry.ended = (Get-Date).ToString('o')
  $results += [pscustomobject]$entry
  @{ started = $start.ToString('o'); ended = (Get-Date).ToString('o'); companies = $results } |
    ConvertTo-Json -Depth 6 | Set-Content (Join-Path $outDir "gui_r2.json")
  Write-Host ("  -> ok={0} {1}" -f $entry.ok, $entry.notes)
}

$okN = @($results | Where-Object ok).Count
Write-Host ("DONE PASS {0}/{1}" -f $okN, $results.Count)
