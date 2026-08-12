import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Employee / person name helpers.
///
/// Historical note: [fetchNames] used to read SLST `dropdown_roster`
/// (`person_by`). Document Generator contact memory now uses [ContactSync]
/// / `shared_contacts` instead. [filter] remains for autocomplete typeahead.
class EmployeeDirectory {
  EmployeeDirectory({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 12);
  static const rosterType = 'person_by';

  List<String>? _cache;
  DateTime? _cachedAt;
  String? lastError;

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Accept': 'application/json',
        // Prefer exact JSON array (avoids CSV / sparse representations).
        'Accept-Profile': 'public',
      };

  /// Legacy SLST roster fetch — retained for tests/tools only. App UI uses
  /// [ContactSync] and should not call this for autocomplete.
  @Deprecated('Use ContactSync / shared_contacts for Document Generator names')
  Future<List<String>> fetchNames({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(minutes: 10)) {
      return List<String>.from(_cache!);
    }

    lastError = null;
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/dropdown_roster'
      '?roster_type=eq.$rosterType'
      '&select=value'
      '&order=value.asc',
    );

    try {
      final res = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        lastError = 'Could not load Swift contacts (${res.statusCode}).';
        debugPrint('[EmployeeDirectory] ${res.statusCode}: ${res.body}');
        throw EmployeeDirectoryException(lastError!);
      }
      final body = jsonDecode(res.body);
      if (body is! List) {
        lastError = 'Unexpected roster response.';
        throw EmployeeDirectoryException(lastError!);
      }
      final names = <String>{};
      for (final row in body) {
        if (row is! Map) continue;
        final name = '${row['value'] ?? ''}'.trim();
        if (name.isNotEmpty) names.add(name);
      }
      final sorted = names.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _cache = sorted;
      _cachedAt = now;
      debugPrint('[EmployeeDirectory] loaded ${sorted.length} names');
      return List<String>.from(sorted);
    } on EmployeeDirectoryException {
      rethrow;
    } catch (e, st) {
      lastError = 'Could not load Swift contacts.';
      debugPrint('[EmployeeDirectory] $e\n$st');
      throw EmployeeDirectoryException(lastError!);
    }
  }

  /// Filter [names] for typeahead. Empty query → first [limit] names.
  static Iterable<String> filter(
    List<String> names,
    String query, {
    int limit = 24,
  }) {
    if (names.isEmpty) return const Iterable<String>.empty();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return names.take(limit);
    final starts = <String>[];
    final contains = <String>[];
    for (final n in names) {
      final lower = n.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(n);
      } else if (lower.contains(q)) {
        contains.add(n);
      }
      if (starts.length + contains.length >= limit * 2) break;
    }
    return [...starts, ...contains].take(limit);
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
