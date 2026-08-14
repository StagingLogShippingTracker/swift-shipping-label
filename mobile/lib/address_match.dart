/// Canonical fingerprints so the Delivery Address book treats the same place
/// as one row despite case, hyphens, ordinals, and street-type abbreviations.
class AddressMatch {
  AddressMatch._();

  /// Fingerprint of a street address (not the ship-to name).
  static String addressKey(String address) {
    final tokens = _tokens(_expandStreetTypes(_stripOrdinals(_prep(address))));
    if (tokens.isEmpty) return '';
    tokens.sort();
    return tokens.join(' ');
  }

  /// Fingerprint of a ship-to / consignee name.
  static String shipToKey(String name) {
    final tokens = _tokens(_prep(name));
    if (tokens.isEmpty) return '';
    return tokens.join(' ');
  }

  static bool samePlace({
    required String shipToA,
    required String addressA,
    required String shipToB,
    required String addressB,
  }) {
    final sa = shipToKey(shipToA);
    final sb = shipToKey(shipToB);
    if (sa.isEmpty || sb.isEmpty || sa != sb) return false;
    final aa = addressKey(addressA);
    final ab = addressKey(addressB);
    return aa.isNotEmpty && aa == ab;
  }

  static String _prep(String raw) {
    var s = raw.toLowerCase().trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[\u2010-\u2015\u2212_]'), '-');
    s = s.replaceAll('&', ' and ');
    s = s.replaceAll('#', ' ');
    s = s.replaceAll(RegExp(r'[/\\,.;:()]+'), ' ');
    s = s.replaceAll('-', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// `8th` / `1st` / `2nd` / `3rd` → `8` / `1` / `2` / `3`.
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
        if (t.isNotEmpty && t != 'and' && t != 'of' && t != 'the') t,
    ];
  }
}
