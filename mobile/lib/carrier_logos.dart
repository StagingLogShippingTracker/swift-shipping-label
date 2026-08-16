import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Built-in courier marks for the Shipping Label carrier value box.
///
/// Matching is case-insensitive and ignores punctuation. Only [LabelFields.carrier]
/// should be passed in — do not scan ship-to / customer names.
class CarrierLogos {
  CarrierLogos._();

  static const murrays = 'murrays';
  static const dunrite = 'dunrite';

  static const assetMurrays = 'assets/images/carrier_murrays.png';
  static const assetDunrite = 'assets/images/carrier_dunrite.png';

  static const Map<String, String> assets = {
    murrays: assetMurrays,
    dunrite: assetDunrite,
  };

  /// Lowercase, strip punctuation, collapse whitespace.
  static String normalize(String raw) {
    final buf = StringBuffer();
    var prevSpace = true;
    for (final rune in raw.toLowerCase().runes) {
      if (rune == 39) continue; // apostrophe: Murray's → murrays
      final isDigit = rune >= 48 && rune <= 57;
      final isAlpha = rune >= 97 && rune <= 122;
      if (isAlpha || isDigit) {
        buf.writeCharCode(rune);
        prevSpace = false;
      } else if (!prevSpace) {
        buf.writeCharCode(32);
        prevSpace = true;
      }
    }
    return buf.toString().trim();
  }

  static String compact(String normalized) =>
      normalized.replaceAll(' ', '');

  /// Returns [murrays], [dunrite], or null.
  static String? matchId(String carrier) {
    final n = normalize(carrier);
    if (n.isEmpty) return null;
    final c = compact(n);
    if (_isMurrays(n, c)) return murrays;
    if (_isDunrite(c)) return dunrite;
    return null;
  }

  static bool _isMurrays(String normalized, String compact) {
    if (compact.contains('murrays')) return true;
    if (normalized == 'murray') return true;
    if (normalized.startsWith('murray ')) return true;
    return false;
  }

  static bool _isDunrite(String compact) {
    return compact.contains('dunrite') || compact.contains('dunright');
  }

  static Future<Map<String, Uint8List>> loadPngs() async {
    final out = <String, Uint8List>{};
    for (final e in assets.entries) {
      try {
        final data = await rootBundle.load(e.value);
        out[e.key] = data.buffer.asUint8List();
      } catch (_) {}
    }
    return out;
  }
}
