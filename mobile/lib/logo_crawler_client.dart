import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Bridge to the Playwright Google Images crawler under `services/logo_crawler`.
///
/// Priority:
/// 1. Local HTTP sidecar at [endpoint] (optional, if already running)
/// 2. Local Python + `crawl_google_images.py` via [Process] (Windows desktop)
///
/// Returns original image URLs (not gstatic thumbs). Empty list on failure —
/// callers must fall open to CSE / Bing / other sources.
class LogoCrawlerClient {
  LogoCrawlerClient({
    this.endpoint = defaultEndpoint,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const defaultEndpoint = 'http://127.0.0.1:8765';
  static const defaultMax = 30;

  final String endpoint;
  final http.Client _http;

  static String? _cachedPython;
  static String? _cachedScript;
  static bool? _httpHealthy;

  /// Probe local HTTP sidecar (fast). Cached for a few minutes.
  Future<bool> httpReachable() async {
    final cached = _httpHealthy;
    if (cached != null) return cached;
    try {
      final res = await _http
          .get(Uri.parse('$endpoint/health'))
          .timeout(const Duration(seconds: 2));
      _httpHealthy = res.statusCode == 200;
    } catch (_) {
      _httpHealthy = false;
    }
    return _httpHealthy ?? false;
  }

  /// Clear health / path caches (tests / after install).
  static void clearCaches() {
    _cachedPython = null;
    _cachedScript = null;
    _httpHealthy = null;
  }

  /// Fetch Google Images URLs for [query] (and optional extra [queries]).
  Future<List<String>> crawl({
    required String query,
    List<String> queries = const [],
    int maxResults = defaultMax,
    Duration timeout = const Duration(seconds: 40),
    void Function(String)? onLog,
  }) async {
    final qs = <String>[
      query.trim(),
      ...queries.map((q) => q.trim()).where((q) => q.isNotEmpty),
    ].where((q) => q.isNotEmpty).toList();
    if (qs.isEmpty) return const [];

    if (await httpReachable()) {
      try {
        final urls = await _crawlHttp(qs, maxResults: maxResults, timeout: timeout);
        if (urls.isNotEmpty) {
          onLog?.call('logo crawler HTTP: ${urls.length} urls');
          return urls;
        }
      } catch (e) {
        onLog?.call('logo crawler HTTP failed: $e');
        _httpHealthy = false;
      }
    }

    if (Platform.isWindows) {
      try {
        final urls = await _crawlProcess(
          qs,
          maxResults: maxResults,
          timeout: timeout,
          onLog: onLog,
        );
        if (urls.isNotEmpty) {
          onLog?.call('logo crawler Process: ${urls.length} urls');
          return urls;
        }
      } catch (e) {
        onLog?.call('logo crawler Process failed: $e');
      }
    }

    return const [];
  }

  Future<List<String>> _crawlHttp(
    List<String> queries, {
    required int maxResults,
    required Duration timeout,
  }) async {
    final body = jsonEncode({
      if (queries.length == 1) 'query': queries.first,
      if (queries.length > 1) 'queries': queries,
      'max': maxResults,
      'scroll_rounds': 6,
      'headless': true,
    });
    final res = await _http
        .post(
          Uri.parse('$endpoint/crawl'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: body,
        )
        .timeout(timeout);
    if (res.statusCode != 200) return const [];
    return _parseUrls(res.body);
  }

  Future<List<String>> _crawlProcess(
    List<String> queries, {
    required int maxResults,
    required Duration timeout,
    void Function(String)? onLog,
  }) async {
    final python = await _resolvePython();
    final script = await _resolveScript();
    if (python == null || script == null) {
      onLog?.call(
        'logo crawler: Python/script not found '
        '(python=$python script=$script)',
      );
      return const [];
    }

    final args = <String>[
      ...pythonLauncherPrefix(python),
      script,
      '--max',
      '$maxResults',
      '--scroll-rounds',
      '6',
      for (final q in queries) ...['--query', q],
    ];

    final proc = await Process.start(
      python,
      args,
      workingDirectory: File(script).parent.path,
      runInShell: false,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    final so = proc.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
    final se = proc.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBuf.write(chunk);
      final line = chunk.trim();
      if (line.isNotEmpty) onLog?.call(line);
    });

    try {
      final code = await proc.exitCode.timeout(timeout);
      await so.cancel();
      await se.cancel();
      final out = stdoutBuf.toString().trim();
      if (out.isEmpty) {
        onLog?.call(
          'logo crawler empty stdout (exit=$code): ${stderrBuf.toString().trim()}',
        );
        return const [];
      }
      // Last JSON object on stdout (ignore any chrome noise lines).
      final jsonLine = out
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('{') && l.endsWith('}'))
          .lastOrNull;
      if (jsonLine == null) return const [];
      return _parseUrls(jsonLine);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigkill);
      onLog?.call('logo crawler timed out after ${timeout.inSeconds}s');
      return const [];
    } finally {
      await so.cancel();
      await se.cancel();
    }
  }

