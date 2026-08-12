import 'dart:convert';

import 'package:http/http.dart' as http;

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

  List<DeliveryAddressEntry> entries = const [];

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  static String addressKey(String address) {
    final normalized = address
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  Future<void> syncOnLaunch() async {
    entries = await fetchAll();
  }

  Future<List<DeliveryAddressEntry>> fetchAll() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_addresses'
      '?select=address_key,ship_to_name,address,carrier,account_numbers,last_used_at'
      '&order=last_used_at.desc'
      '&limit=$maxEntries',
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
    entries = out;
    return out;
  }

  Future<void> remember({
    required String shipToName,
    required String address,
    required String carrier,
    required String accountNumbers,
  }) async {
    final addr = address.trim();
    if (addr.isEmpty) return;
    final key = addressKey(addr);
    final now = DateTime.now().toUtc();
    await _clearTombstone(key);
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
            'address_key': key,
            'ship_to_name': shipToName.trim(),
            'address': addr,
            'carrier': carrier.trim(),
            'account_numbers': accountNumbers.trim(),
            'last_used_at': now.toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AddressBookSyncException(
        'Could not save address (${res.statusCode}).',
      );
    }
    await fetchAll();
  }

  Future<void> forget(String addressOrKey) async {
    final key = addressKey(addressOrKey);
    if (key.isEmpty) return;
    final enc = Uri.encodeComponent(key);
    final del = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/shared_delivery_addresses'
      '?address_key=eq.$enc',
    );
    await http.delete(del, headers: _headers).timeout(_timeout);
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
    await fetchAll();
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
