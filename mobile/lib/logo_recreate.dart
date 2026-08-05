import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'logo_recreate_cloud.dart';
import 'logo_recreate_native.dart';

/// Cross-platform "Recreate" bridge.
///
/// Backends (priority order):
///
/// 1. **Windows local Python** — `tools/logo_vectorizer --recreate-customer`
///    (manual-quality Bezier + sectional). Highest fidelity when available.
/// 2. **On-device Rust** — `native/logo_recreate` via `dart:ffi`
///    ([LogoRecreateNative]). Primary path for Android once the `.so` is
///    shipped; optional on Windows without Python. MVP uses palette +
///    contour polylines (Bezier parity is a follow-up).
/// 3. **Cloud fallback** — Supabase Deno/`vtracer` edge function
///    ([LogoRecreateCloud]). Used only when local/native paths fail or are
///    unavailable. **Not** Fly.io (that experiment was aborted).
///
/// All backends return a [LogoRecreateResult] with a rasterized PNG
/// (transparent background) and, when possible, the source SVG.
class LogoRecreate {
  LogoRecreate._();

  static Directory? _cachedToolsDir;
  static String? _cachedPython;

  /// True when at least one backend can be attempted (always true: cloud
  /// is the last resort; native/Python are opportunistic).
  static Future<bool> isAvailable() async => true;

  /// Which backend we'd prefer for the next call.
  static Future<String> diagnostic() async {
    final local = await _resolveLocalBackend();
    if (local != null) {
      return 'Recreate ready — local python=${local.python} '
          'tools=${local.toolsDir.path} '
          '(native + cloud fallback available)';
    }
    if (await LogoRecreateNative.isAvailable()) {
      return await LogoRecreateNative.diagnostic();
    }
    if (Platform.isWindows) {
      return 'Recreate: local Python not found, native Rust not loaded — '
          'using Supabase cloud recreate fallback.';
    }
    return 'Recreate: native Rust not loaded — '
        'using Supabase cloud recreate fallback (${Platform.operatingSystem}).';
  }

  /// Run recreate on [input]. Prefers Windows Python, then on-device Rust,
  /// then cloud. Throws on total failure; callers catch and keep the raw
  /// raster.
  static Future<LogoRecreateResult> run(
    File input, {
    Directory? scratchDir,
    Duration timeout = const Duration(minutes: 4),
    void Function(String)? onLog,
  }) async {
    final local = await _resolveLocalBackend();
    if (local != null) {
      try {
        return await _runLocal(
          input,
          local: local,
          scratchDir: scratchDir,
          timeout: timeout,
          onLog: onLog,
        );
      } catch (e) {
        onLog?.call('Recreate local Python failed, trying native/cloud: $e');
      }
    }

    if (await LogoRecreateNative.isAvailable()) {
      try {
        return await _runNative(input, onLog: onLog);
      } catch (e) {
        onLog?.call('Recreate native failed, trying cloud: $e');
      }
    }

    return _runCloud(input, timeout: timeout, onLog: onLog);
  }

  static Future<LogoRecreateResult> _runNative(
    File input, {
    void Function(String)? onLog,
  }) async {
    final bytes = await input.readAsBytes();
    final native = await LogoRecreateNative.runBytes(bytes, onLog: onLog);
    return LogoRecreateResult(
      pngBytes: native.pngBytes,
      svgBytes: native.svgBytes,
      workDir: null,
      log: 'native recreate (${native.elapsed.inMilliseconds}ms, '
          'sections=${native.sectionCount}, '
          'palette=${native.paletteHex.join(",")}, '
          'bg_stripped=${native.backgroundStripped}, '
          'backend=${native.backend})',
      backend: LogoRecreateBackend.nativeRust,
    );
  }

  static Future<LogoRecreateResult> _runCloud(
    File input, {
    required Duration timeout,
    void Function(String)? onLog,
  }) async {
    final cloudTimeout =
        timeout > const Duration(seconds: 120) ? const Duration(seconds: 120) : timeout;
    final cloud = await LogoRecreateCloud.run(
      input,
      timeout: cloudTimeout,
      onLog: onLog,
    );
    return LogoRecreateResult(
      pngBytes: cloud.pngBytes,
      svgBytes: cloud.svgBytes,
      workDir: null,
      log: 'cloud recreate (${cloud.elapsed.inMilliseconds}ms, '
          'sections=${cloud.sectionCount}, '
          'palette=${cloud.paletteHex.join(",")}, '
          'bg_stripped=${cloud.backgroundStripped})',
      backend: LogoRecreateBackend.cloud,
    );
  }

