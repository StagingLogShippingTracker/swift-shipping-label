import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'app_storage.dart';

/// Syncs Document Generator contact / employee names across Windows & Android.
///
/// Uses Document Generator–owned Supabase tables (`shared_contacts` +
/// `shared_contact_tombstones`). Does **not** read or write SLST
/// `dropdown_roster`.
class ContactSync {
  ContactSync(this.storage);

  final AppStorage storage;

  static const _timeout = Duration(seconds: 25);

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  static String nameKey(String raw) => raw.trim().toLowerCase();

  /// Pull shared names, push local-only names, honor tombstones, refresh cache.
  Future<void> syncOnLaunch() async {
    final remote = await _fetchContacts();
    final tombstones = await _fetchTombstones();

    // Drop local names that were forgotten on another device.
    var localChanged = false;
    final kept = <String>[];
    for (final name in storage.rememberedContacts) {
      final key = nameKey(name);
      if (tombstones.containsKey(key)) {
        localChanged = true;
        continue;
      }
      kept.add(name);
    }
    if (localChanged) {
      storage.rememberedContacts = kept;
      await storage.saveRememberedContacts();
    }

    // Seed / push names that exist only on this device (and are not tombstoned).
    final remoteKeys = {for (final c in remote) c.nameKey};
    final now = DateTime.now().toUtc();
    for (final name in storage.rememberedContacts) {
      final key = nameKey(name);
      if (remoteKeys.contains(key)) continue;
      if (tombstones.containsKey(key)) continue;
      await _upsertContact(name: name, lastUsedAt: now);
    }

    // Authoritative list = remote contacts (after local-only push).
    final refreshed = await _fetchContacts();
    refreshed.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    final next = <String>[];
    final seen = <String>{};
    for (final row in refreshed) {
      if (tombstones.containsKey(row.nameKey)) continue;
      if (seen.contains(row.nameKey)) continue;
      seen.add(row.nameKey);
      next.add(row.name);
      if (next.length >= AppStorage.maxRememberedContacts) break;
    }
    storage.rememberedContacts = next;
    await storage.saveRememberedContacts();
  }

  /// Remember a name locally and upsert to the shared Document Generator store.
  Future<bool> remember(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return false;
    final key = nameKey(name);
    final now = DateTime.now().toUtc();

    final localChanged = await storage.rememberContact(name);
    try {
      await _clearTombstone(key);
      await _upsertContact(name: name, lastUsedAt: now);
    } catch (e) {
      // Local save already happened; surface as soft failure to caller.
      throw ContactSyncException('Could not sync contact “$name”: $e');
    }
    return localChanged;
  }

  /// Forget a name locally and remove it from the shared store (with tombstone).
  Future<bool> forget(String raw) async {
    final name = raw.trim();
    if (name.isEmpty) return false;
    final key = nameKey(name);
    final localChanged = await storage.forgetContact(name);
    try {
      await _deleteContact(key);
      await _upsertTombstone(key);
    } catch (e) {
      throw ContactSyncException('Could not sync contact delete “$name”: $e');
    }
    return localChanged;
  }

  /// Clear local cache and wipe shared contacts (+ write tombstones).
  Future<void> clearAll() async {
    final snapshot = List<String>.from(storage.rememberedContacts);
    await storage.clearRememberedContacts();
    try {
      for (final name in snapshot) {
        final key = nameKey(name);
        await _deleteContact(key);
        await _upsertTombstone(key);
      }
      // Also clear any remaining remote rows (other devices may have more).
      final remote = await _fetchContacts();
      for (final row in remote) {
        await _deleteContact(row.nameKey);
        await _upsertTombstone(row.nameKey);
      }
    } catch (e) {
      throw ContactSyncException('Could not clear shared contacts: $e');
    }
  }

  Future<List<_RemoteContact>> _fetchContacts() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contacts'
      '?select=name_key,name,last_used_at,updated_at'
      '&order=last_used_at.desc',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ContactSyncException(
        'Could not fetch shared contacts (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    final out = <_RemoteContact>[];
    for (final row in body) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final key = '${m['name_key'] ?? ''}'.trim();
      final name = '${m['name'] ?? ''}'.trim();
      if (key.isEmpty || name.isEmpty) continue;
      out.add(
        _RemoteContact(
          nameKey: key,
          name: name,
          lastUsedAt: _parseTime(m['last_used_at']) ??
              _parseTime(m['updated_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    return out;
  }

  Future<Map<String, DateTime>> _fetchTombstones() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contact_tombstones'
      '?select=name_key,deleted_at',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ContactSyncException(
        'Could not fetch contact tombstones (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return {};
    final out = <String, DateTime>{};
    for (final row in body) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final key = '${m['name_key'] ?? ''}'.trim();
      if (key.isEmpty) continue;
      out[key] = _parseTime(m['deleted_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return out;
  }

  Future<void> _upsertContact({
    required String name,
    required DateTime lastUsedAt,
  }) async {
    final key = nameKey(name);
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contacts?on_conflict=name_key',
    );
    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'name_key': key,
            'name': name.trim(),
            'last_used_at': lastUsedAt.toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ContactSyncException(
        'Could not upsert contact (${res.statusCode}).',
      );
    }
  }

  Future<void> _deleteContact(String key) async {
    final enc = Uri.encodeComponent(key);
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contacts?name_key=eq.$enc',
    );
    final res = await http.delete(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ContactSyncException(
        'Could not delete contact (${res.statusCode}).',
      );
    }
  }

  Future<void> _upsertTombstone(String key) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contact_tombstones'
      '?on_conflict=name_key',
    );
    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'name_key': key,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ContactSyncException(
        'Could not write contact tombstone (${res.statusCode}).',
      );
    }
  }

  Future<void> _clearTombstone(String key) async {
    final enc = Uri.encodeComponent(key);
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_contact_tombstones'
      '?name_key=eq.$enc',
    );
    await http.delete(uri, headers: _headers).timeout(_timeout);
  }

  static DateTime? _parseTime(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse('$raw')?.toUtc();
  }
}

class _RemoteContact {
  const _RemoteContact({
    required this.nameKey,
    required this.name,
    required this.lastUsedAt,
  });

  final String nameKey;
  final String name;
  final DateTime lastUsedAt;
}

class ContactSyncException implements Exception {
  ContactSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
