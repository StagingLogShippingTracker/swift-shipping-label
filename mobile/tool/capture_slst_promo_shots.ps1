# Seed SLST promo screenshots, capture Windows UI with sample data, then delete rows.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$exe = Join-Path $repo '.cache\slst\portable\SwiftStagingLog.exe'
$out = Join-Path $repo '.cache\slst\shots'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Get-SlstAuthHeaders {
  $prefsPath = Join-Path $env:APPDATA 'Swift Supply\Swift Staging & Shipping Log\shared_preferences.json'
  if (-not (Test-Path $prefsPath)) { throw "Missing SLST prefs: $prefsPath" }
  $token = (Get-Content $prefsPath -Raw | ConvertFrom-Json).'flutter.sb-gdrpdiwykmnybmkadlrv-auth-token' | ConvertFrom-Json | Select-Object -ExpandProperty access_token
  $anon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdkcnBkaXd5a21ueWJta2FkbHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1MjMyMTIsImV4cCI6MjA5NjA5OTIxMn0.Z7ih_vQic1GtzCyZmTEV-RWJnmuaNZQDfOV2_Fvan5g'
  return @{
    apikey         = $anon
    Authorization  = "Bearer $token"
    Accept         = 'application/json'
    'Content-Type' = 'application/json'
    Prefer         = 'return=representation'
  }
}

