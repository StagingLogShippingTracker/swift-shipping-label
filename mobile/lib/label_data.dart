import 'dart:typed_data';

/// Which print template the generator is targeting.
enum LabelKind { shipping, receiving, bol }

/// Max customer logos per label (primary + care-of / C/O).
const int maxCustomerLogos = 2;

/// Bill of Lading field keys (flat print PDF).
class BolFields {
  static const documentNumber = 'document_number';
  static const documentDate = 'document_date';
  static const bookingRef = 'booking_ref';
  static const probillNumber = 'probill_number';
  static const consigneeName = 'consignee_name';
  static const consigneeAddress = 'consignee_address';
  static const consigneeContactName = 'consignee_contact_name';
  static const consigneeContactNumber = 'consignee_contact_number';
  static const thirdPartyBilling = 'third_party_billing';
  static const freightCharges = 'freight_charges';

  /// Stored values for [freightCharges] (PDF radio group).
  static const freightPrepaid = 'prepaid';
  static const freightCollect = 'collect';
  static const freightThirdParty = 'third_party';

  static const freightChargeOptions = <(String value, String label)>[
    (freightPrepaid, 'Prepaid'),
    (freightCollect, 'Collect'),
    (freightThirdParty, 'Third Party'),
  ];
  static const packingList = 'packing_list';
  static const orderNum = 'order_num';
  static const totalPieces = 'total_pieces';
  static const totalWeight = 'total_weight';
  static const shipperCertName = 'shipper_cert_name';
  static const shipperCertSign = 'shipper_cert_sign';
  static const shipperCertDate = 'shipper_cert_date';
  static const driverCompany = 'driver_company';
  static const driverPrint = 'driver_print';
  static const driverSign = 'driver_sign';
  static const driverDate = 'driver_date';
  static const vehicleId = 'vehicle_id';
  /// Kept for older fills; no longer drawn on the BOL.
  static const arrivalTime = 'arrival_time';
  static const departureTime = 'departure_time';
  static const consigneeSign = 'consignee_sign';
  static const consigneePrint = 'consignee_print';
  static const consigneeDate = 'consignee_date';

  static String lineKey(int row, String suffix) => 'line_${row}_$suffix';

  /// BOL-only keys (PO / Project reuse [LabelFields]).
  static final formDefs = <(String key, String label, bool multiline)>[
    (documentNumber, 'Document Number', false),
    (documentDate, 'Date', false),
    (bookingRef, 'Booking Ref', false),
    (probillNumber, 'Probill #', false),
    (consigneeName, 'Ship To Name', false),
    (consigneeAddress, 'Delivery Address', true),
    (consigneeContactName, 'Contact Name', false),
    (consigneeContactNumber, 'Contact Number', false),
    (thirdPartyBilling, '3rd Party Billing', true),
    (packingList, 'Packing List #', false),
    (orderNum, 'Order #', false),
    (shipperCertName, 'Shipper Cert Name', false),
    (shipperCertDate, 'Shipper Cert Date', false),
    (driverCompany, 'Carrier Company', false),
    (driverPrint, 'Driver Name', false),
    (driverDate, 'Driver Date', false),
    (departureTime, 'Departure', false),
    (vehicleId, 'Vehicle ID', false),
    (consigneePrint, 'Consignee Print Name', false),
    (consigneeDate, 'Consignee Date', false),
    for (var i = 1; i <= 7; i++) ...[
      (lineKey(i, 'pieces'), 'Line $i Qty', false),
      (lineKey(i, 'item_type'), 'Line $i Item Type', false),
      (lineKey(i, 'dimensions'), 'Line $i Dimensions', false),
      (lineKey(i, 'description'), 'Line $i Description', false),
      (lineKey(i, 'weight'), 'Line $i Weight', false),
    ],
  ];
}

/// Field keys shared by the form UI and PDF generators.
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
  static const pm = 'pm';
  static const dateReceived = 'date_received';
  static const receivedBy = 'received_by';

  static final formDefs = <(String key, String label, bool multiline)>[
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
    (pm, 'PM', false),
    (dateReceived, 'Date Received', false),
    (receivedBy, 'Received By', false),
    ...BolFields.formDefs,
  ];

  /// Legacy shipping preset keys (prefer [presetKeysFor]).
  static const presetKeys = <String>[
    customer,
    shipTo,
    location,
    attn,
    carrier,
    swiftContact,
    specialInstructions,
    pm,
  ];
}

/// Date fields that use a calendar picker in the form UI.
const appDateFieldKeys = <String>{
  LabelFields.dateReceived,
  BolFields.documentDate,
  BolFields.shipperCertDate,
  BolFields.driverDate,
  BolFields.consigneeDate,
};

/// Display/parse dates as "Aug 1, 2026" (matches BOL today stamp).
class AppDates {
  AppDates._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String format(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';

  static DateTime? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct;
    final m = RegExp(
      r'^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})$',
    ).firstMatch(s);
    if (m == null) return null;
    final mon = m.group(1)!.toLowerCase();
    final month = _months.indexWhere((name) => name.toLowerCase() == mon) + 1;
    if (month < 1) return null;
    final day = int.tryParse(m.group(2)!);
    final year = int.tryParse(m.group(3)!);
    if (day == null || year == null) return null;
    return DateTime(year, month, day);
  }
}

