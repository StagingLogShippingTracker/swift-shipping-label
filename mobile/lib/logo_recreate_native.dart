import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// On-device Rust Recreate (`native/logo_recreate`) via `dart:ffi`.
///
/// When the dynamic library is not bundled (typical until Android jniLibs /
/// Windows DLL packaging lands), [isAvailable] is false and
/// [LogoRecreate] falls through to cloud.
class LogoRecreateNative {
  LogoRecreateNative._();

  static bool _resolveAttempted = false;
  static String? _loadedName;

  static _RecreatePng? _recreatePng;
  static _RecreateFree? _recreateFree;

  /// True when `logo_recreate` native lib loaded and symbols resolved.
  static Future<bool> isAvailable() async {
    _ensureLoaded();
    return _recreatePng != null && _recreateFree != null;
  }

  static Future<String> diagnostic() async {
    if (await isAvailable()) {
      return 'Recreate native Rust ready (${_loadedName ?? "loaded"})';
    }
    return 'Recreate native Rust unavailable '
        '(build native/logo_recreate and ship .so/.dll — see README)';
  }

  static Future<NativeRecreateResult> runBytes(
    List<int> bytes, {
    int maxColors = 6,
    int renderWidth = 3000,
    void Function(String)? onLog,
  }) async {
    _ensureLoaded();
    final recreate = _recreatePng;
    final free = _recreateFree;
    if (recreate == null || free == null) {
      throw StateError('Recreate native: library not loaded');
    }
    if (bytes.isEmpty) {
      throw StateError('Recreate native: empty image bytes');
    }

    onLog?.call(
      'Recreate (native): ${bytes.length} bytes, '
      'max_colors=$maxColors render_width=$renderWidth',
    );
    final stopwatch = Stopwatch()..start();

    final data = Uint8List.fromList(bytes);
    final ptr = malloc<Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      final resultPtr = recreate(
        ptr,
        data.length,
        maxColors,
        renderWidth,
      );
      if (resultPtr == nullptr) {
        throw StateError('Recreate native: null result');
      }
      try {
        final jsonStr = resultPtr.toDartString();
        stopwatch.stop();
        final decoded = jsonDecode(jsonStr);
        if (decoded is! Map) {
          throw StateError('Recreate native: unexpected JSON type');
        }
        final map = Map<String, dynamic>.from(decoded);
        final err = '${map['error'] ?? ''}';
        if (err.isNotEmpty) {
          throw StateError('Recreate native: $err');
        }
        final pngB64 = '${map['png_base64'] ?? ''}';
        if (pngB64.isEmpty) {
          throw StateError('Recreate native: missing png_base64');
        }
        final svg = '${map['svg'] ?? ''}';
        final palette = <String>[];
        final paletteRaw = map['palette_hex'];
        if (paletteRaw is List) {
          for (final v in paletteRaw) {
            final s = '$v'.trim();
            if (s.isNotEmpty) palette.add(s);
          }
        }
        onLog?.call(
          'Recreate (native): ${stopwatch.elapsedMilliseconds}ms '
          'sections=${map['section_count']} '
          'palette=${palette.join(",")} '
          'backend=${map['backend']}',
        );
        return NativeRecreateResult(
          pngBytes: base64.decode(pngB64),
          svgBytes:
              svg.isEmpty ? null : Uint8List.fromList(utf8.encode(svg)),
          paletteHex: palette,
          sectionCount: (map['section_count'] is num)
              ? (map['section_count'] as num).toInt()
              : 0,
          backgroundStripped: map['bg_stripped'] == true,
          backend: '${map['backend'] ?? 'native_rust'}',
          elapsed: stopwatch.elapsed,
        );
      } finally {
        free(resultPtr);
      }
    } finally {
      malloc.free(ptr);
    }
  }

  static void _ensureLoaded() {
    if (_resolveAttempted) return;
    _resolveAttempted = true;
    try {
      final opened = _openLibrary();
      if (opened == null) return;
      final lib = opened.lib;
      _loadedName = opened.name;
      _recreatePng = lib
          .lookup<NativeFunction<_RecreatePngNative>>('logo_recreate_png')
          .asFunction();
      _recreateFree = lib
          .lookup<NativeFunction<_RecreateFreeNative>>('logo_recreate_free')
          .asFunction();
    } catch (_) {
      _loadedName = null;
      _recreatePng = null;
      _recreateFree = null;
    }
  }

  static ({DynamicLibrary lib, String name})? _openLibrary() {
    if (Platform.isAndroid) {
      try {
        return (
          lib: DynamicLibrary.open('liblogo_recreate.so'),
          name: 'liblogo_recreate.so',
        );
      } catch (_) {
        return null;
      }
    }
    if (Platform.isWindows) {
      for (final path in _windowsCandidates()) {
        try {
          if (File(path).existsSync()) {
            return (lib: DynamicLibrary.open(path), name: path);
          }
        } catch (_) {}
      }
      try {
        return (
          lib: DynamicLibrary.open('logo_recreate.dll'),
          name: 'logo_recreate.dll',
        );
      } catch (_) {
        return null;
      }
    }
    if (Platform.isLinux) {
      try {
        return (
          lib: DynamicLibrary.open('liblogo_recreate.so'),
          name: 'liblogo_recreate.so',
        );
      } catch (_) {
        return null;
      }
    }
    if (Platform.isMacOS || Platform.isIOS) {
      try {
        return (
          lib: DynamicLibrary.open('liblogo_recreate.dylib'),
          name: 'liblogo_recreate.dylib',
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static List<String> _windowsCandidates() {
    final out = <String>[];
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    out.add(p.join(exeDir, 'logo_recreate.dll'));
    out.add(p.join(exeDir, 'native', 'logo_recreate.dll'));
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      out.add(p.join(
        userProfile,
        'OneDrive',
        'Documents',
        'swift_document_generator',
        'native',
        'logo_recreate',
        'target',
        'release',
        'logo_recreate.dll',
      ));
    }
    return out;
  }
}

typedef _RecreatePngNative = Pointer<Utf8> Function(
  Pointer<Uint8>,
  IntPtr,
  Int32,
  Int32,
);
typedef _RecreatePng = Pointer<Utf8> Function(
  Pointer<Uint8>,
  int,
  int,
  int,
);

typedef _RecreateFreeNative = Void Function(Pointer<Utf8>);
typedef _RecreateFree = void Function(Pointer<Utf8>);

class NativeRecreateResult {
  NativeRecreateResult({
    required this.pngBytes,
    required this.svgBytes,
    required this.paletteHex,
    required this.sectionCount,
    required this.backgroundStripped,
    required this.backend,
    required this.elapsed,
  });

  final Uint8List pngBytes;
  final Uint8List? svgBytes;
  final List<String> paletteHex;
  final int sectionCount;
  final bool backgroundStripped;
  final String backend;
  final Duration elapsed;
}