function Remove-ScreenRows {
  param($H)
  $sos = @(
    'SO-SCREEN-4412', 'SO-SCREEN-4418', 'SO-SCREEN-4420', 'SO-SCREEN-4421',
    'SO-SCREEN-4424', 'SO-SCREEN-4425', 'SO-SCREEN-4399', 'SO-SCREEN-TEST'
  )
  foreach ($so in $sos) {
    $enc = [uri]::EscapeDataString($so)
    try { Invoke-RestMethod -Method Delete -Uri "https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/staging?so=eq.$enc" -Headers $H | Out-Null } catch { }
    try { Invoke-RestMethod -Method Delete -Uri "https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/shipped?so=eq.$enc" -Headers $H | Out-Null } catch { }
  }
  try { Invoke-RestMethod -Method Delete -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/staging?so=like.SO-SCREEN-*' -Headers $H | Out-Null } catch { }
  try { Invoke-RestMethod -Method Delete -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/shipped?so=like.SO-SCREEN-*' -Headers $H | Out-Null } catch { }
}

function Add-ScreenRows {
  param($H)
  $today = Get-Date -Format 'yyyy-MM-dd'
  $tomorrow = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
  $rows = @(
    @{ so = 'SO-SCREEN-4412'; customer = 'Arc Resources'; status = 'Rush/Hotshot'; location = 'A-04-A-1'; type = '2 Skids'; qty = 2; staged_by = 'Brice'; comments = 'Rush hotshot' },
    @{ so = 'SO-SCREEN-4418'; customer = 'GCM'; status = $today; location = 'C-12-B-2'; type = '3 Skids'; qty = 3; staged_by = 'Jordan'; comments = 'Ship today' },
    @{ so = 'SO-SCREEN-4420'; customer = 'Propak Energy'; status = 'Partial'; location = 'B-02-Partial'; type = '1 Skid'; qty = 1; staged_by = 'Brice'; comments = 'Awaiting last skid' },
    @{ so = 'SO-SCREEN-4421'; customer = 'Worley Cord LP'; status = $tomorrow; location = 'N-18-C-1'; type = '4 Skids'; qty = 4; staged_by = 'Alex'; comments = 'Tomorrow pickup' },
    @{ so = 'SO-SCREEN-4424'; customer = 'Shell Canada'; status = 'Awaiting Pickup'; location = 'D-08-A-2'; type = '2 Skids'; qty = 2; staged_by = 'Jordan'; comments = 'Customer will call' },
    @{ so = 'SO-SCREEN-4425'; customer = '5Blue Process'; status = 'In Transit'; location = 'E-06-B-1'; type = '1 Skid'; qty = 1; staged_by = 'Brice'; comments = 'Cross-dock' }
  )
  foreach ($r in $rows) {
    Invoke-RestMethod -Method Post -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/staging' -Headers $H -Body ($r | ConvertTo-Json) | Out-Null
  }
  try {
    $toShip = Invoke-RestMethod -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/staging?so=eq.SO-SCREEN-4424&select=id' -Headers $H
    if ($toShip.id) {
      $rpc = @{
        p_staging_id = $toShip.id
        p_carrier    = "Murray's Trucking"
        p_shipped_by = 'Brice'
      }
      Invoke-RestMethod -Method Post -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/rpc/ship_staging_entry' -Headers $H -Body ($rpc | ConvertTo-Json) | Out-Null
      Write-Host 'Shipped SO-SCREEN-4424 via RPC'
    }
  } catch {
    Write-Warning "Ship RPC skipped: $($_.ErrorDetails.Message)"
  }
}

function Get-ScreenRowCount {
  param($H)
  $rows = Invoke-RestMethod -Uri 'https://gdrpdiwykmnybmkadlrv.supabase.co/rest/v1/staging?so=like.SO-SCREEN-*&select=so' -Headers $H
  return @($rows).Count
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if (-not ([System.Management.Automation.PSTypeName]'SlstCap').Type) {
  Add-Type @'
using System; using System.Runtime.InteropServices;
public class SlstCap {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
}
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
}

function Save-Cap {
  param([IntPtr]$Hwnd, [string]$Path)
  [void][SlstCap]::SetForegroundWindow($Hwnd)
  Start-Sleep -Milliseconds 500
  $r = New-Object RECT
  [void][SlstCap]::GetWindowRect($Hwnd, [ref]$r)
  $w = $r.Right - $r.Left
  $h = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
  $g.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  return $r
}

function Click-Rel {
  param($Rect, [int]$X, [int]$Y)
  [void][SlstCap]::SetCursorPos($Rect.Left + $X, $Rect.Top + $Y)
  Start-Sleep -Milliseconds 90
  [SlstCap]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 50
  [SlstCap]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Resize-Window {
  param([IntPtr]$Hwnd)
  $screenW = [SlstCap]::GetSystemMetrics(0)
  $screenH = [SlstCap]::GetSystemMetrics(1)
  [void][SlstCap]::ShowWindow($Hwnd, 9) # SW_RESTORE first
  Start-Sleep -Milliseconds 200
  [void][SlstCap]::MoveWindow($Hwnd, 0, 0, $screenW, $screenH, $true)
  Start-Sleep -Milliseconds 1200
}

function Dismiss-Dialogs {
  [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
  Start-Sleep -Milliseconds 350
  [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
  Start-Sleep -Milliseconds 350
}

function Click-MapBay {
  param($Rect)
  $w = $Rect.Right - $Rect.Left
  $h = $Rect.Bottom - $Rect.Top
  Click-Rel $Rect ([int]($w * 0.42)) ([int]($h * 0.72))
  Start-Sleep -Milliseconds 1000
}

function Go-Dashboard {
  param($Rect)
  Click-Rel $Rect 130 178
  Start-Sleep -Seconds 1
}

function Go-Staging {
  param($Rect)
  Click-Rel $Rect 130 218
  Start-Sleep -Seconds 1
}

function Go-Shipped {
  param($Rect)
  Click-Rel $Rect 130 248
  Start-Sleep -Seconds 1
}

function Refresh-Rect {
  param([IntPtr]$Hwnd)
  $r = New-Object RECT
  [void][SlstCap]::GetWindowRect($Hwnd, [ref]$r)
  return $r
}

$H = Get-SlstAuthHeaders
Remove-ScreenRows $H
Add-ScreenRows $H
$seedCount = Get-ScreenRowCount $H
if ($seedCount -lt 5) { throw "Expected >=5 SO-SCREEN staging rows, got $seedCount" }
Write-Host "Seeded $seedCount SO-SCREEN-* staging rows"

Stop-Process -Name SwiftStagingLog -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process $exe -WorkingDirectory (Split-Path $exe)
Start-Sleep -Seconds 22

$hwnd = (Get-Process SwiftStagingLog).MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { throw 'SwiftStagingLog window not found' }

Resize-Window $hwnd
Dismiss-Dialogs
$r = Save-Cap $hwnd (Join-Path $out '01_initial.png')
Write-Host "dashboard $($r.Right - $r.Left)x$($r.Bottom - $r.Top)"

Go-Dashboard $r
Dismiss-Dialogs
$r = Refresh-Rect $hwnd
Click-MapBay $r
Save-Cap $hwnd (Join-Path $out 'floor_bay_dialog.png') | Out-Null
Write-Host "Captured bay drill-down"
Dismiss-Dialogs

Go-Staging $r
Dismiss-Dialogs
$r = Refresh-Rect $hwnd
Save-Cap $hwnd (Join-Path $out 'nav_dashboard.png') | Out-Null
Write-Host "Captured active staging log"

Go-Shipped $r
Dismiss-Dialogs
Start-Sleep -Milliseconds 600
Save-Cap $hwnd (Join-Path $out 'nav_staging.png') | Out-Null
Write-Host "Captured shipped log"

Stop-Process -Name SwiftStagingLog -Force -ErrorAction SilentlyContinue
Remove-ScreenRows $H
$left = Get-ScreenRowCount $H
Write-Host "Deleted SO-SCREEN-* rows (remaining staging: $left)"