/// Form field keys persisted on a customer preset for [kind].
List<String> presetKeysFor(LabelKind kind) {
  switch (kind) {
    case LabelKind.shipping:
      return const [
        LabelFields.customer,
        LabelFields.shipTo,
        LabelFields.location,
        LabelFields.attn,
        LabelFields.carrier,
        LabelFields.swiftContact,
        LabelFields.specialInstructions,
      ];
    case LabelKind.receiving:
      return const [
        LabelFields.customer,
        LabelFields.project,
        LabelFields.poNum,
        LabelFields.specialInstructions,
        LabelFields.pm,
      ];
    case LabelKind.bol:
      return const [
        LabelFields.customer,
        LabelFields.specialInstructions,
        LabelFields.poNum,
        LabelFields.project,
        BolFields.consigneeName,
        BolFields.consigneeAddress,
        BolFields.consigneeContactName,
        BolFields.consigneeContactNumber,
        BolFields.freightCharges,
        BolFields.packingList,
        BolFields.orderNum,
        BolFields.driverCompany,
        BolFields.shipperCertName,
      ];
  }
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

  static final receivingSample = ShippingLabelData({
    LabelFields.customer: 'CONOCOPHILLIPS CANADA (BRC) PARTNERSHIP',
    LabelFields.project: 'Gateway Pipelines & CBR Pad 107 Lateral FEL3',
    LabelFields.poNum: '278-07-31 - 0009',
    LabelFields.salesOrder: '1380380',
    LabelFields.pm: 'CHRIS ACORN',
    LabelFields.dateReceived: 'May 1st, 2026',
    LabelFields.receivedBy: 'Keith Blackman',
    LabelFields.specialInstructions:
        'Hold on dock until ship confirm. Do not break skid.',
  });

  static final bolSample = ShippingLabelData({
    LabelFields.customer: 'PACIFIC CANBRIAM',
    LabelFields.specialInstructions: 'Call before delivery. Staging bay 3.',
    LabelFields.poNum: 'PCE-112124-03690',
    LabelFields.project: 'B35 PIPE AND FITTINGS',
    LabelFields.salesOrder: 'SO-88421',
    BolFields.documentNumber: 'SW-0024',
    BolFields.documentDate: 'Aug 1, 2026',
    BolFields.bookingRef: 'BK-4412',
    BolFields.consigneeName: 'STRAIT PROJECTS',
    BolFields.consigneeAddress: '12341 271 RD, FORT ST. JOHN, BC',
    BolFields.consigneeContactName: 'RICK SHUMAN',
    BolFields.consigneeContactNumber: '250-555-0199',
    BolFields.freightCharges: 'prepaid',
    BolFields.packingList: '1224618',
    BolFields.orderNum: 'SO-88421',
    BolFields.lineKey(1, 'pieces'): '2',
    BolFields.lineKey(1, 'item_type'): 'Pallets',
    BolFields.lineKey(1, 'dimensions'): '48x40x48',
    BolFields.lineKey(1, 'description'): 'Pipe fittings - north pad staging',
    BolFields.lineKey(1, 'weight'): '1800',
    BolFields.lineKey(2, 'pieces'): '1',
    BolFields.lineKey(2, 'item_type'): 'Boxes',
    BolFields.lineKey(2, 'description'): 'Gasket kit',
    BolFields.lineKey(2, 'weight'): '40',
    BolFields.shipperCertName: 'J. SMITH',
    BolFields.shipperCertDate: 'Aug 1, 2026',
  });
}

class CustomerPreset {
  CustomerPreset({
    required this.name,
    required this.fields,
    this.kind = LabelKind.shipping,
    this.logoFileNames = const [],
  });

  final String name;
  final Map<String, String> fields;
  final LabelKind kind;
  /// Up to [maxCustomerLogos] filenames under app logo storage.
  final List<String> logoFileNames;

  /// First logo (legacy helpers / single-logo callers).
  String get logoFileName =>
      logoFileNames.isEmpty ? '' : logoFileNames.first;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        ...fields,
        'logos': logoFileNames,
        // Keep legacy key for older app versions
        if (logoFileNames.isNotEmpty) 'logo': logoFileNames.first,
      };

  factory CustomerPreset.fromJson(
    String name,
    Map<String, dynamic> json, {
    LabelKind defaultKind = LabelKind.shipping,
  }) {
    var kind = defaultKind;
    final rawKind = json['kind'];
    if (rawKind is String) {
      kind = LabelKind.values.firstWhere(
        (k) => k.name == rawKind,
        orElse: () => defaultKind,
      );
    }
    final fields = <String, String>{};
    for (final key in presetKeysFor(kind)) {
      final v = json[key];
      if (v != null) fields[key] = '$v';
    }
    final logos = <String>[];
    final rawList = json['logos'];
    if (rawList is List) {
      for (final item in rawList) {
        final s = '$item'.trim();
        if (s.isNotEmpty) logos.add(s);
      }
    }
    if (logos.isEmpty) {
      final legacy = '${json['logo'] ?? ''}'.trim();
      if (legacy.isNotEmpty) logos.add(legacy);
    }
    return CustomerPreset(
      name: name,
      fields: fields,
      kind: kind,
      logoFileNames: logos.take(maxCustomerLogos).toList(),
    );
  }
}

/// Counts entered before generating a multi-page shipping PDF.
class PieceCountPlan {
  const PieceCountPlan({this.palletCrates = 0, this.boxes = 0});

  final int palletCrates;
  final int boxes;

  int get totalPages => palletCrates + boxes;

  bool get isEmpty => totalPages <= 0;
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
