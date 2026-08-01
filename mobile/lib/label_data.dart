import 'dart:typed_data';

/// Field keys shared by the form UI and PDF generator.
class LabelFields {
  static const customer = 'customer';
  static const poNum = 'po_num';
  static const project = 'project';
  static const specialInstructions = 'special_instructions';
  static const shipTo = 'ship_to';
  static const location = 'location';
  static const attn = 'attn';
  static const carrier = 'carrier';
  static const packingSlip = 'packing_slip';
  static const salesOrder = 'sales_order';
  static const swiftContact = 'swift_contact';
  static const palletNum = 'pallet_num';
  static const palletOf = 'pallet_of';
  static const boxNum = 'box_num';
  static const boxOf = 'box_of';

  static const formDefs = <(String key, String label, bool multiline)>[
    (customer, 'Customer', false),
    (poNum, 'PO No.', true),
    (project, 'Project', true),
    (specialInstructions, 'Special Instructions', true),
    (shipTo, 'Ship To', false),
    (location, 'Location', true),
    (attn, 'Attn', false),
    (carrier, 'Carrier', false),
    (packingSlip, 'Swift Packing Slip No.', false),
    (salesOrder, 'Swift Sales Order No.', false),
    (swiftContact, 'Swift Contact', false),
    (palletNum, 'Pallet / Crate #', false),
    (palletOf, 'Pallet / Crate of', false),
    (boxNum, 'Box #', false),
    (boxOf, 'Box of', false),
  ];

  /// Fields stored on a customer preset (shipment-specific stay blank).
  static const presetKeys = <String>[
    customer,
    shipTo,
    location,
    attn,
    carrier,
    swiftContact,
    specialInstructions,
  ];
}

class ShippingLabelData {
  ShippingLabelData([Map<String, String>? values])
      : values = {
          for (final def in LabelFields.formDefs) def.$1: '',
          ...?values,
        };

  final Map<String, String> values;

  String get(String key) => (values[key] ?? '').trim();

  void set(String key, String value) => values[key] = value;

  ShippingLabelData copy() => ShippingLabelData(Map.of(values));

  static final sample = ShippingLabelData({
    LabelFields.customer: 'PACIFIC CANBRIAM',
    LabelFields.shipTo: 'STRAIT PROJECTS',
    LabelFields.poNum:
        'PCE-112124-03690 / RELEASE 2 / FORT ST JOHN DELIVERY WINDOW / RUSH / CONFIRM DOCK',
    LabelFields.location: '12341 271 RD, FORT ST. JOHN, BC',
    LabelFields.project:
        'B35 PIPE AND FITTINGS - NORTH PAD STAGING AND HOOKUP MATERIALS FOR WELLSITE PACKAGE',
    LabelFields.carrier: 'WILLYS',
    LabelFields.specialInstructions: 'Call before delivery. Staging bay 3.',
    LabelFields.attn: 'RICK SHUMAN / JEREMY PLATZ',
    LabelFields.palletNum: '1',
    LabelFields.palletOf: '2',
    LabelFields.boxNum: '',
    LabelFields.boxOf: '',
    LabelFields.packingSlip: '1224618',
    LabelFields.salesOrder: 'SO-88421',
    LabelFields.swiftContact: 'J. SMITH',
  });
}

class CustomerPreset {
  CustomerPreset({
    required this.name,
    required this.fields,
    this.logoFileName = '',
  });

  final String name;
  final Map<String, String> fields;
  final String logoFileName;

  Map<String, dynamic> toJson() => {
        ...fields,
        'logo': logoFileName,
      };

  factory CustomerPreset.fromJson(String name, Map<String, dynamic> json) {
    final fields = <String, String>{};
    for (final key in LabelFields.presetKeys) {
      final v = json[key];
      if (v != null) fields[key] = '$v';
    }
    return CustomerPreset(
      name: name,
      fields: fields,
      logoFileName: '${json['logo'] ?? ''}',
    );
  }
}

class LabelFonts {
  LabelFonts({
    required this.oswald,
    required this.oswaldMedium,
    required this.oswaldSemiBold,
    required this.oswaldBold,
    required this.calibri,
    required this.calibriBold,
  });

  final ByteData oswald;
  final ByteData oswaldMedium;
  final ByteData oswaldSemiBold;
  final ByteData oswaldBold;
  final ByteData calibri;
  final ByteData calibriBold;
}
