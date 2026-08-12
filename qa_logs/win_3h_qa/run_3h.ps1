# 3-hour in-app QA: 2h Find logo on the web, then 1h BOL Generate PDF
# Uses real Windows app. Find-logo dialog in current dist can clip bottom-right;
# rely on autofocus + Enter (do NOT click the barrier — that dismisses the dialog).
param(
  [string]$Root = "C:\Users\Brice\OneDrive\Documents\swift_document_generator",
  [int]$LogoMinutes = 120,
  [int]$BolMinutes = 60,
  [int]$LogoWaitSec = 85
)
$ErrorActionPreference = "Continue"
. (Join-Path $Root "qa_logs\win_logo_hour\_win32.ps1")
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$outDir = Join-Path $Root "qa_logs\win_3h_qa"
$shotDir = Join-Path $outDir "shots"
$filledDir = Join-Path $Root "filled"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null

$logPath = Join-Path $outDir "run_log.jsonl"
$summaryPath = Join-Path $outDir "summary.json"
$heartbeatPath = Join-Path $outDir "heartbeat.txt"
$statusPath = Join-Path $outDir "STATUS.md"
if (Test-Path $logPath) { Remove-Item $logPath -Force }

$companies = @(
  "Shell","ATCO","EPCOR","Arc Resources LTD","DNOW","Whitecap",
  "Suncor","Paramount Resources","Warren Valve","BFL","Sureus Murphy",
  "Arjae Design Solutions","Mastec Purnell","Comco","Apex","Canadian Plains Energy",
  "Wolf Midstream","Pacific Canbriam","Fastenal","Cenovus","Enbridge",
  "TC Energy","Pembina","Keyera","Ovintiv","Tourmaline","MEG Energy",
  "Imperial Oil","CNRL","Precision Drilling","Secure Energy",
  "Parkland","Nutrien","Finning","Brandt Tractor","Wajax","Toromont",
  "Caterpillar","Schlumberger","Halliburton","Baker Hughes","Weatherford",
  "TechnipFMC","Worley","Stantec","Fluor","Kiewit","Ledcor","PCL","Bird Construction"
)

function Write-Log([hashtable]$Entry) {
  ($Entry | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $logPath -Encoding UTF8
}
function Write-Heartbeat([string]$Phase, [string]$Detail) {
  $line = "{0:o} | {1} | {2}" -f (Get-Date), $Phase, $Detail
  Set-Content -Path $heartbeatPath -Value $line -Encoding UTF8
  Write-Host $line
}
function Write-Status([string]$Text) { Set-Content -Path $statusPath -Value $Text -Encoding UTF8 }

function Cap([IntPtr]$H, [string]$P) {
  1..2 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 50 }
  Capture-WindowShot -Hwnd $H -Path $P | Out-Null
}
function Focus-App([IntPtr]$H) {
  [Win32Qa]::ShowWindow($H, [Win32Qa]::SW_RESTORE) | Out-Null
  1..3 | ForEach-Object { [Win32Qa]::SetForegroundWindow($H) | Out-Null; Start-Sleep -Milliseconds 80 }
}
function Close-PdfViewers {
  foreach ($n in @("Acrobat","AcroRd32","msedge","chrome","SumatraPDF","FoxitPDFReader","PDFXCview")) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        if ($_.MainWindowTitle -and ($_.MainWindowTitle -match '\.pdf|BOL-|SL-|RL-|Swift')) {
          $_.CloseMainWindow() | Out-Null
        }
      } catch {}
    }
  }
}
function Dismiss-Dialogs([IntPtr]$H) {
  Focus-App $H
  Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 180
  Send-KeysSafe "{ESC}"; Start-Sleep -Milliseconds 180
}

