import 'dart:io';

import 'package:flutter/material.dart';

/// Windows-only window snap / size presets via Win32 MoveWindow.
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

  static String _psShowWindow(int cmd) => '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
\$p = Get-Process -Name 'swift_shipping_label' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not \$p) { throw 'App window not found' }
[W]::ShowWindow(\$p.MainWindowHandle, $cmd) | Out-Null
''';

  static String _psMoveFraction({required bool left}) => '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
}
"@
\$p = Get-Process -Name 'swift_shipping_label' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not \$p) { throw 'App window not found' }
\$hdc = [W]::GetDC([IntPtr]::Zero)
\$sw = [W]::GetDeviceCaps(\$hdc, 118)
\$sh = [W]::GetDeviceCaps(\$hdc, 117)
[W]::ReleaseDC([IntPtr]::Zero, \$hdc) | Out-Null
[W]::ShowWindow(\$p.MainWindowHandle, 1) | Out-Null
\$w = [Math]::Floor(\$sw / 2)
\$x = ${left ? '0' : r'$w'}
[W]::MoveWindow(\$p.MainWindowHandle, \$x, 0, \$w, \$sh, \$true) | Out-Null
''';

  static String _psCentered(int width, int height) => '''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
}
"@
\$p = Get-Process -Name 'swift_shipping_label' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not \$p) { throw 'App window not found' }
\$hdc = [W]::GetDC([IntPtr]::Zero)
\$sw = [W]::GetDeviceCaps(\$hdc, 118)
\$sh = [W]::GetDeviceCaps(\$hdc, 117)
[W]::ReleaseDC([IntPtr]::Zero, \$hdc) | Out-Null
[W]::ShowWindow(\$p.MainWindowHandle, 1) | Out-Null
\$x = [Math]::Max(0, [Math]::Floor((\$sw - $width) / 2))
\$y = [Math]::Max(0, [Math]::Floor((\$sh - $height) / 2))
[W]::MoveWindow(\$p.MainWindowHandle, \$x, \$y, $width, $height, \$true) | Out-Null
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
