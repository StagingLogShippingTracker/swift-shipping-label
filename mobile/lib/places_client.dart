import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'gemini_client.dart';

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;

  String get caption => secondaryText.isEmpty ? 'Google Maps' : secondaryText;
}

/// Google Places Autocomplete (New) + Place Details. Canada-biased, not exclusive.
class PlacesClient {
  PlacesClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _niskuLat = 53.3334;
  static const _niskuLng = -113.5291;

  static String resolveApiKey() {
    final candidates = <String>[
      AppConfig.googlePlacesApiKeyDefine,
      AppConfig.googleMapsApiKeyDefine,
      GeminiClient.envValue('GOOGLE_PLACES_API_KEY'),
      GeminiClient.envValue('GOOGLE_MAPS_API_KEY'),
    ];
    for (final c in candidates) {
      final v = c.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static bool get isConfigured => resolveApiKey().isNotEmpty;

  Future<List<PlacePrediction>> autocomplete(String query) async {
    final key = resolveApiKey();
    final q = query.trim();
    if (key.isEmpty || q.length < 3) return const [];
    try {
      final res = await _client
          .post(
            Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': key,
            },
            body: jsonEncode({
              'input': q,
              'languageCode': 'en',
              'regionCode': 'CA',
              'locationBias': {
                'circle': {
                  'center': {'latitude': _niskuLat, 'longitude': _niskuLng},
                  'radius': 900000.0,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return _autocompleteLegacy(key, q);
      }
      final body = jsonDecode(res.body);
      if (body is! Map) return const [];
      final suggestions = body['suggestions'];
      if (suggestions is! List) return const [];
      final out = <PlacePrediction>[];
      for (final item in suggestions) {
        if (item is! Map) continue;
        final pred = item['placePrediction'];
        if (pred is! Map) continue;
        final id = '${pred['placeId'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final text = pred['text'];
        final structured = pred['structuredFormat'];
        var primary = '';
        var secondary = '';
        if (structured is Map) {
          primary = '${(structured['mainText'] as Map?)?['text'] ?? ''}'.trim();
          secondary =
              '${(structured['secondaryText'] as Map?)?['text'] ?? ''}'.trim();
        }
        if (primary.isEmpty && text is Map) {
          primary = '${text['text'] ?? ''}'.trim();
        }
        if (primary.isEmpty) continue;
        out.add(
          PlacePrediction(
            placeId: id,
            primaryText: primary,
            secondaryText: secondary,
          ),
        );
        if (out.length >= 8) break;
      }
      return out;
    } catch (_) {
      return _autocompleteLegacy(key, q);
    }
  }

  Future<List<PlacePrediction>> _autocompleteLegacy(
    String key,
    String query,
  ) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
        'input': query,
        'key': key,
        'language': 'en',
        'region': 'ca',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final body = jsonDecode(res.body);
      if (body is! Map) return const [];
      final preds = body['predictions'];
      if (preds is! List) return const [];
      final out = <PlacePrediction>[];
      for (final item in preds) {
        if (item is! Map) continue;
        final id = '${item['place_id'] ?? ''}'.trim();
        final desc = '${item['description'] ?? ''}'.trim();
        if (id.isEmpty || desc.isEmpty) continue;
        final structured = item['structured_formatting'];
        var primary = desc;
        var secondary = '';
        if (structured is Map) {
          primary = '${structured['main_text'] ?? desc}'.trim();
          secondary = '${structured['secondary_text'] ?? ''}'.trim();
        }
        out.add(
          PlacePrediction(
            placeId: id,
            primaryText: primary,
            secondaryText: secondary.isEmpty ? desc : secondary,
          ),
        );
        if (out.length >= 8) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<String?> placeDetailsAddress(String placeId) async {
    final key = resolveApiKey();
    final id = placeId.trim();
    if (key.isEmpty || id.isEmpty) return null;
    try {
      final enc = Uri.encodeComponent(id);
      final res = await _client
          .get(
            Uri.parse('https://places.googleapis.com/v1/places/$enc'),
            headers: {
              'X-Goog-Api-Key': key,
              'X-Goog-FieldMask':
                  'formattedAddress,addressComponents',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body);
        if (body is Map) {
          final formatted = _fromComponents(body) ??
              '${body['formattedAddress'] ?? ''}'.trim();
          if (formatted.isNotEmpty) return formatted;
        }
      }
    } catch (_) {}
    return _placeDetailsLegacy(key, id);
  }

  Future<String?> _placeDetailsLegacy(String key, String placeId) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
        'place_id': placeId,
        'key': key,
        'language': 'en',
        'fields': 'address_component,formatted_address',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final result = body['result'];
      if (result is! Map) return null;
      return _fromLegacyComponents(result) ??
          '${result['formatted_address'] ?? ''}'.trim();
    } catch (_) {
      return null;
    }
  }

  static String? _fromComponents(Map body) {
    final comps = body['addressComponents'];
    if (comps is! List) return null;
    String pick(List<String> types) {
      for (final c in comps) {
        if (c is! Map) continue;
        final t = c['types'];
        if (t is! List) continue;
        final ts = t.map((e) => '$e').toSet();
        if (types.any(ts.contains)) {
          return '${c['longText'] ?? c['shortText'] ?? ''}'.trim();
        }
      }
      return '';
    }

    final num = pick(['street_number']);
    final route = pick(['route']);
    final street = [num, route].where((e) => e.isNotEmpty).join(' ');
    final city = pick(['locality', 'postal_town', 'sublocality']);
    final prov = pick(['administrative_area_level_1']);
    final postal = pick(['postal_code']);
    final line2 = [
      city,
      if (prov.isNotEmpty) prov,
      if (postal.isNotEmpty) postal,
    ].where((e) => e.isNotEmpty).join(', ');
    final lines = [street, line2].where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  static String? _fromLegacyComponents(Map result) {
    final comps = result['address_components'];
    if (comps is! List) return null;
    String pick(List<String> types) {
      for (final c in comps) {
        if (c is! Map) continue;
        final t = c['types'];
        if (t is! List) continue;
        final ts = t.map((e) => '$e').toSet();
        if (types.any(ts.contains)) {
          return '${c['long_name'] ?? c['short_name'] ?? ''}'.trim();
        }
      }
      return '';
    }

    final num = pick(['street_number']);
    final route = pick(['route']);
    final street = [num, route].where((e) => e.isNotEmpty).join(' ');
    final city = pick(['locality', 'postal_town', 'sublocality']);
    final prov = pick(['administrative_area_level_1']);
    final postal = pick(['postal_code']);
    final line2 = [
      city,
      if (prov.isNotEmpty) prov,
      if (postal.isNotEmpty) postal,
    ].where((e) => e.isNotEmpty).join(', ');
    final lines = [street, line2].where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return null;
    return lines.join('\n');
  }
}
