import 'dart:convert';

import 'package:http/http.dart' as http;

import 'address_match.dart';
import 'app_config.dart';

/// One Delivery Address book entry shared by Shipping + BOL.
class DeliveryAddressEntry {
  const DeliveryAddressEntry({
    required this.addressKey,
    required this.shipToName,
    required this.address,
    required this.carrier,
    required this.accountNumbers,
    required this.lastUsedAt,
  });

  final String addressKey;
  final String shipToName;
  final String address;
  final String carrier;
  final String accountNumbers;
  final DateTime lastUsedAt;

  DeliveryAddressEntry copyWith({String? addressKey}) {
    return DeliveryAddressEntry(
      addressKey: addressKey ?? this.addressKey,
      shipToName: shipToName,
      address: address,
      carrier: carrier,
      accountNumbers: accountNumbers,
      lastUsedAt: lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'address_key': addressKey,
        'ship_to_name': shipToName,
        'address': address,
        'carrier': carrier,
        'account_numbers': accountNumbers,
        'last_used_at': lastUsedAt.toUtc().toIso8601String(),
      };
}

/// Syncs Delivery Address book across Windows & Android (not contact memory).
class AddressBookSync {
  AddressBookSync();

  static const _timeout = Duration(seconds: 25);
  static const maxEntries = 80;
  /// Fetch more than [maxEntries] so collapse can see every duplicate, not just
  /// the newest 80 truncated rows.
  static const fetchLimit = 2000;

  List<DeliveryAddressEntry> entries = const [];

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  /// Canonical street fingerprint (case, hyphens, St/Street, 8th → 8).
  static String addressKey(String address) => AddressMatch.addressKey(address);

  Future<void> syncOnLaunch() async {
    entries = await fetchAll();
  }

  Future<List<DeliveryAddressEntry>> fetchAll() async {
    final raw = await _fetchRaw();
    var collapsed = _collapseDuplicates(raw);
    await _persistCollapsed(raw, collapsed);
    try {
      collapsed = _collapseDuplicates(await _fetchRaw());
    } catch (_) {}
    if (collapsed.length > maxEntries) {
      collapsed = List<DeliveryAddressEntry>.from(collapsed)
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      collapsed = collapsed.take(maxEntries).toList();
    }
    entries = sortByShipToName(collapsed);
    return entries;
  }

  /// One row per physical place on every device: drop extras and rewrite the
  /// keeper to [AddressMatch.addressKey] when the stored PK is stale.
  Future<void> _persistCollapsed(
    List<DeliveryAddressEntry> raw,
    List<DeliveryAddressEntry> collapsed,
  ) async {
    final keepKeys = <String>{};
    for (final e in collapsed) {
      final canonical = AddressMatch.addressKey(e.address);
      final destKey = canonical.isEmpty ? e.addressKey : canonical;
      keepKeys.add(destKey);
      if (destKey == e.addressKey) continue;
      try {
        await _upsertRow(e.copyWith(addressKey: destKey));
      } catch (_) {}
    }
    for (final e in raw) {
      if (keepKeys.contains(e.addressKey)) continue;
      try {
        await _deleteRow(e.addressKey);
      } catch (_) {}
    }
  }

  /// Keep one row per ship-to + place; prefer the most recently used.
  static List<DeliveryAddressEntry> _collapseDuplicates(
    List<DeliveryAddressEntry> input,
  ) {
    final best = <String, DeliveryAddressEntry>{};
    for (final e in input) {
      final id = _placeId(e.shipToName, e.address);
      if (id.isEmpty) continue;
      final prev = best[id];
      if (prev == null || e.lastUsedAt.isAfter(prev.lastUsedAt)) {
        best[id] = e;
      }
    }
    return sortByShipToName(best.values.toList());
  }

  /// Z–A by Ship To Name (case-insensitive).
  static List<DeliveryAddressEntry> sortByShipToName(
    List<DeliveryAddressEntry> input,
  ) {
    final out = List<DeliveryAddressEntry>.from(input);
    out.sort((a, b) {
      final an = a.shipToName.trim();
      final bn = b.shipToName.trim();
      if (an.isEmpty != bn.isEmpty) return an.isEmpty ? 1 : -1;
      final byName = bn.toLowerCase().compareTo(an.toLowerCase());
      if (byName != 0) return byName;
      return b.lastUsedAt.compareTo(a.lastUsedAt);
    });
    return out;
  }

  static String _placeId(String shipTo, String address) {
    final s = AddressMatch.shipToKey(shipTo);
    final a = AddressMatch.addressKey(address);
    if (s.isEmpty || a.isEmpty) return a;
    return '$s|$a';
  }

