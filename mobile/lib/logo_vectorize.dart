import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Runs repo/bundled [scripts/logo_vectorize.py] (vtracer → SVG → PNG).
///
/// Best for flat / low-color lockups. Photo-like marks should use Real-ESRGAN.
/// Windows-first (needs local Python + vtracer + PyMuPDF). Returns null when
/// unavailable — callers fall through to ESRGAN / cubic.
class LogoVectorize {
  LogoVectorize._();

  static const _timeout = Duration(minutes: 3);

  /// Returns vectorized print PNG bytes, or null when unavailable / failed.
  static Future<Uint8List?> restore(
    Uint8List sourceBytes, {
    int minHeight = 3000,
    void Function(String)? onLog,
  }) async {
    if (!Platform.isWindows) {
      onLog?.call('vectorize: skipped (Windows-only local engine)');
      return null;
    }
    if (sourceBytes.isEmpty) return null;

    final script = await _findScript();
    if (script == null) {
      onLog?.call('vectorize: logo_vectorize.py not found next to exe/repo');
      return null;
    }

    final py = await _findPython();
    if (py == null) {
      onLog?.call('vectorize: Python not found (py/python)');
      return null;
    }

    final tmp = await Directory.systemTemp.createTemp('swift_logo_vec_');
    try {
      final input = File(p.join(tmp.path, 'in.png'));
      final output = File(p.join(tmp.path, 'out.png'));
      await input.writeAsBytes(sourceBytes, flush: true);

      onLog?.call('vectorize: ${py.exe} ${script.path}');
      final proc = await Process.run(
        py.exe,
        [
          ...py.prefixArgs,
          script.path,
          input.path,
          output.path,
          '--min-height',
          '$minHeight',
        ],
        workingDirectory: script.parent.path,
        runInShell: false,
      ).timeout(_timeout);

      if (proc.exitCode != 0) {
        final err = '${proc.stderr}'.trim();
        onLog?.call(
          'vectorize: exit ${proc.exitCode}'
          '${err.isEmpty ? '' : ' — ${err.split('\n').last}'}',
        );
        return null;
      }
      if (!await output.exists()) {
        onLog?.call('vectorize: no output file');
        return null;
      }
      final out = await output.readAsBytes();
      if (out.isEmpty) {
        onLog?.call('vectorize: empty output');
        return null;
      }
      onLog?.call('vectorize: ok (${out.length} bytes)');
      return out;
    } on TimeoutException {
      onLog?.call('vectorize: timed out');
      return null;
    } catch (e) {
      onLog?.call('vectorize: $e');
      return null;
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<File?> _findScript() async {
    final candidates = <String>[];
    try {
      candidates.add(
        p.join(p.dirname(Platform.resolvedExecutable), 'logo_vectorize.py'),
      );
      candidates.add(
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'scripts',
          'logo_vectorize.py',
        ),
      );
    } catch (_) {}
    // Dev / repo checkout: mobile/lib → ../../scripts/logo_vectorize.py
    candidates.add(
      p.normalize(
        p.join(
          p.dirname(Platform.script.toFilePath()),
          '..',
          '..',
          '..',
          'scripts',
          'logo_vectorize.py',
        ),
      ),
    );
    candidates.add(
      p.join(Directory.current.path, 'scripts', 'logo_vectorize.py'),
    );
    candidates.add(
      p.join(Directory.current.path, '..', 'scripts', 'logo_vectorize.py'),
    );
    candidates.add(p.join(Directory.current.path, 'logo_vectorize.py'));

    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) return f;
    }
    return null;
  }

  static Future<_PyCmd?> _findPython() async {
    for (final attempt in [
      (exe: 'py', prefix: <String>['-3']),
      (exe: 'python', prefix: <String>[]),
      (exe: 'python3', prefix: <String>[]),
    ]) {
      try {
        final check = await Process.run(
          attempt.exe,
          [...attempt.prefix, '-c', 'import sys; print(sys.version)'],
          runInShell: false,
        ).timeout(const Duration(seconds: 8));
        if (check.exitCode == 0) {
          return _PyCmd(attempt.exe, attempt.prefix);
        }
      } catch (_) {}
    }
    return null;
  }
}

class _PyCmd {
  const _PyCmd(this.exe, this.prefixArgs);
  final String exe;
  final List<String> prefixArgs;
}
