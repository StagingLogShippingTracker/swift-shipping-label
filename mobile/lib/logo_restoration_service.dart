import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Fly.io RealESRGAN restore — POST a logo, get a 3000px+ PNG back.
class LogoRestorationService {
  LogoRestorationService({http.Client? client, String? endpointUrl})
      : _client = client ?? http.Client(),
        _endpointUrl = endpointUrl ?? AppConfig.restoreLogoUrl;

  final http.Client _client;
  final String _endpointUrl;

  static const _timeout = Duration(minutes: 15);

  /// Upload [imageFile] to Fly.io and return the restored PNG in the temp cache.
  Future<File> restoreLogo(File imageFile) async {
    if (!await imageFile.exists()) {
      throw StateError('Logo file not found: ${imageFile.path}');
    }

    final uri = Uri.parse(_endpointUrl);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
          filename: p.basename(imageFile.path),
        ),
      );

    final streamed = await _client.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamed).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.trim();
      throw StateError(
        'Logo restore failed (${response.statusCode})'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw StateError('Logo restore returned empty PNG');
    }

    final dir = await getTemporaryDirectory();
    final out = File(
      p.join(
        dir.path,
        'logo_restore_${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );
    await out.writeAsBytes(response.bodyBytes, flush: true);
    return out;
  }
}
