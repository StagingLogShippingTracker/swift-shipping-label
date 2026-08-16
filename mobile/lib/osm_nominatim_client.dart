import 'dart:convert';

import 'package:http/http.dart' as http;

class NominatimHit {
  const NominatimHit({
    required this.streetLine,
    required this.localityLine,
    required this.displayAddress,
    this.houseNumber = '',
    this.city = '',
    this.province = '',
    this.postal = '',
  });

  final String streetLine;
  final String localityLine;
  final String displayAddress;
  final String houseNumber;
  final String city;
  final String province;
  final String postal;
}

/// Leading civic number plus the rest of the street (e.g. 2971 + 130 avenue).
class CivicStreetQuery {
  const CivicStreetQuery({
    required this.raw,
    this.houseNumber = '',
    this.streetName = '',
    this.localityHint = '',
  });

  final String raw;
  final String houseNumber;
  final String streetName;
  final String localityHint;

  bool get hasStructuredStreet =>
      houseNumber.isNotEmpty && streetName.isNotEmpty;

  /// Nominatim `street` parameter: housenumber + streetname.
  String get structuredStreet =>
      [houseNumber, streetName].where((e) => e.isNotEmpty).join(' ');
}

/// OpenStreetMap Nominatim search. No API key. Canada-biased unless the query
/// looks like another country. Respect Nominatim 1 req/s (caller debounce).
class OsmNominatimClient {
  OsmNominatimClient({http.Client? client, this.baseUri, this.photonBaseUri})
    : _client = client ?? http.Client();

  static const userAgent =
      'SwiftDocumentGenerator/1.0 (warehouse labels)';

  static final _otherCountry = RegExp(
    r'\b(united states|u\.s\.a\.?|u\.s\.|usa|america|mexico|'
    r'united kingdom|england|uk|australia|germany|france)\b',
    caseSensitive: false,
  );

  static final _usZip = RegExp(r'\b\d{5}(?:-\d{4})?\b');
  static final _caPostal = RegExp(
    r'\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z]\s?\d[ABCEGHJ-NPRSTV-Z]\d\b',
    caseSensitive: false,
  );

  /// First token is a civic number when followed by more street text.
  static final _leadingCivic = RegExp(
    r'^(\d+[A-Za-z]?)\s+(.+)$',
  );

  final http.Client _client;
  final Uri? baseUri;
  final Uri? photonBaseUri;

  /// One Nominatim request (structured civic when possible). No Photon.
  /// Caller must respect 1 req/s.
  Future<List<NominatimHit>> searchAddress(
    String address, {
    String shipTo = '',
  }) async {
    final q = address.trim();
    if (q.length < 3) return const [];
    final parsed = parseCivicStreetQuery(q);
    try {
      if (parsed.hasStructuredStreet) {
        final structured = await _nominatimSearch(structuredParams(parsed, q));
        final houseHits = rankHits(structured, parsed)
            .where((h) => hitMatchesHouseNumber(h, parsed.houseNumber))
            .toList();
        if (houseHits.isNotEmpty) {
          return mergeAndRankHits(houseHits, parsed);
        }
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
      var freeText = await _nominatimSearch(freeTextParams(q));
      if (freeText.isEmpty && shipTo.trim().length >= 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        freeText = await _nominatimSearch(
          freeTextParams('$shipTo, $q'),
        );
      }
      return mergeAndRankHits(freeText, parsed);
    } catch (_) {
      return const [];
    }
  }

  Future<List<NominatimHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final parsed = parseCivicStreetQuery(q);
    try {
      final structured = parsed.hasStructuredStreet
          ? await _nominatimSearch(structuredParams(parsed, q))
          : const <NominatimHit>[];
      final structuredHouseHits = rankHits(structured, parsed)
          .where((h) => hitMatchesHouseNumber(h, parsed.houseNumber))
          .toList();

      var freeText = const <NominatimHit>[];
      if (structuredHouseHits.isEmpty) {
        freeText = await _nominatimSearch(freeTextParams(q));
      }

      final photon = await _photonSearch(q);
      return mergeAndRankHits(
        [...structured, ...freeText, ...photon],
        parsed,
      );
    } catch (_) {
      return const [];
    }
  }

  Map<String, String> structuredParams(CivicStreetQuery parsed, String q) {
    final params = <String, String>{
      'street': parsed.structuredStreet,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      'accept-language': 'en',
    };
    final city = parsed.localityHint.trim();
    if (city.isNotEmpty) {
      params['city'] = city.split(',').first.trim();
    }
    if (biasCanada(q)) {
      params['countrycodes'] = 'ca';
    }
    return params;
  }

  Map<String, String> freeTextParams(String q) {
    final params = <String, String>{
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      'accept-language': 'en',
    };
    if (biasCanada(q)) {
      params['countrycodes'] = 'ca';
    }
    return params;
  }

