import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Windows-only local restore via `logo_restorer.py` (RealESRGAN).
///
/// Target is **[minDimension] px tall**; width follows aspect ratio.
/// Fly.io is not used on Windows.
class LogoRestorer {
  LogoRestorer._();

  static const minDimension = 3000;
  static const cacheFileName = 'logo_restore_cache.json';

  static String? _cachedPython;
  static String? _cachedScript;
  static final Map<String, Future<File>> _inFlight = {};

  /// Returns [source] on non-Windows, when already high-res, or on failure.
  ///
  /// Restoration runs in a background isolate (Python subprocess) so the UI
  /// isolate stays responsive.
  static Future<File> ensureHighRes(
    File source, {
    required Directory logosDir,
    void Function(String)? onLog,
  }) async {
    if (!Platform.isWindows) return source;
    if (!await source.exists()) return source;

    final identity = await _sourceIdentity(source);
    final existing = _inFlight[identity];
    if (existing != null) return existing;

    final future = _ensureHighResUncapped(
      source,
      logosDir: logosDir,
      identity: identity,
      onLog: onLog,
    );
    _inFlight[identity] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(identity);
    }
  }

  static Future<File> _ensureHighResUncapped(
    File source, {
    required Directory logosDir,
    required String identity,
    void Function(String)? onLog,
  }) async {
    await logosDir.create(recursive: true);
    final cache = await _loadCache(logosDir);
    final cachedPath = cache[identity];
    if (cachedPath != null) {
      final cached = File(cachedPath);
      if (await cached.exists() &&
          await _heightPx(cached) >= minDimension) {
        onLog?.call('logo_restorer: cache hit ${cached.path}');
        return cached;
      }
    }

    final height = await _heightPx(source);
    if (height >= minDimension) {
      cache[identity] = source.absolute.path;
      await _saveCache(logosDir, cache);
      onLog?.call('logo_restorer: already ${height}px tall, skip');
      return source;
    }

    final python = await _resolvePython();
    final script = await _resolveScript();
    if (python == null || script == null) {
      onLog?.call(
        'logo_restorer: Python missing — Lanczos to ${minDimension}px height',
      );
      final dest = await _restoredDestFile(source, logosDir);
      final scaled = await _lanczosToMinHeight(source, dest);
      if (scaled != null) {
        cache[identity] = scaled.absolute.path;
        await _saveCache(logosDir, cache);
        return scaled;
      }
      return source;
    }

    final dest = await _restoredDestFile(source, logosDir);
    onLog?.call(
      'logo_restorer: restoring ${source.path} -> ${dest.path} '
      '(${height}px tall, python=$python)',
    );

    try {
      final code = await Isolate.run(
        () => logoRestoreRunProcess(
          python: python,
          script: script,
          input: source.absolute.path,
          output: dest.absolute.path,
          minDimension: minDimension,
        ),
      );
      if (code != 0 || !await dest.exists() || await _heightPx(dest) < minDimension) {
        onLog?.call('logo_restorer: python incomplete, Lanczos to ${minDimension}px height');
        final scaled = await _lanczosToMinHeight(source, dest);
        if (scaled != null) {
          cache[identity] = scaled.absolute.path;
          await _saveCache(logosDir, cache);
          return scaled;
        }
        onLog?.call('logo_restorer: python exit=$code, keeping original');
        return source;
      }
      cache[identity] = dest.absolute.path;
      await _saveCache(logosDir, cache);
      onLog?.call('logo_restorer: wrote ${dest.path}');
      return dest;
    } catch (e) {
      onLog?.call('logo_restorer: failed, Lanczos fallback: $e');
      final scaled = await _lanczosToMinHeight(source, dest);
      if (scaled != null) {
        cache[identity] = scaled.absolute.path;
        await _saveCache(logosDir, cache);
        return scaled;
      }
      return source;
    }
  }

  static Future<int> _heightPx(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return heightOfBytes(bytes);
    } catch (_) {
      return 0;
    }
  }

  static int heightOfBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;
    return decoded.height;
  }

  static int longestEdgeOfBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;
    return decoded.width > decoded.height ? decoded.width : decoded.height;
  }

  /// CPU Lanczos to [minDimension] height when Python/RealESRGAN is unavailable.
  static Future<File?> _lanczosToMinHeight(File source, File dest) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      if (decoded.height >= minDimension) {
        await dest.writeAsBytes(bytes, flush: true);
        return dest;
      }
      final scale = minDimension / decoded.height;
      final w = math.max(1, (decoded.width * scale).round());
      final resized = img.copyResize(
        decoded,
        width: w,
        height: minDimension,
        interpolation: img.Interpolation.cubic,
      );
      await dest.writeAsBytes(img.encodePng(resized), flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sourceIdentity(File source) async {
    final stat = await source.stat();
    return '${p.normalize(source.absolute.path)}|'
        '${stat.size}|${stat.modified.millisecondsSinceEpoch}';
  }

  static Future<File> _restoredDestFile(File source, Directory logosDir) async {
    var stem = p.basenameWithoutExtension(source.path);
    if (stem.toLowerCase().endsWith('_restored')) {
      stem = stem.substring(0, stem.length - '_restored'.length);
    }
    stem = stem.replaceAll(RegExp(r'[^\w\- .]+'), '_');
    if (stem.isEmpty) stem = 'logo';
    var dest = File(p.join(logosDir.path, '${stem}_restored.png'));
    if (p.equals(dest.path, source.absolute.path)) {
      dest = File(p.join(logosDir.path, '${stem}_restored_hr.png'));
    }
    return dest;
  }

  static File _cacheFile(Directory logosDir) =>
      File(p.join(logosDir.path, cacheFileName));

  static Future<Map<String, String>> _loadCache(Directory logosDir) async {
    final file = _cacheFile(logosDir);
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCache(
    Directory logosDir,
    Map<String, String> cache,
  ) async {
    final file = _cacheFile(logosDir);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(cache));
  }

  static Future<String?> _resolvePython() async {
    if (_cachedPython != null) return _cachedPython;
    for (final exe in const ['py', 'python', 'python3']) {
      try {
        final args = exe == 'py'
            ? const ['-3', '-c', 'import sys; print(sys.version_info[0])']
            : const ['-c', 'import sys; print(sys.version_info[0])'];
        final result = await Process.run(
          exe,
          args,
          runInShell: Platform.isWindows,
        );
        if (result.exitCode == 0 &&
            (result.stdout as String).trim().startsWith('3')) {
          _cachedPython = exe;
          return exe;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _resolveScript() async {
    if (_cachedScript != null && await File(_cachedScript!).exists()) {
      return _cachedScript;
    }
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      p.join(exeDir.path, 'logo_restorer.py'),
      p.normalize(p.join(exeDir.path, '..', 'logo_restorer.py')),
      p.normalize(
        p.join(exeDir.path, '..', '..', '..', '..', '..', 'logo_restorer.py'),
      ),
    ];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      candidates.add(
        p.join(
          localAppData,
          'swift-document-generator-mobile',
          'logo_restorer.py',
        ),
      );
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      candidates.add(
        p.join(
          userProfile,
          'OneDrive',
          'Documents',
          'swift_document_generator',
          'logo_restorer.py',
        ),
      );
      candidates.add(
        p.join(
          userProfile,
          'Documents',
          'swift_document_generator',
          'logo_restorer.py',
        ),
      );
    }
    candidates.add(p.join(Directory.current.path, 'logo_restorer.py'));
    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) {
        _cachedScript = f.absolute.path;
        return _cachedScript;
      }
    }
    return null;
  }
}

/// Top-level so [Isolate.run] can spawn it off the UI isolate.
Future<int> logoRestoreRunProcess({
  required String python,
  required String script,
  required String input,
  required String output,
  required int minDimension,
}) async {
  final args = python == 'py'
      ? <String>[
          '-3',
          script,
          input,
          output,
          '--min-dimension',
          '$minDimension',
        ]
      : <String>[
          script,
          input,
          output,
          '--min-dimension',
          '$minDimension',
        ];
  final result = await Process.run(
    python,
    args,
    runInShell: python == 'py',
    workingDirectory: File(script).parent.path,
  ).timeout(const Duration(minutes: 15));
  if (result.exitCode != 0) {
    debugPrint('logo_restorer stderr: ${result.stderr}');
  }
  return result.exitCode;
}
