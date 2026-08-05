import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'gemini_client.dart';
import 'logo_recreate_cloud.dart';
import 'logo_recreate_native.dart';

/// Cross-platform "Recreate" bridge.
///
/// Backend priority (no user toggle):
///
/// **Android**
/// 1. Online → Fly.io Python ([LogoRecreateCloud] / [AppConfig.recreateLogoUrl])
/// 2. Offline or Fly fails → on-device Rust ([LogoRecreateNative])
/// 3. Last resort → Supabase Deno/`vtracer` ([AppConfig.recreateLogoSupabaseUrl])
///
/// **Windows**
/// 1. Local Python if found (online or offline)
/// 2. No Python + online → Fly.io Python
/// 3. No Python + offline (or Fly fails) → on-device Rust
/// 4. Last resort → Supabase Deno/`vtracer`
///
/// All backends return a [LogoRecreateResult] with a rasterized PNG
/// (transparent background) and, when possible, the source SVG.
class LogoRecreate {
  LogoRecreate._();

  static Directory? _cachedToolsDir;
  static String? _cachedPython;

  /// True when at least one backend can be attempted (always true: cloud
  /// last-resort remains available when online).
  static Future<bool> isAvailable() async => true;

  /// Which backend we'd prefer for the next call.
  static Future<String> diagnostic() async {
    final local = await _resolveLocalBackend();
    final online = await LogoRecreateCloud.flyReachable();
    final nativeOk = await LogoRecreateNative.isAvailable();

    if (local != null) {
      return 'Recreate ready — local python=${local.python} '
          'tools=${local.toolsDir.path} '
          '(Fly online=$online, native=$nativeOk)';
    }
    if (online) {
      return 'Recreate ready — Fly.io Python online '
          '(${AppConfig.recreateLogoUrl}; native Rust '
          '${nativeOk ? "fallback available" : "unavailable"})';
    }
    if (nativeOk) {
      final nativeDiag = await LogoRecreateNative.diagnostic();
      return 'Recreate offline — $nativeDiag';
    }
    if (Platform.isWindows) {
      return 'Recreate: no local Python, Fly unreachable, native Rust '
          'not loaded — Supabase vtracer last-resort only.';
    }
    return 'Recreate: Fly unreachable and native Rust not loaded — '
        'Supabase vtracer last-resort only (${Platform.operatingSystem}).';
  }

  /// Resolved local vectorizer package dir (`tools/logo_vectorizer`), if any.
  static Future<Directory?> resolveToolsDir() => _resolveToolsRoot();

  /// Probe Fly.io health endpoint and return a short status line.
  static Future<String> flyHealthReport() async {
    final ok = await LogoRecreateCloud.flyReachable();
    final url = AppConfig.recreateLogoHealthUrl;
    return ok
        ? 'Fly.io healthy — $url'
        : 'Fly.io unreachable — $url';
  }

  /// Run recreate on [input] using the platform priority above.
  /// Throws on total failure; callers catch and keep the raw raster.
  static Future<LogoRecreateResult> run(
    File input, {
    Directory? scratchDir,
    Duration timeout = const Duration(minutes: 4),
    void Function(String)? onLog,
  }) async {
    // Windows: local Python first when available (online or offline).
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
        onLog?.call('Recreate local Python failed, trying Fly/native: $e');
      }
    }

    final online = await LogoRecreateCloud.flyReachable();
    if (online) {
      try {
        return await _runCloud(
          input,
          endpointUrl: AppConfig.recreateLogoUrl,
          backend: LogoRecreateBackend.flyPython,
          timeout: timeout,
          onLog: onLog,
        );
      } catch (e) {
        onLog?.call('Recreate Fly.io failed, trying native/cloud: $e');
      }
    } else {
      onLog?.call('Recreate: Fly unreachable — using on-device / last-resort');
    }

    if (await LogoRecreateNative.isAvailable()) {
      try {
        return await _runNative(input, onLog: onLog);
      } catch (e) {
        onLog?.call('Recreate native failed, trying Supabase last-resort: $e');
      }
    }

    return _runCloud(
      input,
      endpointUrl: AppConfig.recreateLogoSupabaseUrl,
      backend: LogoRecreateBackend.supabaseCloud,
      timeout: timeout,
      onLog: onLog,
    );
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
    required String endpointUrl,
    required LogoRecreateBackend backend,
    required Duration timeout,
    void Function(String)? onLog,
  }) async {
    final cloudTimeout =
        timeout > const Duration(seconds: 120) ? const Duration(seconds: 120) : timeout;
    final cloud = await LogoRecreateCloud.run(
      input,
      endpointUrl: endpointUrl,
      timeout: cloudTimeout,
      onLog: onLog,
    );
    final label = backend == LogoRecreateBackend.flyPython
        ? 'fly python'
        : 'supabase vtracer';
    return LogoRecreateResult(
      pngBytes: cloud.pngBytes,
      svgBytes: cloud.svgBytes,
      workDir: null,
      log: '$label recreate (${cloud.elapsed.inMilliseconds}ms, '
          'sections=${cloud.sectionCount}, '
          'palette=${cloud.paletteHex.join(",")}, '
          'bg_stripped=${cloud.backgroundStripped}, '
          'server=${cloud.serverBackend})',
      backend: backend,
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
        // Match Fly/Android: transparent PNG (CLI default is white).
        '--render-background',
        'transparent',
        // Enable Gemini assist when GEMINI_API_KEY is available in the env.
        '--ai',
        '--ai-providers',
        'gemini',
      ],
      workingDirectory: packageParent.path,
      runInShell: false,
      environment: {
        ...Platform.environment,
        if (GeminiClient.resolveApiKey().isNotEmpty)
          'GEMINI_API_KEY': GeminiClient.resolveApiKey(),
        if (AppConfig.geminiProjectNumber.isNotEmpty)
          'GEMINI_PROJECT_NUMBER': AppConfig.geminiProjectNumber,
        if (AppConfig.geminiModel.isNotEmpty)
          'GEMINI_MODEL': AppConfig.geminiModel,
      },
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

enum LogoRecreateBackend {
  localPython,
  flyPython,
  nativeRust,
  supabaseCloud,
}

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