function Is-ChooseLogo([string]$Path) {
  # Real picker screenshots are ~250KB+ (form alone ~190–205KB). Whitecap picker hit
  # 264KB with ~755 near-white tile pixels — size is the reliable gate.
  if (-not (Test-Path $Path)) { return $false }
  $len = (Get-Item $Path).Length
  if ($len -lt 240000) { return $false }
  $b = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
  try {
    $nearWhite = 0
    for ($y = [int]($b.Height * 0.14); $y -lt [int]($b.Height * 0.86); $y += 3) {
      for ($x = [int]($b.Width * 0.28); $x -lt [int]($b.Width * 0.94); $x += 3) {
        $c = $b.GetPixel($x, $y)
        if (([int]$c.R + [int]$c.G + [int]$c.B) -gt 620) { $nearWhite++ }
      }
    }
    return ($nearWhite -gt 400)
  } finally { $b.Dispose() }
}

function Open-FindLogo([IntPtr]$H) {
  # Tools → Find logo on web… (item ~fy 280). Do not click the dim barrier afterward.
  Focus-App $H
  Dismiss-Dialogs $H
  Start-Sleep -Milliseconds 250
  $info = Get-WindowRectInfo -Hwnd $H
  foreach ($fy in @(280, 282, 278, 275, 285, 288, 270, 290)) {
    Focus-App $H
    Click-Screen -X ($info.Left + 280) -Y ($info.Top + 48)
    Start-Sleep -Milliseconds 650
    Click-Screen -X ($info.Left + 330) -Y ($info.Top + $fy)
    Start-Sleep -Milliseconds 1100
    $tmp = Join-Path $shotDir "_find_probe.png"
    Cap $H $tmp
    if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 1000) { continue }
    # Heuristic: Find-logo dialog (even clipped) usually bumps screenshot size vs plain form
    # and/or shows a bottom-right card. Accept and rely on autofocus.
    if ((Get-Item $tmp).Length -ge 198000) { return $true }
  }
  return $false
}

function Count-NewPdfs([datetime]$Since) {
  if (-not (Test-Path $filledDir)) { return @() }
  return @(Get-ChildItem $filledDir -Filter "*.pdf" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $Since } | Sort-Object LastWriteTime)
}

$sessionStart = Get-Date
Write-Heartbeat "BOOT" "starting 3h QA (autofocus Find-logo path)"
Write-Status @"
# Windows 3h in-app QA

- Started: $($sessionStart.ToString('o'))
- Phase 1: Find logo on the web for $LogoMinutes minutes
- Phase 2: BOL Generate PDF for $BolMinutes minutes
"@

$hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
[Win32Qa]::MoveWindow($hwnd, 40, 40, 1400, 980, $true) | Out-Null
Focus-App $hwnd
Dismiss-Dialogs $hwnd

$logoResults = New-Object System.Collections.Generic.List[object]
$bolResults = New-Object System.Collections.Generic.List[object]
$logoDeadline = $sessionStart.AddMinutes($LogoMinutes)
$i = 0

Write-Heartbeat "LOGO" "phase start until $($logoDeadline.ToString('HH:mm:ss'))"

