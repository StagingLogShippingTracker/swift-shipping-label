/// Whether an OA line supplies a valve TAG# or a PART#.
enum BulkIdKind { tag, part }

extension BulkIdKindLabel on BulkIdKind {
  /// Printed field label on the Propak sticker.
  String get fieldLabel => switch (this) {
        BulkIdKind.tag => 'TAG#',
        BulkIdKind.part => 'PART#',
      };

  String get previewColumn => fieldLabel;
}

/// User choice when OA lines are missing TAG# / PART#.
enum BulkMissingIdAction {
  /// Include incomplete lines with a blank identity (editable in Word).
  proceed,

  /// Omit incomplete lines; keep only fully tagged lines.
  skip,

  /// Discard the whole upload.
  cancel,
}

/// One order-ack line that will become one or more Avery stickers.
class BulkLabelLine {
  const BulkLabelLine({
    required this.lineNo,
    required this.cpo,
    required this.tagOrPart,
    required this.idKind,
    required this.quantity,
    this.description = '',
    this.missingIdentity = false,
  });

  final int lineNo;
  final String cpo;
  final String tagOrPart;
  final BulkIdKind idKind;
  final int quantity;
  final String description;

  /// True when Proceed kept a line that had no TAG#/PART# on the OA.
  final bool missingIdentity;

  int get labelCount => quantity < 1 ? 0 : quantity;
}

/// OA line that has CPO (+ qty) but no TAG# / PART# yet.
class BulkIncompleteLine {
  const BulkIncompleteLine({
    required this.lineNo,
    required this.cpo,
    required this.quantity,
    this.description = '',
    this.reason = 'Missing TAG# / PART#',
  });

  final int lineNo;
  final String cpo;
  final int quantity;
  final String description;
  final String reason;

  /// Placeholder sticker rows if the user chooses Proceed.
  BulkLabelLine asProceedLine() => BulkLabelLine(
        lineNo: lineNo,
        cpo: cpo,
        tagOrPart: '',
        idKind: BulkIdKind.tag,
        quantity: quantity,
        description: description,
        missingIdentity: true,
      );
}

/// One physical sticker after quantity expansion.
class BulkLabelInstance {
  const BulkLabelInstance({
    required this.poNumber,
    required this.cpo,
    required this.tagOrPart,
    required this.idKind,
    required this.sourceLineNo,
  });

  final String poNumber;
  final String cpo;
  final String tagOrPart;
  final BulkIdKind idKind;
  final int sourceLineNo;

  String get idFieldLabel => idKind.fieldLabel;

  Map<String, dynamic> toJson() => {
        'po': poNumber,
        'cpo': cpo,
        'id': tagOrPart,
        'idKind': idKind.name,
        'line': sourceLineNo,
      };
}

/// Result of parsing a Swift Order Acknowledgement.
class OrderAckParseResult {
  const OrderAckParseResult({
    required this.poNumber,
    required this.orderNumber,
    required this.lines,
    required this.warnings,
    this.incompleteLines = const [],
    this.sourceFileName = '',
    this.customerName = '',
    this.projectNumber = '',
    this.deliveryShipToName = '',
    this.deliveryShipToAddress = '',
    this.headerShipToName = '',
    this.headerShipToAddress = '',
    this.deliveryCarrier = '',
    this.hasDeliveryShipTo = false,
  });

  final String poNumber;
  final String orderNumber;
  final List<BulkLabelLine> lines;
  final List<String> warnings;

  /// Lines with CPO but no TAG#/PART# — awaiting Proceed / Skip / Cancel.
  final List<BulkIncompleteLine> incompleteLines;
  final String sourceFileName;

  /// Bill To company name (not the Ship To header).
  final String customerName;

  /// Project column (often a P-number). May match [poNumber] when the OA
  /// only prints one value under Project / Location / PO Number.
  final String projectNumber;

  final String deliveryShipToName;
  final String deliveryShipToAddress;
  final String headerShipToName;
  final String headerShipToAddress;

  /// Freight line from Delivery Instructions (e.g. ROSENAU COLLECT).
  final String deliveryCarrier;

  /// True when Delivery Instructions include a usable name and/or street.
  final bool hasDeliveryShipTo;

  bool get hasIncompleteLines => incompleteLines.isNotEmpty;

  int get totalLabels =>
      lines.fold<int>(0, (sum, line) => sum + line.labelCount);

  int get sheetCount {
    final n = totalLabels;
    if (n <= 0) return 0;
    return (n + 9) ~/ 10; // Avery 5163 = 10 / sheet
  }

  OrderAckParseResult copyWith({
    String? poNumber,
    String? orderNumber,
    List<BulkLabelLine>? lines,
    List<String>? warnings,
    List<BulkIncompleteLine>? incompleteLines,
    String? sourceFileName,
    String? customerName,
    String? projectNumber,
    String? deliveryShipToName,
    String? deliveryShipToAddress,
    String? headerShipToName,
    String? headerShipToAddress,
    String? deliveryCarrier,
    bool? hasDeliveryShipTo,
  }) {
    return OrderAckParseResult(
      poNumber: poNumber ?? this.poNumber,
      orderNumber: orderNumber ?? this.orderNumber,
      lines: lines ?? this.lines,
      warnings: warnings ?? this.warnings,
      incompleteLines: incompleteLines ?? this.incompleteLines,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      customerName: customerName ?? this.customerName,
      projectNumber: projectNumber ?? this.projectNumber,
      deliveryShipToName: deliveryShipToName ?? this.deliveryShipToName,
      deliveryShipToAddress:
          deliveryShipToAddress ?? this.deliveryShipToAddress,
      headerShipToName: headerShipToName ?? this.headerShipToName,
      headerShipToAddress: headerShipToAddress ?? this.headerShipToAddress,
      deliveryCarrier: deliveryCarrier ?? this.deliveryCarrier,
      hasDeliveryShipTo: hasDeliveryShipTo ?? this.hasDeliveryShipTo,
    );
  }

  /// Apply the user's dialog choice for incomplete lines.
  OrderAckParseResult applyingMissingIdAction(BulkMissingIdAction action) {
    switch (action) {
      case BulkMissingIdAction.cancel:
        return this;
      case BulkMissingIdAction.skip:
        final notes = [
          for (final inc in incompleteLines)
            'Line CPO #${inc.cpo} is missing TAG# / PART# — skipped. '
                'Please check with the PM.',
        ];
        return copyWith(
          warnings: [...warnings, ...notes],
          incompleteLines: const [],
        );
      case BulkMissingIdAction.proceed:
        final merged = [
          ...lines,
          for (final inc in incompleteLines) inc.asProceedLine(),
        ]..sort((a, b) => a.lineNo.compareTo(b.lineNo));
        final notes = [
          for (final inc in incompleteLines)
            'Line CPO #${inc.cpo} is missing TAG# / PART# — included blank '
                'for editing. Please check with the PM.',
        ];
        return copyWith(
          lines: merged,
          warnings: [...warnings, ...notes],
          incompleteLines: const [],
        );
    }
  }

  List<BulkLabelInstance> expand() {
    final out = <BulkLabelInstance>[];
    for (final line in lines) {
      for (var i = 0; i < line.labelCount; i++) {
        out.add(
          BulkLabelInstance(
            poNumber: poNumber,
            cpo: line.cpo,
            tagOrPart: line.tagOrPart,
            idKind: line.idKind,
            sourceLineNo: line.lineNo,
          ),
        );
      }
    }
    return out;
  }
}
