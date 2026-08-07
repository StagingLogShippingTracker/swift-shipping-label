import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bol_item_type.dart';
import '../label_data.dart';
import '../pdf_render_options.dart';
import 'shipping_label_pdf.dart';

/// Flat print Bill of Lading — geometry ported from `generate_swift_bol_pdf.py`.
/// Three pages: STORE / DRIVER / CUSTOMER copy (same field values).
class BolLabelPdf {
  BolLabelPdf(this.shipping);

  final ShippingLabelPdf shipping;

  static const swift = PdfColor.fromInt(0xFFCE4E30);
  static const swiftLight = PdfColor.fromInt(0xFFFDF4F1);
  static const black = PdfColor.fromInt(0xFF1A1A1A);
  static const secondary = PdfColor.fromInt(0xFF4A4A4A);
  static const muted = PdfColor.fromInt(0xFF767676);
  static const hint = PdfColor.fromInt(0xFF9A9A9A);
  static const rule = PdfColor.fromInt(0xFFC8C8C8);
  static const tableHead = PdfColor.fromInt(0xFFF0F0F0);
  static const zebra = PdfColor.fromInt(0xFFF7F7F7);
  static const fieldBg = PdfColor.fromInt(0xFFF4F7FA);
  static const white = PdfColor.fromInt(0xFFFFFFFF);

  static final pageFormat = PdfPageFormat.letter;
  static const inch = PdfPageFormat.inch;
  static final margin = 0.4 * inch;
  static final contentW = pageFormat.width - 2 * margin;
  static final footerH = 0.52 * inch;
  static final footerBase = margin + 2;
  static final footerBoxH = footerH - 2;
  static final contentBottom = footerBase + footerBoxH + 8;
  static const gap = 7.0;
  static const pad = 6.0;
  static const bodyInset = 8.0;
  static const inset = 3.0;
  /// Default height for uploaded customer/C/O logos on the BOL header (pt).
  static const customerLogoTargetH = 59.0;
  /// Safety gap between customer logo frame and Probill / Swift.
  static const customerToProbillGap = 12.0;
  /// Legacy alias — same clearance used toward Swift when Probill is absent.
  static const customerToSwiftGap = customerToProbillGap;
  /// Gap between dual customer logo cells.
  static const customerStackGap = 8.0;
  /// Keep uploaded logos inside the header band (above the orange title bar).
  static const logoBandInset = 1.0;
  /// Locked Probill cut-out width (pt).
  static final probillBoxW = 2.35 * inch;
  /// Gap between Swift wordmark and Probill cut-out.
  static const probillCutGap = 14.0;
  static const lineRows = 10;
  static List<String> get itemTypes => BolItemTypes.productTotalLabels;
  static const productTotalLeft = ['Pallets', 'Crates', 'Boxes'];
  static const productTotalRight = ['Pipes', 'Other'];
  /// Still summed for rollups; not drawn in the compact 2-col Product Total grid.
  static const productTotalHidden = ['Bundles'];
  static const copyTypes = ['STORE COPY', 'DRIVER COPY', 'CUSTOMER COPY'];
  static const shipperLines = [
    'Swift Oilfield Supply',
    'Unit 200, 920 - 36 Avenue',
    'Nisku, AB  T9E 1C6',
    '780-423-6979',
  ];

  static const legal =
      'RECEIVED AT THE POINT OF ORIGIN ON THE DATE SPECIFIED, FROM THE CONSIGNOR '
      'MENTIONED HEREIN, THE PROPERTY DESCRIBED IN APPARENT GOOD ORDER EXCEPT AS '
      'NOTED (CONTENTS AND CONDITION OF CONTENTS OF PACKAGES UNKNOWN), MARKED, '
      'CONSIGNED, AND DESTINED AS INDICATED BELOW. NOTICE OF CLAIM: (A) NO CARRIER '
      'IS LIABLE FOR LOSS, DAMAGE, OR DELAY TO ANY GOODS UNDER THIS BILL OF LADING '
      'UNLESS NOTICE THEREOF IS GIVEN IN WRITING TO THE ORIGINATING CARRIER OR THE '
      'DELIVERING CARRIER WITHIN FIVE (5) DAYS AFTER DELIVERY OF THE GOODS, OR IN '
      'THE CASE OF FAILURE TO MAKE DELIVERY, WITHIN NINE (9) MONTHS FROM THE DATE OF '
      'SHIPMENT. (B) THE FINAL STATEMENT OF THE CLAIM MUST BE FILED WITHIN NINE (9) '
      'MONTHS FROM THE DATE OF SHIPMENT, TOGETHER WITH A COPY OF THE PAID FREIGHT '
      'BILL. THE CONTRACT FOR CARRIAGE IS DEEMED TO CONTAIN AND BE SUBJECT TO ALL '
      'CONDITIONS NOT PROHIBITED BY LAW UNDER THE MOTOR TRANSPORT ACT (ALBERTA).';

  static const shipperCert =
      'This is to certify that the above-named materials are properly classified, '
      'described, packaged, marked and labeled, and are in proper condition for '
      'transportation according to the applicable regulations of the Department of '
      'Transportation.';

