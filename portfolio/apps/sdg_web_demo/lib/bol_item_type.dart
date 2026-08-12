/// BOL line item type dropdown values (stored singular) and PDF pluralization.
class BolItemTypes {
  BolItemTypes._();

  static const options = [
    'Pallet',
    'Crate',
    'Box',
    'Pipe',
    'Bundle',
    'Other',
  ];

  /// Product-total row labels on the BOL PDF (always plural except Other).
  static const productTotalLabels = [
    'Pallets',
    'Crates',
    'Boxes',
    'Pipes',
    'Bundles',
    'Other',
  ];

  static String pluralize(String singular) {
    switch (singular) {
      case 'Pallet':
        return 'Pallets';
      case 'Crate':
        return 'Crates';
      case 'Box':
        return 'Boxes';
      case 'Pipe':
        return 'Pipes';
      case 'Bundle':
        return 'Bundles';
      default:
        return singular;
    }
  }

  /// Normalize legacy plural or mixed-case values to a dropdown option.
  static String normalizeStored(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    for (final opt in options) {
      if (lower == opt.toLowerCase() || lower == pluralize(opt).toLowerCase()) {
        return opt;
      }
    }
    return s;
  }

  /// Text drawn on the BOL line row — plural when qty > 1.
  static String displayForm(String stored, num qty) {
    final singular = normalizeStored(stored);
    if (singular.isEmpty) return '';
    if (qty <= 1) return singular;
    return pluralize(singular);
  }

  /// Maps a stored value to the product-total category label.
  static String totalCategory(String stored) {
    final singular = normalizeStored(stored);
    if (singular.isEmpty) return '';
    return pluralize(singular);
  }
}