while ((Get-Date) -lt $logoDeadline) {
  $company = $companies[$i % $companies.Count]
  $i++
  $safe = ("{0:D3}_{1}" -f $i, (($company.ToLower() -replace '[^a-z0-9]+','_').Trim('_')))
  $started = Get-Date
  Write-Heartbeat "LOGO" ("#{0} {1}" -f $i, $company)
  $entry = [ordered]@{
    phase="logo"; n=$i; company=$company; ok=$false; ms=0; notes=""; started=$started.ToString('o')
  }
  try {
    $hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
    Focus-App $hwnd
    Close-PdfViewers
    if (-not (Open-FindLogo $hwnd)) { throw "dialog_open_failed" }
    $entry.notes += "dialog=ToolsMenu; "
    $s1 = Join-Path $shotDir ($safe + "_01_dialog.png"); Cap $hwnd $s1

    # CRITICAL: do not click — barrierDismissible would close the dialog.
    # TextField has autofocus even when clipped off-screen.
    Start-Sleep -Milliseconds 200
    Type-Text $company
    Start-Sleep -Milliseconds 350
    $s2 = Join-Path $shotDir ($safe + "_02_typed.png"); Cap $hwnd $s2
    Send-KeysSafe "{ENTER}"
    $entry.notes += "search=Enter; "
    Start-Sleep -Seconds 8

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $waitShot = Join-Path $shotDir ($safe + "_wait.png")
    while ($sw.Elapsed.TotalSeconds -lt $LogoWaitSec) {
      if ((Get-Date) -gt $logoDeadline.AddSeconds(25)) { break }
      Start-Sleep -Seconds 7
      Cap $hwnd $waitShot
      if (Is-ChooseLogo $waitShot) { $ok = $true; break }
    }
    $s3 = Join-Path $shotDir ($safe + "_03_result.png"); Cap $hwnd $s3
    $entry.ok = $ok
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    $entry.bytes = (Get-Item $s3 -ErrorAction SilentlyContinue).Length
    $entry.notes += ("chooseLogo={0}; " -f $ok)

    if ($ok -and (($i % 4) -eq 0)) {
      $info = Get-WindowRectInfo -Hwnd $hwnd
      Click-Screen -X ($info.Left + [int](($info.Right-$info.Left)*0.42)) -Y ($info.Top + [int](($info.Bottom-$info.Top)*0.40))
      Start-Sleep -Seconds 2
      $entry.notes += "selectedTile; "
      Cap $hwnd (Join-Path $shotDir ($safe + "_04_selected.png"))
    } else {
      Dismiss-Dialogs $hwnd
      $entry.notes += "dismissed; "
    }
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    try { Dismiss-Dialogs $hwnd } catch {}
  }
  $entry.ended = (Get-Date).ToString('o')
  $logoResults.Add([pscustomobject]$entry) | Out-Null
  Write-Log $entry
  $pass = @($logoResults | Where-Object ok).Count
  Write-Status @"
# Phase 1 — Find logo on the web

- Elapsed: $([int]((Get-Date)-$sessionStart).TotalMinutes) min
- Attempts: $($logoResults.Count)  Pass: $pass
- Last: $company ok=$($entry.ok) ms=$($entry.ms) bytes=$($entry.bytes)
- Until: $($logoDeadline.ToString('HH:mm:ss'))
"@
}

$logoEnd = Get-Date
$logoPass = @($logoResults | Where-Object ok).Count
Write-Heartbeat "LOGO" ("phase done pass={0}/{1}" -f $logoPass, $logoResults.Count)

# -------- PHASE 2: BOL --------
$bolStart = Get-Date
$bolDeadline = $bolStart.AddMinutes($BolMinutes)
Write-Heartbeat "BOL" "phase start until $($bolDeadline.ToString('HH:mm:ss'))"
Dismiss-Dialogs $hwnd
Focus-App $hwnd
[System.Windows.Forms.SendKeys]::SendWait("^3")
Start-Sleep -Milliseconds 800
Cap $hwnd (Join-Path $shotDir "bol_00_tab.png")