  Future<void> remember({
    required String shipToName,
    required String address,
    required String carrier,
    required String accountNumbers,
  }) async {
    final addr = address.trim();
    if (addr.isEmpty) return;
    List<DeliveryAddressEntry> existing;
    try {
      existing = await _fetchRaw();
    } catch (_) {
      existing = entries;
    }

    final matches = existing
        .where(
          (e) => AddressMatch.samePlace(
            shipToA: shipToName,
            addressA: addr,
            shipToB: e.shipToName,
            addressB: e.address,
          ),
        )
        .toList();

    final key = AddressMatch.addressKey(addr);
    if (key.isEmpty) return;

    final now = DateTime.now().toUtc();
    await _clearTombstone(key);
    for (final extra in matches) {
      if (extra.addressKey != key) {
        await _deleteRow(extra.addressKey);
      }
    }

    await _upsertRow(
      DeliveryAddressEntry(
        addressKey: key,
        shipToName: shipToName.trim(),
        address: addr,
        carrier: carrier.trim(),
        accountNumbers: accountNumbers.trim(),
        lastUsedAt: now,
      ),
    );
    await fetchAll();
  }

  Future<List<DeliveryAddressEntry>> _fetchRaw() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_addresses'
      '?select=address_key,ship_to_name,address,carrier,account_numbers,last_used_at'
      '&order=last_used_at.desc'
      '&limit=$fetchLimit',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AddressBookSyncException(
        'Could not fetch addresses (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    final out = <DeliveryAddressEntry>[];
    for (final row in body) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final key = '${m['address_key'] ?? ''}'.trim();
      final address = '${m['address'] ?? ''}'.trim();
      if (key.isEmpty || address.isEmpty) continue;
      out.add(
        DeliveryAddressEntry(
          addressKey: key,
          shipToName: '${m['ship_to_name'] ?? ''}'.trim(),
          address: address,
          carrier: '${m['carrier'] ?? ''}'.trim(),
          accountNumbers: '${m['account_numbers'] ?? ''}'.trim(),
          lastUsedAt: _parseTime(m['last_used_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    return out;
  }

  Future<void> forget(String addressOrKey) async {
    final needleKey = AddressMatch.addressKey(addressOrKey);
    if (needleKey.isEmpty && addressOrKey.trim().isEmpty) return;
    List<DeliveryAddressEntry> existing;
    try {
      existing = await _fetchRaw();
    } catch (_) {
      existing = entries;
    }
    final toDrop = <String>{};
    final raw = addressOrKey.trim().toLowerCase();
    for (final e in existing) {
      if (e.addressKey == addressOrKey.trim() ||
          e.addressKey == needleKey ||
          AddressMatch.addressKey(e.address) == needleKey ||
          e.address.trim().toLowerCase() == raw) {
        toDrop.add(e.addressKey);
      }
    }
    if (toDrop.isEmpty && needleKey.isNotEmpty) toDrop.add(needleKey);
    for (final key in toDrop) {
      await _deleteRow(key);
      await _tombstone(key);
    }
    await fetchAll();
  }

  Future<void> _upsertRow(DeliveryAddressEntry e) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_addresses'
      '?on_conflict=address_key',
    );
    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'address_key': e.addressKey,
            'ship_to_name': e.shipToName,
            'address': e.address,
            'carrier': e.carrier,
            'account_numbers': e.accountNumbers,
            'last_used_at': e.lastUsedAt.toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AddressBookSyncException(
        'Could not save address (${res.statusCode}).',
      );
    }
  }

  Future<void> _deleteRow(String key) async {
    if (key.isEmpty) return;
    final enc = Uri.encodeComponent(key);
    final del = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_addresses'
      '?address_key=eq.$enc',
    );
    await http.delete(del, headers: _headers).timeout(_timeout);
  }

  Future<void> _tombstone(String key) async {
    final tomb = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_address_tombstones'
      '?on_conflict=address_key',
    );
    await http
        .post(
          tomb,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'address_key': key,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        .timeout(_timeout);
  }

  Future<void> _clearTombstone(String key) async {
    final enc = Uri.encodeComponent(key);
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_address_tombstones'
      '?address_key=eq.$enc',
    );
    await http.delete(uri, headers: _headers).timeout(_timeout);
  }

  static DateTime? _parseTime(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse('$raw')?.toUtc();
  }
}

class AddressBookSyncException implements Exception {
  AddressBookSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