  static Future<LogoRecreateResult> _runLocal(
    File input, {
    required _LocalBackend local,
    Directory? scratchDir,
    required Duration timeout,
    void Function(String)? onLog,
  }) async {
    final work = scratchDir ??
        await Directory.systemTemp.createTemp('swift_recreate_');
    final stem = p.basenameWithoutExtension(input.path).trim().isEmpty
        ? 'logo'
        : p.basenameWithoutExtension(input.path).trim();
    final svgOut = File(p.join(work.path, '$stem.recreate.svg'));
    final pngOut = File(p.join(work.path, '$stem.recreate.png'));

    // The tools folder we resolved is `.../tools/logo_vectorizer`; the
    // package parent (the folder that contains `tools/`) needs to be the
    // working directory so `python -m tools.logo_vectorizer` resolves.
    final packageParent = local.toolsDir.parent.parent;

    onLog?.call('recreate: python=${local.python} cwd=${packageParent.path}');

    final proc = await Process.start(
      local.python,
      [
        '-X',
        'utf8',
        '-m',
        'tools.logo_vectorizer',
        '--recreate-customer',
        '--input',
        input.absolute.path,
        '--output',
        svgOut.absolute.path,
        '--render-png',
        pngOut.absolute.path,
        '--render-width',
        '3000',
      ],
      workingDirectory: packageParent.path,
      runInShell: false,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    final so = proc.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
    final se = proc.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBuf.write(chunk);
      onLog?.call(chunk.trim());
    });

    int? exitCode;
    try {
      exitCode = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      throw TimeoutException(
        'Recreate timed out after ${timeout.inSeconds}s',
      );
    } finally {
      await so.cancel();
      await se.cancel();
    }

    if (exitCode != 0) {
      throw StateError(
        'Recreate failed (exit=$exitCode): ${stderrBuf.toString().trim()}',
      );
    }
    if (!await pngOut.exists()) {
      throw StateError(
        'Recreate produced no PNG (stderr=${stderrBuf.toString().trim()})',
      );
    }
    return LogoRecreateResult(
      pngBytes: await pngOut.readAsBytes(),
      svgBytes: await svgOut.exists() ? await svgOut.readAsBytes() : null,
      workDir: work,
      log: stdoutBuf.toString() + stderrBuf.toString(),
      backend: LogoRecreateBackend.localPython,
    );
  }

  static Future<_LocalBackend?> _resolveLocalBackend() async {
    if (!Platform.isWindows) return null;
    final python = await _resolvePython();
    final tools = await _resolveToolsRoot();
    if (python == null || tools == null) return null;
    return _LocalBackend(python: python, toolsDir: tools);
  }

  static Future<Directory?> _resolveToolsRoot() async {
    if (_cachedToolsDir != null && await _cachedToolsDir!.exists()) {
      return _cachedToolsDir;
    }
    final candidates = <String>[];
    final exeDir = File(Platform.resolvedExecutable).parent;
    candidates.add(p.join(exeDir.path, 'tools', 'logo_vectorizer'));
    candidates.add(
      p.normalize(
        p.join(exeDir.path, '..', '..', '..', '..', '..', 'tools',
            'logo_vectorizer'),
      ),
    );
    candidates.add(
      p.normalize(p.join(exeDir.path, '..', 'tools', 'logo_vectorizer')),
    );
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      candidates.add(p.join(localAppData,
          'swift-document-generator-mobile', 'tools', 'logo_vectorizer'));
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      candidates.add(p.join(userProfile, 'OneDrive', 'Documents',
          'swift_document_generator', 'tools', 'logo_vectorizer'));
      candidates.add(p.join(userProfile, 'Documents',
          'swift_document_generator', 'tools', 'logo_vectorizer'));
    }
    for (final path in candidates) {
      final dir = Directory(path);
      if (await dir.exists() &&
          await File(p.join(dir.path, '__main__.py')).exists()) {
        _cachedToolsDir = dir;
        return dir;
      }
    }
    return null;
  }

  static Future<String?> _resolvePython() async {
    if (_cachedPython != null) return _cachedPython;
    final probes = <String>[
      'py',
      'python',
      'python3',
    ];
    for (final exe in probes) {
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
      } catch (_) {
        // Try next candidate.
      }
    }
    return null;
  }
}

enum LogoRecreateBackend { localPython, nativeRust, cloud }

class _LocalBackend {
  const _LocalBackend({required this.python, required this.toolsDir});
  final String python;
  final Directory toolsDir;
}

class LogoRecreateResult {
  LogoRecreateResult({
    required this.pngBytes,
    required this.svgBytes,
    required this.workDir,
    required this.log,
    required this.backend,
  });

  final List<int> pngBytes;
  final List<int>? svgBytes;
  final Directory? workDir;
  final String log;
  final LogoRecreateBackend backend;
}