  static List<String> _parseUrls(String raw) {
    try {
      final body = jsonDecode(raw);
      if (body is! Map) return const [];
      final urls = body['urls'];
      if (urls is! List) return const [];
      return [
        for (final u in urls)
          if (u is String && u.startsWith('http')) u,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> _resolvePython() async {
    if (_cachedPython != null) return _cachedPython;
    for (final probe in ['py', 'python', 'python3']) {
      try {
        final r = await Process.run(
          probe,
          probe == 'py' ? ['-3', '-c', 'print(1)'] : ['-c', 'print(1)'],
          runInShell: true,
        );
        if (r.exitCode == 0) {
          _cachedPython = probe == 'py' ? 'py' : probe;
          // Prefer `py -3` style: store as space-joined for Process.start? Better
          // return actual executable. For `py`, Process.start('py', ['-3', script]).
          if (probe == 'py') {
            _cachedPython = 'py';
          }
          return _cachedPython;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Args prefix when using the Windows `py` launcher (`-3`).
  static List<String> pythonLauncherPrefix(String python) =>
      python == 'py' ? ['-3'] : const [];

  static Future<String?> _resolveScript() async {
    if (_cachedScript != null && await File(_cachedScript!).exists()) {
      return _cachedScript;
    }
    final candidates = <String>[];
    final exeDir = File(Platform.resolvedExecutable).parent;
    candidates.add(
      p.join(exeDir.path, 'services', 'logo_crawler', 'crawl_google_images.py'),
    );
    candidates.add(
      p.normalize(
        p.join(
          exeDir.path,
          '..',
          '..',
          '..',
          '..',
          '..',
          'services',
          'logo_crawler',
          'crawl_google_images.py',
        ),
      ),
    );
    candidates.add(
      p.normalize(
        p.join(exeDir.path, '..', 'services', 'logo_crawler', 'crawl_google_images.py'),
      ),
    );

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      candidates.add(
        p.join(
          userProfile,
          'OneDrive',
          'Documents',
          'swift_document_generator',
          'services',
          'logo_crawler',
          'crawl_google_images.py',
        ),
      );
      candidates.add(
        p.join(
          userProfile,
          'Documents',
          'swift_document_generator',
          'services',
          'logo_crawler',
          'crawl_google_images.py',
        ),
      );
    }

    // Repo-relative from current working directory (dev `flutter run`).
    candidates.add(
      p.normalize(
        p.join(Directory.current.path, 'services', 'logo_crawler', 'crawl_google_images.py'),
      ),
    );
    candidates.add(
      p.normalize(
        p.join(
          Directory.current.path,
          '..',
          'services',
          'logo_crawler',
          'crawl_google_images.py',
        ),
      ),
    );

    for (final path in candidates) {
      if (await File(path).exists()) {
        _cachedScript = path;
        return path;
      }
    }
    return null;
  }
}

extension _LastOrNull<E> on Iterable<E> {
  E? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
