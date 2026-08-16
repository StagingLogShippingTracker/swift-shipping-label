/// Canonical fingerprints so the Delivery Address book treats the same place
/// as one row despite case, hyphens, ordinals, street-type abbreviations,
/// extra city/province, and postal codes.
class AddressMatch {
  AddressMatch._();

  static final _caPostal = RegExp(
    r'\b[a-z]\d[a-z]\s*\d[a-z]\d\b',
    caseSensitive: false,
  );
  static final _usZip = RegExp(r'\b\d{5}(?:-\d{4})?\b');
  static const _provinces = {
    'ab', 'bc', 'sk', 'mb', 'on', 'qc', 'nb', 'ns', 'pe', 'nl', 'nt', 'nu', 'yt',
    'alberta', 'canada', 'ca', 'usa', 'us',
  };
  static const _streetTypes = {
    'st', 'ave', 'rd', 'blvd', 'dr', 'ln', 'ct', 'cir', 'pl', 'hwy', 'cres',
    'trl', 'ter', 'pkwy',
  };
  static const _quadrants = {'n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'};
  static const _noiseName = {
    'ltd', 'inc', 'corp', 'llc', 'llp', 'lp', 'co', 'limited', 'incorporated',
  };

  /// Fingerprint of a street address (civic + street + type + quadrant).
  /// City, province, and postal code are ignored.
  static String addressKey(String address) {
    final tokens = _tokens(_expandStreetTypes(_stripOrdinals(_prep(address))));
    final core = _streetCore(tokens);
    if (core.isEmpty) return '';
    return core.join(' ');
  }

  /// Fingerprint of a ship-to / consignee name.
  static String shipToKey(String name) {
    final tokens = _tokens(_prep(name))
        .map(_stem)
        .where((t) => t.isNotEmpty && !_noiseName.contains(t))
        .toList();
    if (tokens.isEmpty) return '';
    return tokens.join(' ');
  }

  static bool samePlace({
    required String shipToA,
    required String addressA,
    required String shipToB,
    required String addressB,
  }) {
    if (!_sameShipTo(shipToA, shipToB)) return false;
    final aa = addressKey(addressA);
    final ab = addressKey(addressB);
    return aa.isNotEmpty && aa == ab;
  }

  static bool _sameShipTo(String a, String b) {
    final sa = shipToKey(a);
    final sb = shipToKey(b);
    return sa.isNotEmpty && sa == sb;
  }

  static String _prep(String raw) {
    var s = raw.toLowerCase().trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[\u2010-\u2015\u2212_]'), '-');
    s = s.replaceAll('&', ' and ');
    s = s.replaceAll('#', ' ');
    s = s.replaceAll(_caPostal, ' ');
    s = s.replaceAll(_usZip, ' ');
    s = s.replaceAll(RegExp(r'[/\\,.;:()*]+'), ' ');
    s = s.replaceAll('-', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _stripOrdinals(String s) {
    return s.replaceAllMapped(
      RegExp(r'\b(\d+)(?:st|nd|rd|th)\b'),
      (m) => m.group(1)!,
    );
  }

  static String _expandStreetTypes(String s) {
    const suffixes = <String, String>{
      'street': 'st',
      'streets': 'st',
      'str': 'st',
      'avenue': 'ave',
      'avenues': 'ave',
      'av': 'ave',
      'road': 'rd',
      'roads': 'rd',
      'boulevard': 'blvd',
      'drive': 'dr',
      'drives': 'dr',
      'lane': 'ln',
      'court': 'ct',
      'circle': 'cir',
      'place': 'pl',
      'highway': 'hwy',
      'crescent': 'cres',
      'trail': 'trl',
      'terrace': 'ter',
      'parkway': 'pkwy',
      'suite': 'ste',
      'apartment': 'apt',
      'north': 'n',
      'south': 's',
      'east': 'e',
      'west': 'w',
      'northeast': 'ne',
      'northwest': 'nw',
      'southeast': 'se',
      'southwest': 'sw',
    };
    final parts = s.split(' ');
    return [
      for (final p in parts) suffixes[p] ?? p,
    ].join(' ');
  }

  static List<String> _tokens(String s) {
    return [
      for (final t in s.split(' '))
        if (t.isNotEmpty &&
            t != 'and' &&
            t != 'of' &&
            t != 'the' &&
            !_provinces.contains(t))
          t,
    ];
  }

  /// Civic number + street tokens through street type and optional quadrant.
  static List<String> _streetCore(List<String> tokens) {
    if (tokens.isEmpty) return const [];
    final civicAt = tokens.indexWhere((t) => RegExp(r'^\d+$').hasMatch(t));
    if (civicAt < 0) {
      final copy = [...tokens]..sort();
      return copy;
    }
    final core = <String>[tokens[civicAt]];
    var i = civicAt + 1;
    var sawType = false;
    while (i < tokens.length) {
      final t = tokens[i];
      if (_provinces.contains(t)) {
        i++;
        continue;
      }
      if (sawType) {
        if (_quadrants.contains(t)) {
          core.add(t);
          i++;
          continue;
        }
        break;
      }
      core.add(t);
      if (_streetTypes.contains(t)) sawType = true;
      i++;
    }
    return core;
  }

  static String _stem(String t) {
    if (t.length > 4 && t.endsWith('s') && !t.endsWith('ss')) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }
}
