import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Windows-side "Recreate" pipeline bridge: locate `tools/logo_vectorizer`,
/// pick a Python interpreter, and run the premium vectorizer against the
/// caller's raster so it comes back as a clean SVG + PNG.
///
/// The Flutter Windows build ships the `tools/` directory alongside the exe
/// (see `scripts/build_windows.ps1`). When running from source, the tools
/// live two levels above the exe (`mobile\build\...\Release`). We probe a
/// handful of well-known candidate directories, so both packaged and dev
/// runs work without config.
///
/// On non-Windows platforms this class is a graceful no-op:
///   - `isAvailable()` returns false
///   - `run(...)` throws `UnsupportedError`
///
/// The caller (usually [AppStorage.importLogoBytes]) is responsible for
/// falling back to the raw raster when recreate can't run.
class LogoRecreate {
  LogoRecreate._();

  /// Diagnostic — location of the resolved `tools/logo_vectorizer` folder
  /// (or `null` if we couldn't find it).
  static Directory? _cachedToolsDir;

  /// Diagnostic — resolved Python interpreter (or `null` if none found).
  static String? _cachedPython;

  /// True on Windows once we have both a python interpreter and the tools folder.
  static Future<bool> isAvailable() async {
    if (!Platform.isWindows) return false;
    return await _resolvePython() != null && await _resolveToolsRoot() != null;
  }

  /// Human-readable diagnostic for logs / snackbars.
  static Future<String> diagnostic() async {
    if (!Platform.isWindows) {
      return 'Recreate requires Windows (current: ${Platform.operatingSystem}).';
    }
    final py = await _resolvePython();
    final tools = await _resolveToolsRoot();
    if (py == null) return 'Recreate: Python 3 not found on PATH.';
    if (tools == null) {
      return 'Recreate: tools/logo_vectorizer directory not found next to the app.';
    }
    return 'Recreate ready — python=$py tools=${tools.path}';
  }

  /// Run recreate on [inputPath]; return the recreated PNG bytes on success.
  ///
  /// Writes the SVG next to the PNG so the caller (or callers of the SVG
  /// export) can persist both. Throws on failure — callers should catch and
  /// fall back to the original raster.
  static Future<LogoRecreateResult> run(
    File input, {
    Directory? scratchDir,
    Duration timeout = const Duration(minutes: 4),
    void Function(String)? onLog,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Recreate vectorizer is Windows-only in this build.',
      );
    }
    final py = await _resolvePython();
    final tools = await _resolveToolsRoot();
    if (py == null || tools == null) {
      throw StateError(await diagnostic());
    }
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
    final packageParent = tools.parent.parent;

    onLog?.call('recreate: python=$py cwd=${packageParent.path}');

    final proc = await Process.start(
      py,
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
        // Rasterize wide enough that scaling / zoom in-app stays crisp;
        // the vector SVG remains the source of truth and is also stored.
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
    );
  }

  static Future<Directory?> _resolveToolsRoot() async {
    if (_cachedToolsDir != null && await _cachedToolsDir!.exists()) {
      return _cachedToolsDir;
    }
    final candidates = <String>[];
    final exeDir = File(Platform.resolvedExecutable).parent;
    // 1. Packaged next to the exe (build_windows.ps1 copies this in).
    candidates.add(p.join(exeDir.path, 'tools', 'logo_vectorizer'));
    // 2. Dev run from Flutter build output: mobile/build/.../Release
    candidates.add(
      p.normalize(
        p.join(exeDir.path, '..', '..', '..', '..', '..', 'tools',
            'logo_vectorizer'),
      ),
    );
    // 3. Dev run one level up.
    candidates.add(
      p.normalize(p.join(exeDir.path, '..', 'tools', 'logo_vectorizer')),
    );
    // 4. LOCALAPPDATA install target (see scripts/publish_release.ps1).
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      candidates.add(p.join(localAppData,
          'swift-document-generator-mobile', 'tools', 'logo_vectorizer'));
    }
    // 5. Known dev checkouts.
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

class LogoRecreateResult {
  LogoRecreateResult({
    required this.pngBytes,
    required this.svgBytes,
    required this.workDir,
    required this.log,
  });

  final List<int> pngBytes;
  final List<int>? svgBytes;
  final Directory workDir;
  final String log;
}