$bolN = 0
while ((Get-Date) -lt $bolDeadline) {
  $bolN++
  $safe = ("bol_{0:D3}" -f $bolN)
  $started = Get-Date
  Write-Heartbeat "BOL" ("#{0}" -f $bolN)
  $beforeCount = (Count-NewPdfs $sessionStart).Count
  $entry = [ordered]@{ phase="bol"; n=$bolN; ok=$false; notes=""; started=$started.ToString('o') }
  try {
    $hwnd = Ensure-AppWindow -W 1400 -H 980 -X 40 -Y 40
    Focus-App $hwnd
    Close-PdfViewers
    [System.Windows.Forms.SendKeys]::SendWait("^3")
    Start-Sleep -Milliseconds 350

    $info = Get-WindowRectInfo -Hwnd $hwnd
    # Edit → Load sample (Load sample is near bottom of Edit menu)
    Click-Screen -X ($info.Left + 95) -Y ($info.Top + 42)
    Start-Sleep -Milliseconds 450
    foreach ($dy in @(200, 220, 240, 260, 180)) {
      Click-Screen -X ($info.Left + 130) -Y ($info.Top + $dy)
      Start-Sleep -Milliseconds 180
    }
    # Fallback: on-form Load sample button
    Click-Rel -Hwnd $hwnd -Fx 0.22 -Fy 0.90 | Out-Null
    Start-Sleep -Milliseconds 400
    $entry.notes += "loadSample; "
    Cap $hwnd (Join-Path $shotDir ($safe + "_01_form.png"))

    Focus-App $hwnd
    [System.Windows.Forms.SendKeys]::SendWait("^{ENTER}")
    $entry.notes += "ctrlEnter; "
    Start-Sleep -Seconds 3
    Send-KeysSafe "{ENTER}"; Start-Sleep -Milliseconds 400
    Send-KeysSafe "{ENTER}"; Start-Sleep -Seconds 2

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $newPdf = $null
    while ($sw.Elapsed.TotalSeconds -lt 28) {
      $pdfs = Count-NewPdfs $sessionStart
      if ($pdfs.Count -gt $beforeCount) { $newPdf = $pdfs | Select-Object -Last 1; break }
      Start-Sleep -Milliseconds 700
    }
    $entry.ms = [int]$sw.Elapsed.TotalMilliseconds
    if ($newPdf) {
      $entry.ok = $true
      $entry.pdf = $newPdf.Name
      $entry.pdfBytes = $newPdf.Length
      $entry.notes += ("pdf={0}; " -f $newPdf.Name)
    } else { $entry.notes += "noNewPdf; " }
    Cap $hwnd (Join-Path $shotDir ($safe + "_02_after.png"))
    Close-PdfViewers
    Focus-App $hwnd
  } catch {
    $entry.ok = $false
    $entry.notes = $_.Exception.Message
    try { Close-PdfViewers; Dismiss-Dialogs $hwnd } catch {}
  }
  $entry.ended = (Get-Date).ToString('o')
  $bolResults.Add([pscustomobject]$entry) | Out-Null
  Write-Log $entry
  $bolPass = @($bolResults | Where-Object ok).Count
  Write-Status @"
# Phase 2 — BOL Generate PDF

- Total elapsed: $([int]((Get-Date)-$sessionStart).TotalMinutes) min
- BOL attempts: $($bolResults.Count)  Pass: $bolPass
- Last ok=$($entry.ok) $($entry.pdf)
- Until: $($bolDeadline.ToString('HH:mm:ss'))

## Phase 1
- Logo attempts: $($logoResults.Count) pass=$logoPass
"@
}

$sessionEnd = Get-Date
$bolPass = @($bolResults | Where-Object ok).Count
$summary = [ordered]@{
  started = $sessionStart.ToString('o')
  ended = $sessionEnd.ToString('o')
  totalMinutes = [Math]::Round(($sessionEnd - $sessionStart).TotalMinutes, 1)
  logo = @{ attempts=$logoResults.Count; pass=$logoPass; fail=($logoResults.Count-$logoPass); minutes=[Math]::Round(($logoEnd-$sessionStart).TotalMinutes,1) }
  bol = @{ attempts=$bolResults.Count; pass=$bolPass; fail=($bolResults.Count-$bolPass); minutes=[Math]::Round(($sessionEnd-$bolStart).TotalMinutes,1); pdfs=@(Count-NewPdfs $sessionStart | ForEach-Object Name) }
}
$summary | ConvertTo-Json -Depth 6 | Set-Content $summaryPath -Encoding UTF8
Write-Heartbeat "DONE" ("logo {0}/{1}; bol {2}/{3}" -f $logoPass,$logoResults.Count,$bolPass,$bolResults.Count)
Write-Status @"
# 3h QA COMPLETE

- Started: $($sessionStart.ToString('o'))
- Ended: $($sessionEnd.ToString('o'))
- Total minutes: $($summary.totalMinutes)

## Find logo
- Attempts: $($logoResults.Count)  Pass: $logoPass

## BOL Generate
- Attempts: $($bolResults.Count)  Pass: $bolPass

See summary.json / run_log.jsonl / shots/
"@
Write-Host "=== 3H QA COMPLETE ==="
Write-Host ($summary | ConvertTo-Json -Depth 6)
