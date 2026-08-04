import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'logo_recreate_cloud.dart';

/// Cross-platform "Recreate" bridge.
///
/// Two independent backends produce equivalent premium recreate output:
///
/// * **Windows local** — shells out to `python -m tools.logo_vectorizer
///   --recreate-customer`, which runs the manual-quality Bezier tracer +
///   sectional composer. This is the highest-fidelity backend and is kept
///   unchanged on Windows so we never regress the local UX. It's only
///   available when a Python 3 interpreter and the `tools/logo_vectorizer`
///   folder can both be located next to the app.
///
/// * **Cloud (Supabase Edge Function `recreate-logo`)** — runs the same
///   pipeline (background strip → color-region trace → SVG + rasterized
///   PNG) on Deno + WASM (vtracer + resvg). This is what Android uses;
///   Windows falls back to it whenever the local Python path isn't
///   available.
///
/// Both backends return a [LogoRecreateResult] with a rasterized PNG
/// (transparent background, print-ready) and, when possible, the source
/// SVG. Callers (see [AppStorage.importLogoBytes]) persist both.
class LogoRecreate {
  LogoRecreate._();

  static Directory? _cachedToolsDir;
  static String? _cachedPython;

  /// Recreate is always available now: local Python on Windows when we
  /// find it, cloud otherwise. We can only meaningfully answer "yes" when
  /// the app has *some* path to run — for the cloud path this means we
  /// trust it will reach Supabase at call time.
  static Future<bool> isAvailable() async => true;

  /// Which backend we'd use for the next call, in priority order.
  static Future<String> diagnostic() async {
    final local = await _resolveLocalBackend();
    if (local != null) {
      return 'Recreate ready — local python=${local.python} '
          'tools=${local.toolsDir.path} (cloud fallback available)';
    }
    if (Platform.isWindows) {
      return 'Recreate: local Python not found — using cloud recreate service.';
    }
    return 'Recreate: cloud recreate service (${Platform.operatingSystem}).';
  }

  /// Run recreate on [input]. Prefers local Python on Windows when
  /// available (highest fidelity) and falls back to the cloud edge
  /// function otherwise. Throws on total failure; callers catch and
  /// fall back to the raw raster.
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
        onLog?.call('Recreate local failed, trying cloud: $e');
      }
    }
    return _runCloud(input, timeout: timeout, onLog: onLog);
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

enum LogoRecreateBackend { localPython, cloud }

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
