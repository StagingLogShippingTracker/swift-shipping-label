import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Cross-platform "Recreate" bridge that calls the Supabase edge function.
///
/// Fallback only — preferred paths are Windows local Python and on-device
/// Rust (`LogoRecreateNative`). This Deno/`vtracer` function is weaker than
/// the Python Bezier pipeline but needs no native binary.
///
/// Fly.io Python recreate was aborted; do not point here at fly.dev.
class LogoRecreateCloud {
  LogoRecreateCloud._();

  /// Supabase `recreate-logo` edge function. Override via
  /// [AppConfig.recreateLogoUrl] (`--dart-define=RECREATE_LOGO_URL=...`).
  static Uri get _endpoint {
    final base = Uri.parse(AppConfig.recreateLogoUrl);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'render_width': '3000',
      },
    );
  }

  /// True when we're online enough to at least try. We treat unavailable
  /// network as a graceful failure at call time rather than a hard gate,
  /// so users can still queue the upload / retry.
  static Future<bool> isAvailable() async => true;

  static Future<CloudRecreateResult> run(
    File input, {
    Duration timeout = const Duration(seconds: 120),
    void Function(String)? onLog,
  }) async {
    onLog?.call('Recreate (cloud): uploading ${input.path}');
    final bytes = await input.readAsBytes();
    return runBytes(bytes, onLog: onLog, timeout: timeout);
  }

  static Future<CloudRecreateResult> runBytes(
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 120),
    void Function(String)? onLog,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Recreate cloud: empty image bytes');
    }
    final headers = {
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      'Content-Type': _guessContentType(bytes),
    };
    onLog?.call('Recreate (cloud): POST ${_endpoint.toString()}');
    final stopwatch = Stopwatch()..start();
    late final http.Response res;
    try {
      res = await http
          .post(_endpoint, headers: headers, body: bytes)
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
      'bg_stripped=${map['bg_stripped']}',
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
  });

  final Uint8List pngBytes;
  final Uint8List? svgBytes;
  final List<String> paletteHex;
  final int sectionCount;
  final bool backgroundStripped;
  final Duration elapsed;
}