  Future<List<NominatimHit>> _nominatimSearch(Map<String, String> params) async {
    final uri = (baseUri ?? Uri.https('nominatim.openstreetmap.org', '/search'))
        .replace(queryParameters: params);
    final res = await _client
        .get(
          uri,
          headers: {
            'User-Agent': userAgent,
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    return parseSearchBody(res.body);
  }

  Future<List<NominatimHit>> _photonSearch(String q) async {
    try {
      final params = <String, String>{
        'q': q,
        'limit': '8',
        'lang': 'en',
      };
      final uri = (photonBaseUri ?? Uri.https('photon.komoot.io', '/api/'))
          .replace(queryParameters: params);
      final res = await _client
          .get(
            uri,
            headers: {
              'User-Agent': userAgent,
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      return parsePhotonBody(res.body);
    } catch (_) {
      return const [];
    }
  }

  static CivicStreetQuery parseCivicStreetQuery(String query) {
    final raw = query.trim();
    if (raw.isEmpty) return CivicStreetQuery(raw: raw);

    final comma = raw.indexOf(',');
    final head = (comma < 0 ? raw : raw.substring(0, comma)).trim();
    final locality = comma < 0 ? '' : raw.substring(comma + 1).trim();

    final m = _leadingCivic.firstMatch(head);
    if (m == null) {
      return CivicStreetQuery(
        raw: raw,
        streetName: head,
        localityHint: locality,
      );
    }
    return CivicStreetQuery(
      raw: raw,
      houseNumber: m.group(1)!.trim(),
      streetName: m.group(2)!.trim(),
      localityHint: locality,
    );
  }

  static bool biasCanada(String query) {
    final q = query.trim();
    if (_otherCountry.hasMatch(q)) return false;
    if (_usZip.hasMatch(q) && !_caPostal.hasMatch(q)) return false;
    return true;
  }

  static List<NominatimHit> parseSearchBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) return const [];
      return parseSearchList(decoded);
    } catch (_) {
      return const [];
    }
  }

  static List<NominatimHit> parsePhotonBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final features = decoded['features'];
      if (features is! List) return const [];
      final out = <NominatimHit>[];
      final seen = <String>{};
      for (final f in features) {
        if (f is! Map) continue;
        final props = f['properties'];
        if (props is! Map) continue;
        final hit = fromPhotonProperties(Map<String, dynamic>.from(props));
        if (hit == null) continue;
        final k = hit.displayAddress.trim().toLowerCase();
        if (k.isEmpty || !seen.add(k)) continue;
        out.add(hit);
        if (out.length >= 8) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static NominatimHit? fromPhotonProperties(Map<String, dynamic> p) {
    final house = _str(p['housenumber']);
    var road = _str(p['street']);
    if (road.isEmpty) {
      final name = _str(p['name']);
      if (name.isNotEmpty && name.toLowerCase() != house.toLowerCase()) {
        road = name;
      }
    }
    final street = formatStreetLine(houseNumber: house, road: road);
    final city = _first(p, const ['city', 'town', 'village', 'district']);
    final prov = _photonProvince(p);
    final postal = _str(p['postcode']);
    final country = _str(p['country']);
    final countryCode = _str(p['countrycode']).toLowerCase();
    final locality = formatLocalityLine(
      city: city,
      province: prov,
      postal: postal,
      country: country,
      countryCode: countryCode,
    );
    final display = formatDisplayAddress(
      streetLine: street,
      localityLine: locality,
      fallback: _str(p['name']),
    );
    if (display.isEmpty) return null;
    return NominatimHit(
      streetLine: street,
      localityLine: locality,
      displayAddress: display,
      houseNumber: house,
      city: city,
      province: prov,
      postal: postal,
    );
  }

  static String _photonProvince(Map<String, dynamic> p) {
    final state = _str(p['state']);
    const names = {
      'alberta': 'AB',
      'british columbia': 'BC',
      'manitoba': 'MB',
      'new brunswick': 'NB',
      'newfoundland and labrador': 'NL',
      'nova scotia': 'NS',
      'northwest territories': 'NT',
      'nunavut': 'NU',
      'ontario': 'ON',
      'prince edward island': 'PE',
      'quebec': 'QC',
      'saskatchewan': 'SK',
      'yukon': 'YT',
    };
    return names[state.toLowerCase()] ?? state;
  }

  static List<NominatimHit> parseSearchList(List<dynamic> items) {
    final out = <NominatimHit>[];
    final seen = <String>{};
    for (final item in items) {
      if (item is! Map) continue;
      final hit = fromResult(Map<String, dynamic>.from(item));
      if (hit == null) continue;
      final k = hit.displayAddress.trim().toLowerCase();
      if (k.isEmpty || !seen.add(k)) continue;
      out.add(hit);
      if (out.length >= 8) break;
    }
    return out;
  }

  static NominatimHit? fromResult(Map<String, dynamic> item) {
    final addr = item['address'];
    final address = addr is Map
        ? Map<String, dynamic>.from(addr)
        : <String, dynamic>{};

    final house = _str(address['house_number']);
    final road = _first(address, const [
      'road',
      'street',
      'pedestrian',
      'residential',
    ]);
    final street = formatStreetLine(houseNumber: house, road: road);

    final city = _first(address, const [
      'city',
      'town',
      'village',
      'hamlet',
      'municipality',
      'city_district',
      'suburb',
    ]);
    final prov = _province(address);
    final postal = _str(address['postcode']);
    final country = _str(address['country']);
    final countryCode = _str(address['country_code']).toLowerCase();
    final locality = formatLocalityLine(
      city: city,
      province: prov,
      postal: postal,
      country: country,
      countryCode: countryCode,
    );

    final display = formatDisplayAddress(
      streetLine: street,
      localityLine: locality,
      fallback: _str(item['display_name']),
    );
    if (display.isEmpty) return null;

    return NominatimHit(
      streetLine: street,
      localityLine: locality,
      displayAddress: display,
      houseNumber: house,
      city: city,
      province: prov,
      postal: postal,
    );
  }

  static String formatStreetLine({
    required String houseNumber,
    required String road,
  }) {
    return [houseNumber, road].where((e) => e.isNotEmpty).join(' ');
  }

  static String formatLocalityLine({
    required String city,
    required String province,
    required String postal,
    required String country,
    required String countryCode,
  }) {
    final localityParts = <String>[
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
      if (postal.isNotEmpty) postal,
    ];
    if (countryCode.isNotEmpty && countryCode != 'ca' && country.isNotEmpty) {
      localityParts.add(country);
    }
    return localityParts.join(', ');
  }

  static String formatDisplayAddress({
    required String streetLine,
    required String localityLine,
    String fallback = '',
  }) {
    final display = [
      if (streetLine.isNotEmpty) streetLine,
      if (localityLine.isNotEmpty) localityLine,
    ].join(', ');
    if (display.trim().isNotEmpty) return display.trim();
    return fallback.trim();
  }

  static bool hitMatchesHouseNumber(NominatimHit hit, String houseNumber) {
    final want = houseNumber.trim().toLowerCase();
    if (want.isEmpty) return false;
    if (hit.houseNumber.trim().toLowerCase() == want) return true;
    final blob = '${hit.streetLine} ${hit.displayAddress}'.toLowerCase();
    return RegExp('\\b${RegExp.escape(want)}\\b').hasMatch(blob);
  }

  static int houseMatchRank(NominatimHit hit, CivicStreetQuery parsed) {
    if (parsed.houseNumber.isEmpty) return 1;
    if (hitMatchesHouseNumber(hit, parsed.houseNumber)) return 0;
    if (hit.houseNumber.isEmpty) return 2;
    return 1;
  }

  static List<NominatimHit> rankHits(
    List<NominatimHit> hits,
    CivicStreetQuery parsed,
  ) {
    final copy = [...hits];
    copy.sort((a, b) {
      final ra = houseMatchRank(a, parsed);
      final rb = houseMatchRank(b, parsed);
      if (ra != rb) return ra.compareTo(rb);
      return a.displayAddress.compareTo(b.displayAddress);
    });
    return copy;
  }

  static List<NominatimHit> mergeAndRankHits(
    List<NominatimHit> hits,
    CivicStreetQuery parsed,
  ) {
    final seen = <String>{};
    final unique = <NominatimHit>[];
    for (final h in hits) {
      final k = h.displayAddress.trim().toLowerCase();
      if (k.isEmpty || !seen.add(k)) continue;
      unique.add(h);
    }
    final ranked = rankHits(unique, parsed);
    final hasHouseMatch = parsed.houseNumber.isNotEmpty &&
        ranked.any((h) => hitMatchesHouseNumber(h, parsed.houseNumber));
    final filtered = hasHouseMatch
        ? ranked.where((h) {
            if (hitMatchesHouseNumber(h, parsed.houseNumber)) return true;
            // Keep other house-level hits, but not bare streets named like "130 Avenue".
            return h.houseNumber.isNotEmpty;
          }).toList()
        : ranked;
    return filtered.take(8).toList();
  }

  static String _province(Map<String, dynamic> address) {
    final iso = _str(address['ISO3166-2-lvl4']);
    if (iso.contains('-')) {
      final code = iso.split('-').last.trim().toUpperCase();
      if (code.length == 2) return code;
    }
    return _first(address, const ['state', 'province', 'region']);
  }

  static String _first(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = _str(map[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String _str(Object? v) {
    if (v == null) return '';
    return '$v'.trim();
  }
}
