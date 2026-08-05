import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// HTTP client for cloud Recreate backends (Fly.io Python primary,
/// Supabase Deno/`vtracer` last resort).
///
/// Preferred non-cloud paths are Windows local Python and on-device Rust
/// (`LogoRecreateNative`) — see [LogoRecreate] selection order.
class LogoRecreateCloud {
  LogoRecreateCloud._();

  /// Fly.io Python recreate endpoint (default [AppConfig.recreateLogoUrl]).
  static Uri endpointFor(String url) {
    final base = Uri.parse(url);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'render_width': '3000',
      },
    );
  }

  /// Lightweight online probe — GET Fly `/health` with a short timeout.
  /// Retries once: cold-started machines (`min_machines_running = 0`) often
  /// miss a single 8s window; a second attempt after wake usually succeeds.
  static Future<bool> flyReachable({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = Uri.parse(AppConfig.recreateLogoHealthUrl);
    Future<bool> once() async {
      try {
        final res = await http.get(uri).timeout(timeout);
        return res.statusCode >= 200 && res.statusCode < 300;
      } on TimeoutException {
        return false;
      } on SocketException {
        return false;
      } catch (_) {
        return false;
      }
    }

    if (await once()) return true;
    // Brief pause then one retry for Fly machine cold start.
    await Future<void>.delayed(const Duration(seconds: 2));
    return once();
  }

  static Future<CloudRecreateResult> run(
    File input, {
    String? endpointUrl,
    Duration timeout = const Duration(seconds: 120),
    void Function(String)? onLog,
  }) async {
    onLog?.call('Recreate (cloud): uploading ${input.path}');
    final bytes = await input.readAsBytes();
    return runBytes(
      bytes,
      endpointUrl: endpointUrl,
      onLog: onLog,
      timeout: timeout,
    );
  }

  static Future<CloudRecreateResult> runBytes(
    List<int> bytes, {
    String? endpointUrl,
    Duration timeout = const Duration(seconds: 120),
    void Function(String)? onLog,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Recreate cloud: empty image bytes');
    }
    final endpoint = endpointFor(endpointUrl ?? AppConfig.recreateLogoUrl);
    final headers = {
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      'Content-Type': _guessContentType(bytes),
    };
    onLog?.call('Recreate (cloud): POST ${endpoint.toString()}');
    final stopwatch = Stopwatch()..start();
    late final http.Response res;
    try {
      res = await http
          .post(endpoint, headers: headers, body: bytes)
          .timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'Recreate cloud timed out after ${timeout.inSeconds}s',
      );
    } on SocketException catch (e) {
      throw StateError('Recreate cloud: network unavailable (${e.message})');
    }
    stopwatch.stop();
    onLog?.call(
      'Recreate (cloud): status=${res.statusCode} '
      'time=${stopwatch.elapsedMilliseconds}ms',
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final snippet = res.body.length > 240
          ? '${res.body.substring(0, 240)}…'
          : res.body;
      throw StateError(
        'Recreate cloud failed (${res.statusCode}): $snippet',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw StateError('Recreate cloud: unexpected response type');
    }
    final map = Map<String, dynamic>.from(body);
    final pngB64 = '${map['png_base64'] ?? ''}';
    final svg = '${map['svg'] ?? ''}';
    if (pngB64.isEmpty) {
      throw StateError(
        'Recreate cloud: response missing png_base64 '
        '(error=${map['error']})',
      );
    }
    final palette = <String>[];
    final paletteRaw = map['palette_hex'];
    if (paletteRaw is List) {
      for (final v in paletteRaw) {
        final s = '$v'.trim();
        if (s.isNotEmpty) palette.add(s);
      }
    }
    onLog?.call(
      'Recreate (cloud): palette=${palette.join(',')} '
      'sections=${map['section_count']} '
      'bg_stripped=${map['bg_stripped']} '
      'backend=${map['backend']}',
    );
    return CloudRecreateResult(
      pngBytes: base64.decode(pngB64),
      svgBytes: svg.isEmpty ? null : Uint8List.fromList(utf8.encode(svg)),
      paletteHex: palette,
      sectionCount: (map['section_count'] is num)
          ? (map['section_count'] as num).toInt()
          : 0,
      backgroundStripped: map['bg_stripped'] == true,
      elapsed: stopwatch.elapsed,
      serverBackend: '${map['backend'] ?? ''}',
    );
  }

  static String _guessContentType(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'image/webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return 'application/octet-stream';
  }
}

class CloudRecreateResult {
  CloudRecreateResult({
    required this.pngBytes,
    required this.svgBytes,
    required this.paletteHex,
    required this.sectionCount,
    required this.backgroundStripped,
    required this.elapsed,
    this.serverBackend = '',
  });

  final Uint8List pngBytes;
  final Uint8List? svgBytes;
  final List<String> paletteHex;
  final int sectionCount;
  final bool backgroundStripped;
  final Duration elapsed;
  final String serverBackend;
}
