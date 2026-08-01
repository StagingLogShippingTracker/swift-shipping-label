import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Shared BOL document numbers via Supabase (all Windows + Android clients).
class BolDocumentNumber {
  BolDocumentNumber._();

  /// Allocates the next `SW-####` from the cloud counter.
  /// Throws [BolSerialException] when offline or the service rejects the call.
  static Future<String> allocate({
    String source = 'swift_document_generator',
    String? note,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/rpc/next_bol_serial',
    );
    final res = await http
        .post(
          uri,
          headers: {
            'apikey': AppConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
            'Content-Type': 'application/json',
            'Prefer': 'return=representation',
          },
          body: jsonEncode({
            'p_source': source,
            'p_client_note': note,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BolSerialException(
        'Could not allocate document number (${res.statusCode}). '
        'Check network and try again.',
      );
    }

    final body = jsonDecode(res.body);
    if (body is List && body.isNotEmpty) {
      final row = body.first;
      if (row is Map && row['document_number'] != null) {
        return '${row['document_number']}';
      }
    }
    if (body is Map && body['document_number'] != null) {
      return '${body['document_number']}';
    }
    throw const BolSerialException(
      'Document number service returned an unexpected response.',
    );
  }

  static String todayStamp() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final d = DateTime.now();
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class BolSerialException implements Exception {
  const BolSerialException(this.message);
  final String message;

  @override
  String toString() => message;
}
