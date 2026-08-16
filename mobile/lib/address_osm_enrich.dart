import 'address_match.dart';
import 'osm_nominatim_client.dart';

/// Fill missing civic / locality fields from OSM without changing the site.
class AddressOsmEnrich {
  AddressOsmEnrich._();

  static final _caPostal = RegExp(
    r'\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z]\s?\d[ABCEGHJ-NPRSTV-Z]\d\b',
    caseSensitive: false,
  );
  static final _usZip = RegExp(r'\b\d{5}(?:-\d{4})?\b');
  static const _provCodes = {
    'ab', 'bc', 'sk', 'mb', 'on', 'qc', 'nb', 'ns', 'pe', 'nl', 'nt', 'nu', 'yt',
  };
  static const _provNames = {
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

  /// Apply the first good OSM hit, or return [current] unchanged.
  static String fillFromHits(String current, List<NominatimHit> hits) {
    final hit = pickGoodHit(current, hits);
    if (hit == null) return current.trim();
    return fillFromHit(current, hit);
  }

  static NominatimHit? pickGoodHit(String current, List<NominatimHit> hits) {
    final trimmed = current.trim();
    if (trimmed.isEmpty || hits.isEmpty) return null;
    final parsed = OsmNominatimClient.parseCivicStreetQuery(trimmed);
    final ranked = OsmNominatimClient.mergeAndRankHits(hits, parsed);
    for (final h in ranked) {
      if (isSameSite(trimmed, h, parsed)) return h;
    }
    return null;
  }

  /// Same civic site: matching house (when typed) and street core.
  /// Rejects a bare street that shares a name with the typed avenue.
  static bool isSameSite(
    String current,
    NominatimHit hit, [
    CivicStreetQuery? parsed,
  ]) {
    final q = parsed ?? OsmNominatimClient.parseCivicStreetQuery(current);
    final currentKey = AddressMatch.addressKey(current);
    if (currentKey.isEmpty) return false;
    final hitKey = AddressMatch.addressKey(
      hit.streetLine.isNotEmpty ? hit.streetLine : hit.displayAddress,
    );
    if (hitKey.isEmpty) return false;

    if (q.houseNumber.isNotEmpty) {
      if (!OsmNominatimClient.hitMatchesHouseNumber(hit, q.houseNumber)) {
        return false;
      }
      if (hit.houseNumber.isEmpty &&
          !RegExp('\\b${RegExp.escape(q.houseNumber)}\\b', caseSensitive: false)
              .hasMatch(hit.streetLine)) {
        return false;
      }
      return currentKey == hitKey ||
          _streetTokensCompatible(currentKey, hitKey);
    }

    // No civic number typed: never adopt a house from a random same-named street.
    if (hit.houseNumber.isNotEmpty) return false;
    return _streetTokensCompatible(currentKey, hitKey);
  }

  static bool _streetTokensCompatible(String a, String b) {
    if (a == b) return true;
    final at = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final bt = b.split(' ').where((t) => t.isNotEmpty).toSet();
    if (at.isEmpty || bt.isEmpty) return false;
    final smaller = at.length <= bt.length ? at : bt;
    final larger = at.length <= bt.length ? bt : at;
    return smaller.every(larger.contains);
  }

  static String fillFromHit(String current, NominatimHit hit) {
    final parts = parseParts(current);
    final keepStreet = parts.streetLine.isNotEmpty
        ? parts.streetLine
        : hit.streetLine;
    // Never invent a house number when the saved row had none.
    if (parts.houseNumber.isEmpty &&
        OsmNominatimClient.parseCivicStreetQuery(current).houseNumber.isEmpty) {
      if (hit.houseNumber.isNotEmpty &&
          !keepStreet.toLowerCase().startsWith(hit.houseNumber.toLowerCase())) {
        return current.trim();
      }
    }
    final city = parts.city.isNotEmpty ? parts.city : hit.city;
    final province =
        parts.province.isNotEmpty ? parts.province : hit.province;
    final postal = parts.postal.isNotEmpty ? parts.postal : hit.postal;
    final filled = formatAddress(
      streetLine: keepStreet,
      city: city,
      province: province,
      postal: postal,
    );
    if (filled.isEmpty) return current.trim();
    return filled;
  }

  static String formatAddress({
    required String streetLine,
    required String city,
    required String province,
    required String postal,
  }) {
    final loc = [
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
      if (postal.isNotEmpty) postal,
    ].join(', ');
    return [
      if (streetLine.isNotEmpty) streetLine,
      if (loc.isNotEmpty) loc,
    ].join(', ');
  }

  static AddressParts parseParts(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const AddressParts();
    var postal = '';
    var rest = trimmed;
    final ca = _caPostal.firstMatch(rest);
    if (ca != null) {
      postal = ca.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      if (postal.length == 6) {
        postal = '${postal.substring(0, 3)} ${postal.substring(3)}';
      }
      rest = rest.replaceFirst(ca.group(0)!, ' ');
    } else {
      final us = _usZip.firstMatch(rest);
      if (us != null) {
        postal = us.group(0)!;
        rest = rest.replaceFirst(us.group(0)!, ' ');
      }
    }
    final bits = rest
        .split(RegExp(r'[,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    var streetLine = bits.isNotEmpty ? bits.first : trimmed;
    var city = '';
    var province = '';
    for (var i = 1; i < bits.length; i++) {
      final token = bits[i].trim();
      if (token.isEmpty) continue;
      final asProv = _asProvince(token);
      if (asProv != null && province.isEmpty) {
        province = asProv;
        continue;
      }
      final words = token.split(RegExp(r'\s+'));
      if (words.length >= 2) {
        final lastProv = _asProvince(words.last);
        if (lastProv != null) {
          if (city.isEmpty) {
            city = words.sublist(0, words.length - 1).join(' ');
          }
          if (province.isEmpty) province = lastProv;
          continue;
        }
      }
      if (city.isEmpty) city = token;
    }
    final civic = OsmNominatimClient.parseCivicStreetQuery(streetLine);
    return AddressParts(
      streetLine: streetLine,
      houseNumber: civic.houseNumber,
      streetName: civic.streetName,
      city: city,
      province: province,
      postal: postal,
    );
  }

  static String? _asProvince(String raw) {
    final t = raw.trim().toLowerCase();
    if (_provCodes.contains(t)) return t.toUpperCase();
    return _provNames[t];
  }

  static bool looksIncomplete(String address) {
    final p = parseParts(address);
    return p.houseNumber.isEmpty ||
        p.streetName.isEmpty ||
        p.city.isEmpty ||
        p.province.isEmpty ||
        p.postal.isEmpty;
  }
}

class AddressParts {
  const AddressParts({
    this.streetLine = '',
    this.houseNumber = '',
    this.streetName = '',
    this.city = '',
    this.province = '',
    this.postal = '',
  });

  final String streetLine;
  final String houseNumber;
  final String streetName;
  final String city;
  final String province;
  final String postal;
}
