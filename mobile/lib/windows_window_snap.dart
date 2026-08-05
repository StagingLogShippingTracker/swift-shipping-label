import 'dart:io';

/// Windows-only window snap / size presets via Win32 MoveWindow.
///
/// Uses the monitor work area that contains the app window (virtual-screen
/// coordinates). Earlier builds used DESKTOPHORZRES/VERTRES (physical pixels),
/// which on high-DPI displays moved the window off-screen / made it unusable.
class WindowsWindowSnap {
  WindowsWindowSnap._();

  static Future<String> apply(WindowsSnapPreset preset) async {
    if (!Platform.isWindows) return 'Window snap is Windows-only.';
    final script = switch (preset) {
      WindowsSnapPreset.maximize => _psShowWindow(3),
      WindowsSnapPreset.restore => _psShowWindow(9),
      WindowsSnapPreset.halfLeft => _psMoveFraction(left: true),
      WindowsSnapPreset.halfRight => _psMoveFraction(left: false),
      WindowsSnapPreset.centered1440 => _psCentered(1440, 900),
      WindowsSnapPreset.centered1280 => _psCentered(1280, 800),
      WindowsSnapPreset.centered1100 => _psCentered(1100, 760),
    };
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
    );
    if (result.exitCode != 0) {
      final err = '${result.stderr}'.trim();
      return err.isEmpty ? 'Window snap failed.' : err;
    }
    return 'Window: ${preset.label}';
  }

  static const _win32Types = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SwiftWinSnap {
  public const uint MONITOR_DEFAULTTONEAREST = 2;
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);
  [DllImport("user32.dll", CharSet = CharSet.Auto)]
  public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
  }
}
"@
''';

  static String _psResolveWindow() => r'''
$p = Get-Process -Name 'swift_shipping_label' -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
  Select-Object -First 1
if (-not $p) { throw 'App window not found' }
$hwnd = $p.MainWindowHandle
''';

  static String _psWorkArea() => r'''
$mi = New-Object SwiftWinSnap+MONITORINFO
$mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][SwiftWinSnap+MONITORINFO])
$hMon = [SwiftWinSnap]::MonitorFromWindow($hwnd, [SwiftWinSnap]::MONITOR_DEFAULTTONEAREST)
if (-not [SwiftWinSnap]::GetMonitorInfo($hMon, [ref]$mi)) { throw 'GetMonitorInfo failed' }
$left = $mi.rcWork.Left
$top = $mi.rcWork.Top
$sw = [Math]::Max(320, $mi.rcWork.Right - $mi.rcWork.Left)
$sh = [Math]::Max(240, $mi.rcWork.Bottom - $mi.rcWork.Top)
''';

  static String _psShowWindow(int cmd) => '''
$_win32Types
${_psResolveWindow()}
[SwiftWinSnap]::ShowWindow(\$hwnd, $cmd) | Out-Null
''';

  static String _psMoveFraction({required bool left}) => '''
$_win32Types
${_psResolveWindow()}
${_psWorkArea()}
[SwiftWinSnap]::ShowWindow(\$hwnd, 1) | Out-Null
\$w = [Math]::Floor(\$sw / 2)
\$h = \$sh
\$x = ${left ? r'$left' : r'$left + $w'}
\$y = \$top
[SwiftWinSnap]::MoveWindow(\$hwnd, \$x, \$y, \$w, \$h, \$true) | Out-Null
''';

  static String _psCentered(int width, int height) => '''
$_win32Types
${_psResolveWindow()}
${_psWorkArea()}
[SwiftWinSnap]::ShowWindow(\$hwnd, 1) | Out-Null
\$w = [Math]::Min($width, \$sw)
\$h = [Math]::Min($height, \$sh)
\$x = \$left + [Math]::Max(0, [Math]::Floor((\$sw - \$w) / 2))
\$y = \$top + [Math]::Max(0, [Math]::Floor((\$sh - \$h) / 2))
[SwiftWinSnap]::MoveWindow(\$hwnd, \$x, \$y, \$w, \$h, \$true) | Out-Null
''';
}

enum WindowsSnapPreset {
  maximize,
  restore,
  halfLeft,
  halfRight,
  centered1440,
  centered1280,
  centered1100;

  String get label => switch (this) {
        WindowsSnapPreset.maximize => 'Maximize',
        WindowsSnapPreset.restore => 'Restore',
        WindowsSnapPreset.halfLeft => 'Snap left half',
        WindowsSnapPreset.halfRight => 'Snap right half',
        WindowsSnapPreset.centered1440 => 'Centered 1440×900',
        WindowsSnapPreset.centered1280 => 'Centered 1280×800',
        WindowsSnapPreset.centered1100 => 'Centered 1100×760',
      };
}
