# Shared Win32 helpers for Find-logo Windows QA
if (-not ([System.Management.Automation.PSTypeName]'Win32Qa').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Qa {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP = 0x0004;
  public const int SW_RESTORE = 9;
}
"@
}

function Get-AppHwnd {
  $p = Get-Process -Name "swift_shipping_label" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if (-not $p) { return [IntPtr]::Zero }
  return $p.MainWindowHandle
}

function Ensure-AppWindow {
  param(
    [string]$Exe = "C:\Users\Brice\OneDrive\Documents\swift_document_generator\dist\Swift Document Generator\swift_shipping_label.exe",
    [int]$X = 10,
    [int]$Y = 10,
    [int]$W = 1440,
    [int]$H = 900
  )
  $hwnd = Get-AppHwnd
  if ($hwnd -eq [IntPtr]::Zero) {
    Start-Process -FilePath $Exe
    Start-Sleep -Seconds 4
    for ($i = 0; $i -lt 20; $i++) {
      $hwnd = Get-AppHwnd
      if ($hwnd -ne [IntPtr]::Zero) { break }
      Start-Sleep -Milliseconds 500
    }
  }
  if ($hwnd -eq [IntPtr]::Zero) { throw "App window not found" }
  [Win32Qa]::ShowWindow($hwnd, [Win32Qa]::SW_RESTORE) | Out-Null
  [Win32Qa]::MoveWindow($hwnd, $X, $Y, $W, $H, $true) | Out-Null
  [Win32Qa]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 400
  return $hwnd
}

function Click-Screen {
  param([int]$X, [int]$Y)
  [Win32Qa]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 80
  [Win32Qa]::mouse_event([Win32Qa]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 40
  [Win32Qa]::mouse_event([Win32Qa]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

function Click-Rel {
  param([IntPtr]$Hwnd, [double]$Fx, [double]$Fy)
  $r = New-Object Win32Qa+RECT
  [Win32Qa]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
  $x = [int]($r.Left + ($r.Right - $r.Left) * $Fx)
  $y = [int]($r.Top + ($r.Bottom - $r.Top) * $Fy)
  Click-Screen -X $x -Y $y
  return @{ X = $x; Y = $y }
}

function Send-KeysSafe {
  param([string]$Keys)
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  Start-Sleep -Milliseconds 150
}

function Type-Text {
  param([string]$Text)
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 80
  [System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE}")
  Start-Sleep -Milliseconds 80
  [System.Windows.Forms.SendKeys]::SendWait($Text.Replace('+','{+}').Replace('^','{^}').Replace('%','{%}').Replace('~','{~}').Replace('(','{(}').Replace(')','{)}').Replace('[','{[}').Replace(']','{]}'))
  Start-Sleep -Milliseconds 200
}

function Capture-WindowShot {
  param(
    [IntPtr]$Hwnd,
    [string]$Path
  )
  Add-Type -AssemblyName System.Drawing
  $r = New-Object Win32Qa+RECT
  [Win32Qa]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
  $w = [Math]::Max(1, $r.Right - $r.Left)
  $h = [Math]::Max(1, $r.Bottom - $r.Top)
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return $Path
}

function Get-WindowRectInfo {
  param([IntPtr]$Hwnd)
  $r = New-Object Win32Qa+RECT
  [Win32Qa]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
  return [pscustomobject]@{
    Left = $r.Left; Top = $r.Top; Right = $r.Right; Bottom = $r.Bottom
    Width = ($r.Right - $r.Left); Height = ($r.Bottom - $r.Top)
  }
}