import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Employee / person names from the SLST `dropdown_roster` table
/// (`roster_type = person_by`).
class EmployeeDirectory {
  EmployeeDirectory({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  List<String>? _cache;
  DateTime? _cachedAt;

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Accept': 'application/json',
      };

  /// Full names only, sorted. Cached briefly to keep autocomplete snappy.
  Future<List<String>> fetchNames({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(minutes: 10)) {
      return List<String>.from(_cache!);
    }

    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/dropdown_roster'
      '?roster_type=eq.person_by'
      '&select=value'
      '&order=value.asc',
    );
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw EmployeeDirectoryException(
        'Could not load Swift contacts (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return const [];
    final names = <String>{};
    for (final row in body) {
      if (row is! Map) continue;
      final name = '${row['value'] ?? ''}'.trim();
      if (name.isNotEmpty) names.add(name);
    }
    final sorted = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _cache = sorted;
    _cachedAt = now;
    return List<String>.from(sorted);
  }

  void dispose() {
    _client.close();
  }
}

class EmployeeDirectoryException implements Exception {
  EmployeeDirectoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