  Future<Uint8List> build({
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
    Uint8List? shipperSignatureBytes,
    /// Which copy pages to include (subset of [copyTypes]). Defaults to all three.
    List<String>? copies,
    PdfRenderOptions options = PdfRenderOptions.defaults,
  }) async {
    final selected = (copies == null || copies.isEmpty)
        ? List<String>.from(copyTypes)
        : [
            for (final c in copyTypes)
              if (copies.contains(c)) c,
          ];
    if (selected.isEmpty) {
      throw ArgumentError('At least one BOL copy must be selected.');
    }

    final doc = pw.Document(
      title: 'Swift Oilfield Supply — Straight Bill of Lading',
      author: 'Swift Oilfield Supply',
    );
    // BOL layout is fixed to portrait Letter.
    final format = pageFormat;

    for (final copy in selected) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            final fonts = _Fonts(
              regular: pw.Font.helvetica().getFont(context),
              bold: pw.Font.helveticaBold().getFont(context),
            );
            PdfImage? swiftLogo;
            if (options.showSwiftLogo && shipping.swiftLogoBytes != null) {
              swiftLogo = PdfImage.file(
                context.document,
                bytes: shipping.swiftLogoBytes!,
              );
            }
            final customerLogos = <PdfImage>[];
            if (options.showCustomerLogos &&
                options.logoPlacement != PdfLogoPlacement.hidden) {
              for (final b in customerLogoBytes.take(maxCustomerLogos)) {
                if (b.isNotEmpty) {
                  customerLogos.add(PdfImage.file(context.document, bytes: b));
                }
              }
            }
            return pw.CustomPaint(
              size: PdfPoint(format.width, format.height),
              painter: (c, size) {
                PdfImage? shipperSig;
                if (shipperSignatureBytes != null &&
                    shipperSignatureBytes.isNotEmpty) {
                  shipperSig = PdfImage.file(
                    context.document,
                    bytes: shipperSignatureBytes,
                  );
                }
                return _paint(
                  c,
                  fonts,
                  data,
                  copy,
                  swiftLogo,
                  customerLogos,
                  shipperSignature: shipperSig,
                );
              },
            );
          },
        ),
      );
    }
    return doc.save();
  }

  void _paint(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    String copyLabel,
    PdfImage? swiftLogo,
    List<PdfImage> customerLogos, {
    PdfImage? shipperSignature,
  }) {
    final pageW = pageFormat.width;
    final pageH = pageFormat.height;
    var y = pageH - margin - 2;

    // Header row: Swift + Probill are absolutely locked first. Customer logos
    // may only occupy the remaining left frame and never move static elements.
    const swiftBandH = customerLogoTargetH;
    var swiftH = swiftBandH;
    var swiftW = 0.0;
    var swiftX = margin;

    if (swiftLogo != null) {
      final iw = swiftLogo.width.toDouble();
      final ih = swiftLogo.height.toDouble();
      if (iw > 0 && ih > 0) {
        swiftW = swiftH * iw / ih;
        final maxW = contentW * 0.42;
        if (swiftW > maxW) {
          swiftW = maxW;
          swiftH = swiftW * ih / iw;
        }
        // Locked: right edge of the content band. Never shifts for uploads.
        swiftX = pageW - margin - swiftW;
        if (swiftX < margin) swiftX = margin;
        c.drawImage(swiftLogo, swiftX, y - swiftH, swiftW, swiftH);
      }
    }

    // Probill locks immediately left of Swift (hardcoded relative to Swift).
    // Customer logos never feed these coordinates.
    final probill = _probillBox(swiftX, swiftW, y, swiftH);
    final staticLeft = swiftW > 0
        ? math.min(swiftX, probill.x)
        : probill.x;
    _drawCustomerLogosLeft(
      c,
      customerLogos,
      logoTop: y,
      bandH: math.max(swiftH, customerLogoTargetH),
      frameRightLimit: staticLeft - customerToProbillGap,
    );
    _paintProbillCutout(c, fonts, d, probill);
    y -= math.max(swiftH, customerLogoTargetH) + 6;

    // Title band
    const bandH = 22.0;
    _orangeBar(c, margin, y - bandH, contentW, bandH, r: 3);
    _drawCentered(
      c,
      fonts.bold,
      8.5,
      'SWIFT OILFIELD SUPPLY',
      pageW / 2,
      y - 11,
      color: white,
    );
    _drawCentered(
      c,
      fonts.regular,
      6.5,
      'STRAIGHT BILL OF LADING  ·  NOT NEGOTIABLE',
      pageW / 2,
      y - 18,
      color: white,
    );
    c
      ..setFillColor(white)
      ..setFont(fonts.bold, 7)
      ..drawString(
        fonts.bold,
        7,
        copyLabel,
        margin + contentW - pad - _sw(fonts.bold, 7, copyLabel),
        y - bandH + 6,
      );
    y -= bandH + 10;

    y = _metaStrip(c, fonts, d, y);

    final colW = (contentW - gap) / 2;
    final lx = margin;
    final rx = margin + colW + gap;
    const hdrH = 15.0;
    // Equal-height panels sized for a 3-line Delivery Address + compact contacts.
    const nameH = 20.0;
    const addrH = 46.0;
    const contactH = 20.0;
    const panelH = nameH + addrH + contactH;

    _sectionTitle(c, fonts, lx, y, colW, 'SHIPPER (CONSIGNOR)', hdrH);
    _sectionTitle(c, fonts, rx, y, colW, 'SHIP TO (CONSIGNEE)', hdrH);
    final top = y - hdrH;
    final bot = top - panelH;
    _rect(c, lx, bot, colW, panelH, lw: 0.75);
    // Vertically center shipper lines — no open blank strip under the address.
    _drawShipperBlockCentered(c, fonts, lx + pad, top, bot);

    final row1 = top - nameH;
    final row2 = top - nameH - addrH;
    final midX = rx + colW / 2;
    _cellValue(
      c,
      fonts,
      rx,
      row1,
      colW,
      top - row1,
      'Ship To Name',
      d.get(BolFields.consigneeName),
    );
    _cellValue(
      c,
      fonts,
      rx,
      row2,
      colW,
      row1 - row2,
      'Delivery Address',
      d.get(BolFields.consigneeAddress),
      maxLines: 3,
      alignTop: true,
    );
    _cellValue(
      c,
      fonts,
      rx,
      bot,
      midX - rx,
      row2 - bot,
      'Contact Name',
      d.get(BolFields.consigneeContactName),
      compact: true,
    );
    _cellValue(
      c,
      fonts,
      midX,
      bot,
      rx + colW - midX,
      row2 - bot,
      'Contact Number',
      d.get(BolFields.consigneeContactNumber),
      compact: true,
    );
    y = bot - gap;

    final billH = 0.42 * inch;
    _sectionTitle(c, fonts, lx, y, colW, '3RD PARTY BILLING (COLLECT)', hdrH);
    final billBodyBot = y - hdrH - billH;
    _rect(c, lx, billBodyBot, colW, billH, lw: 0.75);
    _drawValue(
      c,
      fonts,
      d.get(BolFields.thirdPartyBilling),
      lx + pad,
      billBodyBot + pad,
      colW - 2 * pad,
      billH - 2 * pad,
      7,
      maxLines: 3,
    );

    final freightH = hdrH + billH;
    _rect(c, rx, y - freightH, colW, freightH, lw: 0.75);
    _sectionTitle(c, fonts, rx, y, colW, 'FREIGHT CHARGES', hdrH);
    final freight = d.get(BolFields.freightCharges).toLowerCase().trim();
    const radioSize = 8.0;
    const labelSize = 7.0;
    const radioLabelGap = 4.0;
    final freightBodyBot = y - freightH;
    final freightBodyTop = y - hdrH;
    final rowCenter = (freightBodyBot + freightBodyTop) / 2;
    final ry = rowCenter - radioSize / 2;
    // Baseline so label cap-height aligns with the radio circle center.
    final labelY = rowCenter - labelSize * 0.35;
    final options = [
      ('prepaid', 'Prepaid'),
      ('collect', 'Collect'),
      ('third_party', '3rd Party'),
    ];
    final innerLeft = rx + pad + 2;
    final innerRight = rx + colW - pad - 2;
    final widths = [
      for (final o in options)
        radioSize + radioLabelGap + _sw(fonts.regular, labelSize, o.$2),
    ];
    final totalW = widths.fold<double>(0, (a, b) => a + b);
    final free = (innerRight - innerLeft - totalW).clamp(0.0, double.infinity);
    final radioGap = free / (options.length - 1);
    var ox = innerLeft;
    for (var i = 0; i < options.length; i++) {
      final key = options[i].$1;
      final label = options[i].$2;
      final on = freight == key ||
          freight == label.toLowerCase() ||
          (key == 'third_party' && (freight == '3rd party' || freight == 'third party'));
      _radio(c, ox, ry, radioSize, on);
      c
        ..setFillColor(black)
        ..setFont(fonts.regular, labelSize)
        ..drawString(
          fonts.regular,
          labelSize,
          label,
          ox + radioSize + radioLabelGap,
          labelY,
        );
      ox += widths[i] + radioGap;
    }
    y -= freightH + gap;

    // Tracking
    const trackHdr = 13.0;
    _sectionTitle(
      c,
      fonts,
      margin,
      y,
      contentW,
      'TRACKING & REFERENCE NUMBERS',
      trackHdr,
    );
    y -= trackHdr;
    final trackCols = [
      (LabelFields.poNum, 'PO #', 1.15),
      (BolFields.packingList, 'PACKING LIST #', 1.45),
      (BolFields.orderNum, 'ORDER #', 1.15),
      (LabelFields.project, 'PROJECT', 1.35),
    ];
    const th = 12.0, rh = 14.0;
    final tSum = trackCols.fold<double>(0, (a, e) => a + e.$3);
    final tWidths = trackCols.map((e) => contentW * e.$3 / tSum).toList();
    var cx = margin;
    for (var i = 0; i < trackCols.length; i++) {
      c
        ..setFillColor(tableHead)
        ..drawRect(cx, y - th, tWidths[i], th)
        ..fillPath();
      _rect(c, cx, y - th, tWidths[i], th);
      c
        ..setFillColor(secondary)
        ..setFont(fonts.bold, 5)
        ..drawString(fonts.bold, 5, trackCols[i].$2, cx + 3, y - th + 3.5);
      cx += tWidths[i];
    }
    y -= th;
    cx = margin;
    for (var i = 0; i < trackCols.length; i++) {
      _rect(c, cx, y - rh, tWidths[i], rh);
      _drawValue(
        c,
        fonts,
        d.get(trackCols[i].$1),
        cx + inset,
        y - rh + inset,
        tWidths[i] - 2 * inset,
        rh - 2 * inset,
        7,
      );
      cx += tWidths[i];
    }
    y -= rh + gap;

    // Line items
    final lineCols = [
      ('pieces', 'QTY', 0.55),
      ('item_type', 'ITEM TYPE', 1.05),
      ('dimensions', 'DIMENSIONS (in)', 0.95),
      ('description', 'DESCRIPTION OF GOODS', 2.2),
      ('weight', 'WEIGHT (LBS)', 0.8),
    ];
    const lh = 14.0, lr = 14.0;
    final lSum = lineCols.fold<double>(0, (a, e) => a + e.$3);
    final lWidths = lineCols.map((e) => contentW * e.$3 / lSum).toList();
    cx = margin;
    for (var i = 0; i < lineCols.length; i++) {
      _orangeBar(c, cx, y - lh, lWidths[i], lh, r: 0);
      _rect(c, cx, y - lh, lWidths[i], lh, lw: 0.4);
      c
        ..setFillColor(white)
        ..setFont(fonts.bold, 5)
        ..drawString(fonts.bold, 5, lineCols[i].$2, cx + 3, y - lh + 4);
      cx += lWidths[i];
    }
    y -= lh;

    var totalPieces = 0.0;
    var totalWeight = 0.0;
    final typeTotals = {for (final t in itemTypes) t: 0.0};

    for (var row = 0; row < lineRows; row++) {
      cx = margin;
      final n = row + 1;
      final pieces = d.get(BolFields.lineKey(n, 'pieces'));
      final itypeRaw = d.get(BolFields.lineKey(n, 'item_type'));
      final dims = d.get(BolFields.lineKey(n, 'dimensions'));
      final desc = d.get(BolFields.lineKey(n, 'description'));
      final weight = d.get(BolFields.lineKey(n, 'weight'));
      final pq = double.tryParse(pieces.replaceAll(',', '')) ?? 0;
      final itype = BolItemTypes.displayForm(itypeRaw, pq);
      final vals = [pieces, itype, dims, desc, weight];
      final wq = double.tryParse(weight.replaceAll(',', '')) ?? 0;
      totalPieces += pq;
      totalWeight += wq;
      final cat = BolItemTypes.totalCategory(itypeRaw);
      if (cat.isNotEmpty) {
        for (final t in itemTypes) {
          if (cat.toLowerCase() == t.toLowerCase()) {
            typeTotals[t] = (typeTotals[t] ?? 0) + pq;
          }
        }
      }
      for (var i = 0; i < lineCols.length; i++) {
        if (row.isOdd) {
          c
            ..setFillColor(zebra)
            ..drawRect(cx, y - lr, lWidths[i], lr)
            ..fillPath();
        }
        _rect(c, cx, y - lr, lWidths[i], lr);
        _drawValue(
          c,
          fonts,
          vals[i],
          cx + inset,
          y - lr + inset,
          lWidths[i] - 2 * inset,
          lr - 2 * inset,
          7,
        );
        cx += lWidths[i];
      }
      y -= lr;
    }
    y -= gap;

    // Product total (2-col) | Special instructions | Totals — compact band
    final blockH = 0.92 * inch;
    const bHdr = 14.0;
    _alignedBottomRow(
      c,
      fonts,
      d,
      y,
      blockH,
      bHdr,
      typeTotals,
      totalPieces,
      totalWeight,
    );
    y -= blockH + gap;

    // Signature columns
    final sw = (contentW - 2 * gap) / 3;
    final sh = 1.28 * inch;
    const shdr = 14.0;
    var sx = margin;
    final bodyTop = y - shdr;
    final bodyBot = bodyTop - sh;

    // Shipper's Certification
    _sectionTitle(c, fonts, sx, y, sw, "SHIPPER'S CERTIFICATION", shdr);
    _rect(c, sx, bodyBot, sw, sh, lw: 0.75);
    final certBot = bodyBot + sh * 0.55;
    _wrapText(
      c,
      fonts,
      shipperCert,
      sx + pad,
      bodyTop - bodyInset,
      sw - 2 * pad,
      size: 4.4,
      leading: 5.2,
      color: secondary,
      minY: certBot + 3,
    );
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.5)
      ..drawLine(sx, certBot, sx + sw, certBot)
      ..strokePath();
    _sigFields(
      c,
      fonts,
      d,
      sx,
      certBot,
      bodyBot,
      sw,
      [
        [(BolFields.shipperCertName, 'Name', 1.0)],
        [
          (BolFields.shipperCertSign, 'Signature', 0.62),
          (BolFields.shipperCertDate, 'Date', 0.38),
        ],
      ],
      topInset: 7,
      signatureImages: shipperSignature == null
          ? null
          : {BolFields.shipperCertSign: shipperSignature},
    );
    sx += sw + gap;

    // Carrier / Driver Acceptance
    _sectionTitle(c, fonts, sx, y, sw, 'CARRIER / DRIVER ACCEPTANCE', shdr);
    _rect(c, sx, bodyBot, sw, sh, lw: 0.75);
    _sigFields(
      c,
      fonts,
      d,
      sx,
      bodyTop,
      bodyBot,
      sw,
      [
        [(BolFields.driverCompany, 'Company', 1.0)],
        [(BolFields.driverPrint, 'Driver Print Name', 1.0)],
        [(BolFields.driverSign, 'Signature', 1.0)],
        [(BolFields.vehicleId, 'Vehicle ID', 1.0)],
        [
          (BolFields.departureTime, 'Departure', 0.62),
          (BolFields.driverDate, 'Date', 0.38),
        ],
      ],
      topInset: bodyInset,
    );
    sx += sw + gap;

    // Consignee Delivery Receipt
    _sectionTitle(c, fonts, sx, y, sw, 'CONSIGNEE DELIVERY RECEIPT', shdr);
    _rect(c, sx, bodyBot, sw, sh, lw: 0.75);
    _sigFields(
      c,
      fonts,
      d,
      sx,
      bodyTop,
      bodyBot,
      sw,
      [
        [(BolFields.consigneeSign, 'Consignee Signature', 1.0)],
        [(BolFields.consigneePrint, 'Print Name', 1.0)],
        [(BolFields.consigneeDate, 'Date', 1.0)],
      ],
      topInset: bodyInset,
    );

    _drawPageFrame(c, pageH, contentBot: bodyBot - 4);
    _drawFooter(c, fonts);
  }

  void _alignedBottomRow(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    double y,
    double blockH,
    double hdrH,
    Map<String, double> typeTotals,
    double totalPieces,
    double totalWeight,
  ) {
    final blockBot = y - blockH;
    // Wider Product Total for dual columns; SI narrows; Totals slightly tighter.
    final pw = 2.05 * inch;
    final tw = 1.12 * inch;
    final iw = contentW - pw - tw - 2 * gap;
    final ix = margin + pw + gap;
    final tx = ix + iw + gap;
    final bodyH = blockH - hdrH;
    final bodyTop = y - hdrH;

    _sectionTitle(c, fonts, margin, y, pw, 'PRODUCT TOTAL', hdrH);
    _rect(c, margin, blockBot, pw, bodyH, lw: 0.75);

    _sectionTitle(c, fonts, ix, y, iw, 'SPECIAL INSTRUCTIONS', hdrH);
    _rect(c, ix, blockBot, iw, bodyH, lw: 0.75);

    _sectionTitle(c, fonts, tx, y, tw, 'TOTALS', hdrH);
    c
      ..setFillColor(swiftLight)
      ..drawRect(tx, blockBot, tw, bodyH)
      ..fillPath();
    _rect(c, tx, blockBot, tw, bodyH, lw: 0.75);

    // Product totals: 2-column grid (left stack + right stack).
    const leftCats = productTotalLeft;
    const rightCats = productTotalRight;
    final nRows = leftCats.length > rightCats.length
        ? leftCats.length
        : rightCats.length;
    const topInset = 5.0;
    final avail = bodyH - topInset - 3;
    final rowH = avail / nRows;
    const colGap = 5.0;
    final innerW = pw - 2 * pad;
    final colW = (innerW - colGap) / 2;

    void productTotalCol(List<String> cats, double colX) {
      for (var i = 0; i < cats.length; i++) {
        final label = cats[i];
        final rowTop = bodyTop - topInset - i * rowH;
        _micro(c, fonts, colX, rowTop - 6.5, label);
        const labelReserve = 8.5;
        final fieldTop = rowTop - labelReserve;
        final fieldBot = rowTop - rowH + 2;
        final fieldH = (fieldTop - fieldBot).clamp(9.0, rowH);
        final v = typeTotals[label] ?? 0;
        final text = v > 0
            ? v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)
            : '';
        _drawValue(
          c,
          fonts,
          text,
          colX,
          fieldBot,
          colW - 1,
          fieldH,
          8,
          alignCenter: true,
        );
        _hline(c, colX, fieldBot, colW - 1);
      }
    }

    productTotalCol(leftCats, margin + pad);
    productTotalCol(rightCats, margin + pad + colW + colGap);

    final siBot = blockBot + 3;
    final siH = bodyH - topInset - 2;
    _drawValue(
      c,
      fonts,
      d.get(LabelFields.specialInstructions),
      ix + pad,
      siBot,
      iw - 2 * pad,
      siH < 18 ? 18 : siH,
      7,
      maxLines: 5,
      alignTop: true,
    );

    final midTot = blockBot + bodyH / 2;
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.45)
      ..drawLine(tx, midTot, tx + tw, midTot)
      ..strokePath();

    _micro(c, fonts, tx + pad, bodyTop - 6, 'Total Piece Count');
    final piecesBot = midTot + 3;
    final piecesTop = bodyTop - 12;
    final piecesText = totalPieces > 0
        ? totalPieces.toStringAsFixed(0)
        : d.get(BolFields.totalPieces);
    _drawValue(
      c,
      fonts,
      piecesText,
      tx + pad,
      piecesBot,
      tw - 2 * pad,
      (piecesTop - piecesBot).clamp(12.0, 28.0),
      9,
      alignCenter: true,
    );

    _micro(c, fonts, tx + pad, midTot - 6, 'Total Weight');
    final weightBot = blockBot + 11;
    final weightTop = midTot - 12;
    final weightText = totalWeight > 0
        ? totalWeight.toStringAsFixed(0)
        : d.get(BolFields.totalWeight);
    _drawValue(
      c,
      fonts,
      weightText,
      tx + pad,
      weightBot,
      tw - 2 * pad,
      (weightTop - weightBot).clamp(12.0, 28.0),
      9,
      alignCenter: true,
    );
    c
      ..setFillColor(hint)
      ..setFont(fonts.regular, 5);
    final lbs = 'LBS';
    c.drawString(
      fonts.regular,
      5,
      lbs,
      tx + (tw - _sw(fonts.regular, 5, lbs)) / 2,
      blockBot + 3,
    );
  }

  void _sigFields(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    double x,
    double yTop,
    double yBottom,
    double w,
    List<List<(String, String, double)>> rows, {
    double? topInset,
    Map<String, PdfImage>? signatureImages,
  }) {
    final innerX = x + pad;
    final innerW = w - 2 * pad;
    final insetTop = topInset ?? bodyInset;
    const insetBot = 5.0;
    final contentTop = yTop - insetTop;
    final contentBot = yBottom + insetBot;
    final availH = contentTop - contentBot;
    if (availH < 20 || rows.isEmpty) return;

    const fieldH = 11.0;
    const labelToRule = 13.0;
    const stackH = labelToRule + 2;
    const colGap = 10.0;
    final n = rows.length;
    final rowH = availH / n;

    for (var i = 0; i < n; i++) {
      final bandTop = contentTop - i * rowH;
      final bandBot = bandTop - rowH;
      var labelY = bandBot + (rowH + stackH) / 2 - 1;
      if (labelY > bandTop - 3) labelY = bandTop - 3;
      if (labelY < bandBot + stackH) labelY = bandBot + stackH;
      final yRule = labelY - labelToRule;

      final row = rows[i];
      final total = row.fold<double>(0, (a, e) => a + e.$3);
      var cx = innerX;
      final avail = innerW - colGap * (row.length - 1);
      for (final cell in row) {
        final fw = avail * (cell.$3 / total);
        _micro(c, fonts, cx, labelY, cell.$2);
        final sigImg = signatureImages?[cell.$1];
        if (sigImg != null) {
          final maxW = fw - 2;
          // Use the full underline band up to the label (cropped PNG fills this slot).
          final maxH = (labelY - yRule - 0.5).clamp(11.0, 18.0);
          final iw = sigImg.width.toDouble();
          final ih = sigImg.height.toDouble();
          if (iw > 0 && ih > 0) {
            final fitScale = math.min(maxW / iw, maxH / ih);
            final imgW = iw * fitScale;
            final imgH = ih * fitScale;
            c.drawImage(sigImg, cx + 1, yRule + 1, imgW, imgH);
          }
        } else {
          final value = d.get(cell.$1);
          _drawValue(c, fonts, value, cx, yRule + 1.5, fw, fieldH - 1, 8);
        }
        _hline(c, cx, yRule, fw);
        cx += fw + colGap;
      }
    }
  }

  /// Locked Probill geometry from Swift only (customer logos never feed this).
  /// Prefers the slot immediately left of Swift so the left header stays free
  /// for customer logos; falls back to the right only if left cannot fit.
  ({double x, double y, double w, double h}) _probillBox(
    double logoX,
    double logoW,
    double logoTop,
    double logoH,
  ) {
    final boxW = probillBoxW;
    final boxH = logoH < 0.85 * inch ? logoH : 0.85 * inch;
    final leftX = logoX - probillCutGap - boxW;
    final rightX = logoX + logoW + probillCutGap;
    // Prefer left-of-Swift so customer logos have a stable left frame.
    double boxX;
    if (leftX >= margin) {
      boxX = leftX;
    } else if (rightX + boxW <= margin + contentW - 2) {
      boxX = rightX;
    } else {
      boxX = margin.clamp(margin, margin + contentW - boxW);
    }
    final boxY = logoTop - logoH + (logoH - boxH) / 2;
    return (x: boxX, y: boxY, w: boxW, h: boxH);
  }

  void _paintProbillCutout(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    ({double x, double y, double w, double h}) box,
  ) {
    final boxX = box.x;
    final boxY = box.y;
    final boxW = box.w;
    final boxH = box.h;

    c
      ..setFillColor(const PdfColor.fromInt(0xFFFAFAFA))
      ..drawRect(boxX, boxY, boxW, boxH)
      ..fillPath()
      ..setStrokeColor(swift)
      ..setLineWidth(1)
      ..setLineDashPattern(const [3, 2])
      ..drawRect(boxX, boxY, boxW, boxH)
      ..strokePath()
      ..setLineDashPattern(const []);

    _drawCentered(
      c,
      fonts.bold,
      6,
      'PROBILL',
      boxX + boxW / 2,
      boxY + boxH - 11,
      color: swift,
    );
    _drawCentered(
      c,
      fonts.regular,
      5,
      'AFFIX STICKER HERE',
      boxX + boxW / 2,
      boxY + boxH - 20,
      color: muted,
    );
    _drawValue(
      c,
      fonts,
      d.get(BolFields.probillNumber),
      boxX + 6,
      boxY + 6,
      boxW - 12,
      12,
      8,
    );
    _hline(c, boxX + 6, boxY + 6, boxW - 12);
  }

  double _metaStrip(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    double y,
  ) {
    const stripH = 28.0;
    final bot = y - stripH;
    c
      ..setFillColor(fieldBg)
      ..drawRect(margin, bot, contentW, stripH)
      ..fillPath();
    _rect(c, margin, bot, contentW, stripH, lw: 0.75);
    final colW = contentW / 3;
    final specs = [
      (BolFields.documentNumber, 'Document Number'),
      (BolFields.documentDate, 'Date'),
      (BolFields.bookingRef, 'Booking Ref'),
    ];
    for (var i = 0; i < specs.length; i++) {
      final cx = margin + i * colW;
      if (i > 0) {
        c
          ..setStrokeColor(rule)
          ..setLineWidth(0.5)
          ..drawLine(cx, bot, cx, y)
          ..strokePath();
      }
      _micro(c, fonts, cx + pad, y - 8, specs[i].$2);
      _drawValue(c, fonts, d.get(specs[i].$1), cx + 4, bot + 3, colW - 8, 12, 8);
      _hline(c, cx + 4, bot + 3, colW - 8);
    }
    return bot - gap;
  }

  void _drawPageFrame(PdfGraphics c, double pageH, {required double contentBot}) {
    final top = pageH - margin + 4;
    final bot = contentBot - 2;
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.75)
      ..drawRect(margin - 3, bot, contentW + 6, top - bot)
      ..strokePath()
      ..setFillColor(swift)
      ..drawRect(margin - 3, pageH - margin + 2, contentW + 6, 3)
      ..fillPath();
  }

  void _drawFooter(PdfGraphics c, _Fonts fonts) {
    final boxY = footerBase;
    final boxH = footerBoxH;
    final boxTop = boxY + boxH;
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.5)
      ..drawRect(margin, boxY, contentW, boxH)
      ..strokePath()
      ..setFillColor(swift)
      ..drawRect(margin, boxTop - 2, contentW, 2)
      ..fillPath();

    const size = 5.2;
    const leading = 6.2;
    final textW = contentW - 2 * pad;
    final textH = _measureWrapped(fonts, legal, textW, size: size, leading: leading);
    final bodyTop = boxTop - 3;
    final bodyBot = boxY + 2;
    final bodyH = bodyTop - bodyBot;
    final topPad = ((bodyH - textH) / 2).clamp(1.0, bodyH);
    final legalTop = bodyTop - topPad - size + 0.5;
    _wrapText(
      c,
      fonts,
      legal,
      margin + pad,
      legalTop,
      textW,
      size: size,
      leading: leading,
      color: muted,
      minY: bodyBot + 1,
      bold: false,
    );
  }

  void _orangeBar(
    PdfGraphics c,
    double x,
    double y,
    double w,
    double h, {
    double r = 3,
  }) {
    c.setFillColor(swift);
    if (r > 0) {
      c.drawRRect(x, y, w, h, r, r);
    } else {
      c.drawRect(x, y, w, h);
    }
    c.fillPath();
  }

  void _rect(
    PdfGraphics c,
    double x,
    double y,
    double w,
    double h, {
    double lw = 0.5,
  }) {
    c
      ..setStrokeColor(rule)
      ..setLineWidth(lw)
      ..drawRect(x, y, w, h)
      ..strokePath();
  }

  void _hline(PdfGraphics c, double x, double y, double w) {
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.4)
      ..drawLine(x, y, x + w, y)
      ..strokePath();
  }

  void _sectionTitle(
    PdfGraphics c,
    _Fonts fonts,
    double x,
    double y,
    double w,
    String text,
    double h,
  ) {
    // Sharp corners so panel grids join cleanly.
    c
      ..setFillColor(swift)
      ..drawRect(x, y - h, w, h)
      ..fillPath();
    _rect(c, x, y - h, w, h, lw: 0.5);
    const fontSize = 6.5;
    c
      ..setFillColor(white)
      ..setFont(fonts.bold, fontSize)
      ..drawString(
        fonts.bold,
        fontSize,
        text,
        x + pad,
        y - h + (h - fontSize) / 2 + 0.5,
      );
  }

  void _micro(PdfGraphics c, _Fonts fonts, double x, double y, String text) {
    c
      ..setFillColor(muted)
      ..setFont(fonts.bold, 5.5)
      ..drawString(fonts.bold, 5.5, text.toUpperCase(), x, y);
  }

  /// Fit [img] inside [maxW]×[maxH] at (x,y) bottom-left, preserving aspect ratio.
  void _drawImageInBox(
    PdfGraphics c,
    PdfImage img,
    double x,
    double y,
    double maxW,
    double maxH,
  ) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    if (iw <= 0 || ih <= 0 || maxW <= 0 || maxH <= 0) return;
    final scale = maxW / iw < maxH / ih ? maxW / iw : maxH / ih;
    final w = iw * scale;
    final h = ih * scale;
    final dx = x + (maxW - w) / 2;
    final dy = y + (maxH - h) / 2;
    c.drawImage(img, dx, dy, w, h);
  }

  /// Scale preserving aspect: prefer [targetH], never exceed [maxW]/[maxH].
  ({double w, double h}) _fitLogoSize(
    PdfImage img,
    double maxW,
    double maxH,
    double targetH,
  ) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    if (iw <= 0 || ih <= 0 || maxW <= 0 || maxH <= 0) {
      return (w: 0.0, h: 0.0);
    }
    final defaultScale = targetH / ih;
    final scale = math.min(
      maxW / iw,
      math.min(maxH / ih, defaultScale),
    );
    return (w: iw * scale, h: ih * scale);
  }

  void _drawLogoInCell(
    PdfGraphics c,
    PdfImage img,
    double cellX,
    double cellY,
    double cellW,
    double cellH,
    double targetH,
  ) {
    final size = _fitLogoSize(img, cellW, cellH, targetH);
    if (size.w <= 0 || size.h <= 0) return;
    c.drawImage(
      img,
      cellX + (cellW - size.w) / 2,
      cellY + (cellH - size.h) / 2,
      size.w,
      size.h,
    );
  }

  /// Uploaded logos only — left of the locked Probill / Swift static zone.
  ///
  /// Default height [customerLogoTargetH] (59 pt). Wide logos downscale
  /// proportionally to stay inside [margin, frameRightLimit] × band.
  /// Dual logos share equal-width cells and an equal pt height.
  void _drawCustomerLogosLeft(
    PdfGraphics c,
    List<PdfImage> customerLogos, {
    required double logoTop,
    required double bandH,
    required double frameRightLimit,
  }) {
    final logos = <PdfImage>[];
    for (final l in customerLogos.take(maxCustomerLogos)) {
      final iw = l.width.toDouble();
      final ih = l.height.toDouble();
      if (iw > 0 && ih > 0) logos.add(l);
    }
    if (logos.isEmpty) return;

    final frameLeft = margin;
    final frameRight = math.min(
      frameRightLimit,
      margin + contentW,
    );
    final frameW = frameRight - frameLeft;
    if (frameW < 8) return;

    final frameTop = logoTop - logoBandInset;
    final frameBot = logoTop - bandH + logoBandInset;
    final frameH = (frameTop - frameBot).clamp(1.0, 10000.0);
    if (frameH <= 0) return;

    // Isolate logo drawing so overflow cannot affect Swift / Probill.
    c.saveContext();
    c
      ..drawRect(frameLeft, frameBot, frameW, frameH)
      ..clipPath();

    if (logos.length == 1) {
      _drawLogoInCell(
        c,
        logos.first,
        frameLeft,
        frameBot,
        frameW,
        frameH,
        customerLogoTargetH,
      );
      c.restoreContext();
      return;
    }

    // Dual logos: equal-width grid cells, shared equal pt height.
    final cellW = (frameW - customerStackGap) / 2;
    if (cellW < 4) {
      c.restoreContext();
      return;
    }

    var sharedH = customerLogoTargetH;
    if (sharedH > frameH) sharedH = frameH;
    for (final l in logos) {
      final fitted = _fitLogoSize(l, cellW, frameH, sharedH);
      if (fitted.h < sharedH) sharedH = fitted.h;
    }
    if (sharedH < 1) {
      c.restoreContext();
      return;
    }

    for (var i = 0; i < logos.length; i++) {
      final cellX = frameLeft + i * (cellW + customerStackGap);
      _drawLogoInCell(
        c,
        logos[i],
        cellX,
        frameBot,
        cellW,
        frameH,
        sharedH,
      );
    }
    c.restoreContext();
  }

  void _radio(PdfGraphics c, double x, double y, double size, bool on) {
    final cx = x + size / 2;
    final cy = y + size / 2;
    final r = size / 2 - 0.45;
    c
      ..setFillColor(white)
      ..drawEllipse(x, y, size, size)
      ..fillPath()
      ..setStrokeColor(on ? swift : black)
      ..setLineWidth(on ? 1.1 : 0.85)
      ..drawEllipse(cx - r, cy - r, r * 2, r * 2)
      ..strokePath();
    if (on) {
      final dr = r * 0.45;
      c
        ..setFillColor(swift)
        ..drawEllipse(cx - dr, cy - dr, dr * 2, dr * 2)
        ..fillPath();
    }
  }

  void _cellValue(
    PdfGraphics c,
    _Fonts fonts,
    double x,
    double y,
    double w,
    double h,
    String label,
    String value, {
    int? maxLines,
    bool alignTop = false,
    bool compact = false,
  }) {
    _rect(c, x, y, w, h, lw: 0.6);
    final labelY = y + h - (compact ? 8.5 : 10);
    _micro(c, fonts, x + pad, labelY, label);
    final topReserve = compact ? 11.0 : (alignTop ? 12.0 : 16.0);
    final botPad = compact ? 2.0 : 4.0;
    final lines = maxLines ?? (h > 36 ? 3 : (h > 28 ? 2 : 1));
    _drawValue(
      c,
      fonts,
      value,
      x + pad,
      y + botPad,
      w - 2 * pad,
      (h - topReserve - botPad).clamp(8.0, h),
      7.5,
      maxLines: lines,
      alignTop: alignTop,
    );
  }

  void _drawShipperBlockCentered(
    PdfGraphics c,
    _Fonts fonts,
    double x,
    double top,
    double bot, {
    double size = 7.0,
  }) {
    const leadingExtra = 4.0;
    final blockH = shipperLines.isEmpty
        ? 0.0
        : shipperLines.length * size + (shipperLines.length - 1) * leadingExtra;
    final panelH = top - bot;
    const inset = 8.0;
    final avail = math.max(panelH - 2 * inset, blockH);
    var sy = top - inset - (avail - blockH) / 2;
    for (final line in shipperLines) {
      c
        ..setFillColor(black)
        ..setFont(fonts.bold, size)
        ..drawString(fonts.bold, size, line, x, sy);
      sy -= size + leadingExtra;
    }
  }

  String _latin1(String text) => text
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2026', '...')
      .replaceAll('\u00b7', '·')
      .replaceAllMapped(RegExp(r'[^\x00-\xff]'), (_) => '?');

  double _sw(PdfFont font, double size, String text) =>
      font.stringMetrics(_latin1(text)).width * size;

  void _drawCentered(
    PdfGraphics c,
    PdfFont font,
    double size,
    String text,
    double cx,
    double y, {
    required PdfColor color,
  }) {
    text = _latin1(text);
    c
      ..setFillColor(color)
      ..setFont(font, size)
      ..drawString(font, size, text, cx - _sw(font, size, text) / 2, y);
  }

  void _drawValue(
    PdfGraphics c,
    _Fonts fonts,
    String text,
    double x,
    double y,
    double w,
    double h,
    double size, {
    int maxLines = 1,
    bool alignTop = false,
    bool alignCenter = false,
  }) {
    text = _latin1(text).trim();
    if (text.isEmpty || w <= 2 || h <= 2) return;
    final leading = size + 1;
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var line = '';
    for (final word in words) {
      final trial = line.isEmpty ? word : '$line $word';
      if (_sw(fonts.bold, size, trial) > w && line.isNotEmpty) {
        lines.add(line);
        line = word;
        if (lines.length >= maxLines) break;
      } else {
        line = trial;
      }
    }
    if (line.isNotEmpty && lines.length < maxLines) lines.add(line);

    c
      ..setFillColor(black)
      ..setFont(fonts.bold, size);

    if (alignCenter) {
      final blockH = lines.length * leading - (leading - size);
      var yy = y + (h - blockH) / 2 + (lines.length - 1) * leading;
      if (yy > y + h - size) yy = y + h - size;
      if (yy < y) yy = y;
      for (final l in lines) {
        final tw = _sw(fonts.bold, size, l);
        c.drawString(fonts.bold, size, l, x + (w - tw) / 2, yy);
        yy -= leading;
      }
      return;
    }

    if (alignTop) {
      var yy = y + h - size;
      for (final l in lines) {
        if (yy < y) break;
        c.drawString(fonts.bold, size, l, x, yy);
        yy -= leading;
      }
    } else {
      // Baseline near bottom of the field rect (AcroForm-like).
      var yy = y + (h - size).clamp(0.0, h) * 0.15;
      if (lines.length > 1) {
        yy = y + (lines.length - 1) * leading;
        if (yy + size > y + h) yy = y + h - size;
      }
      for (final l in lines) {
        c.drawString(fonts.bold, size, l, x, yy);
        yy -= leading;
      }
    }
  }

  double _measureWrapped(
    _Fonts fonts,
    String text,
    double maxW, {
    required double size,
    required double leading,
  }) {
    final words = text.split(RegExp(r'\s+'));
    var lines = 0;
    var current = <String>[];
    for (final word in words) {
      final trial = [...current, word].join(' ');
      if (_sw(fonts.regular, size, trial) <= maxW) {
        current.add(word);
      } else {
        if (current.isNotEmpty) lines++;
        current = [word];
      }
    }
    if (current.isNotEmpty) lines++;
    if (lines <= 0) return 0;
    return size + (lines - 1) * leading;
  }

  void _wrapText(
    PdfGraphics c,
    _Fonts fonts,
    String text,
    double x,
    double y,
    double maxW, {
    required double size,
    required double leading,
    required PdfColor color,
    double? minY,
    bool bold = false,
  }) {
    final font = bold ? fonts.bold : fonts.regular;
    c
      ..setFillColor(color)
      ..setFont(font, size);
    final words = text.split(RegExp(r'\s+'));
    var curY = y;
    var current = <String>[];
    for (final word in words) {
      final trial = [...current, word].join(' ');
      if (_sw(font, size, trial) <= maxW) {
        current.add(word);
      } else {
        if (current.isNotEmpty) {
          if (minY != null && curY < minY) return;
          c.drawString(font, size, current.join(' '), x, curY);
          curY -= leading;
        }
        current = [word];
      }
    }
    if (current.isNotEmpty) {
      if (minY == null || curY >= minY) {
        c.drawString(font, size, current.join(' '), x, curY);
      }
    }
  }
}

class _Fonts {
  _Fonts({
    required this.regular,
    required this.bold,
  });
  final PdfFont regular;
  final PdfFont bold;
}
