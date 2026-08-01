import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../label_data.dart';
import 'shipping_label_pdf.dart';

/// Flat print Bill of Lading — layout ported from `generate_swift_bol_pdf.py`.
/// Three pages: STORE / DRIVER / CUSTOMER copy (same field values).
class BolLabelPdf {
  BolLabelPdf(this.shipping);

  final ShippingLabelPdf shipping;

  static const swift = PdfColor.fromInt(0xFFD94B2B);
  static const swiftLight = PdfColor.fromInt(0xFFFDF4F1);
  static const black = PdfColor.fromInt(0xFF1A1A1A);
  static const secondary = PdfColor.fromInt(0xFF4A4A4A);
  static const muted = PdfColor.fromInt(0xFF767676);
  static const hint = PdfColor.fromInt(0xFF9A9A9A);
  static const rule = PdfColor.fromInt(0xFFC8C8C8);
  static const tableHead = PdfColor.fromInt(0xFFF0F0F0);
  static const zebra = PdfColor.fromInt(0xFFF7F7F7);
  static const fieldBg = PdfColor.fromInt(0xFFF4F7FA);

  static final pageFormat = PdfPageFormat.letter;
  static const inch = PdfPageFormat.inch;
  static final margin = 0.4 * inch;
  static final contentW = pageFormat.width - 2 * margin;
  static const gap = 7.0;
  static const pad = 6.0;
  static const lineRows = 7;
  static const itemTypes = ['Pallets', 'Crates', 'Boxes', 'Pipe', 'Other'];
  static const copyTypes = ['STORE COPY', 'DRIVER COPY', 'CUSTOMER COPY'];
  static const shipperLines = [
    'Swift Oilfield Supply',
    'Unit 200, 920 - 36 Avenue',
    'Nisku, AB  T9E 1C6',
    '780-423-6979',
  ];

  Future<Uint8List> build({
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
  }) async {
    final doc = pw.Document(
      title: 'Swift Oilfield Supply — Straight Bill of Lading',
      author: 'Swift Oilfield Supply',
    );

    for (final copy in copyTypes) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            final fonts = _Fonts(
              regular: pw.Font.helvetica().getFont(context),
              bold: pw.Font.helveticaBold().getFont(context),
              oswaldBold: shipping.oswaldBold.getFont(context),
            );
            PdfImage? swiftLogo;
            if (shipping.swiftLogoBytes != null) {
              swiftLogo = PdfImage.file(
                context.document,
                bytes: shipping.swiftLogoBytes!,
              );
            }
            final customerLogos = <PdfImage>[];
            for (final b in customerLogoBytes.take(maxCustomerLogos)) {
              if (b.isNotEmpty) {
                customerLogos.add(PdfImage.file(context.document, bytes: b));
              }
            }
            return pw.CustomPaint(
              size: PdfPoint(pageFormat.width, pageFormat.height),
              painter: (c, size) =>
                  _paint(c, fonts, data, copy, swiftLogo, customerLogos),
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
    List<PdfImage> customerLogos,
  ) {
    final pageW = pageFormat.width;
    final pageH = pageFormat.height;
    var y = pageH - margin - 2;

    // Logo centered
    var logoH = 0.72 * inch;
    var logoW = 0.0;
    var logoX = margin;
    if (swiftLogo != null) {
      final iw = swiftLogo.width.toDouble();
      final ih = swiftLogo.height.toDouble();
      if (iw > 0 && ih > 0) {
        logoW = logoH * iw / ih;
        final maxW = contentW * 0.7;
        if (logoW > maxW) {
          logoW = maxW;
          logoH = logoW * ih / iw;
        }
        logoX = (pageW - logoW) / 2;
        c.drawImage(swiftLogo, logoX, y - logoH, logoW, logoH);
      }
    }

    // Optional C/O logos small on left of header
    if (customerLogos.isNotEmpty) {
      final slot = 0.9 * inch;
      for (var i = 0; i < customerLogos.length; i++) {
        final img = customerLogos[i];
        final iw = img.width.toDouble();
        final ih = img.height.toDouble();
        if (iw <= 0 || ih <= 0) continue;
        final h = logoH * 0.85;
        final w = h * iw / ih;
        final x = margin + i * (slot);
        final drawW = w > slot - 4 ? slot - 4 : w;
        c.drawImage(img, x, y - h, drawW, h);
      }
    }

    // Probill cutout (right)
    _probillCutout(c, fonts, d, logoX, logoW, y, logoH);
    y -= logoH + 6;

    // Title band
    const bandH = 22.0;
    _orangeBar(c, margin, y - bandH, contentW, bandH);
    c
      ..setFillColor(const PdfColor.fromInt(0xFFFFFFFF))
      ..setFont(fonts.bold, 8.5)
      ..drawString(
        fonts.bold,
        8.5,
        'SWIFT OILFIELD SUPPLY',
        pageW / 2 - fonts.bold.stringMetrics('SWIFT OILFIELD SUPPLY').width * 8.5 / 2,
        y - 11,
      )
      ..setFont(fonts.regular, 6.5);
    const sub = 'STRAIGHT BILL OF LADING  ·  NOT NEGOTIABLE';
    c.drawString(
      fonts.regular,
      6.5,
      sub,
      pageW / 2 - fonts.regular.stringMetrics(sub).width * 6.5 / 2,
      y - 18,
    );
    c
      ..setFont(fonts.bold, 6)
      ..setFillColor(const PdfColor.fromInt(0xFFFFFFFF))
      ..drawString(
        fonts.bold,
        6,
        copyLabel,
        margin + contentW - fonts.bold.stringMetrics(copyLabel).width * 6 - 8,
        y - 14,
      );
    y -= bandH + 10;

    y = _metaStrip(c, fonts, d, y);

    final colW = (contentW - gap) / 2;
    final lx = margin;
    final rx = margin + colW + gap;
    const hdrH = 15.0;
    final panelH = 1.05 * inch;

    _sectionTitle(c, fonts, lx, y, colW, 'SHIPPER (CONSIGNOR)', hdrH);
    _sectionTitle(c, fonts, rx, y, colW, 'SHIP TO (CONSIGNEE)', hdrH);
    final top = y - hdrH;
    final bot = top - panelH;
    _rect(c, lx, bot, colW, panelH);
    var sy = top - 12;
    for (final line in shipperLines) {
      c
        ..setFillColor(black)
        ..setFont(fonts.bold, 7)
        ..drawString(fonts.bold, 7, line, lx + pad, sy);
      sy -= 10;
    }

    final row1 = top - panelH * 0.30;
    final row2 = top - panelH * 0.58;
    final midX = rx + colW / 2;
    _cellValue(c, fonts, rx, row1, colW, top - row1, 'Ship To Name', d.get(BolFields.consigneeName));
    _cellValue(c, fonts, rx, row2, colW, row1 - row2, 'Delivery Address', d.get(BolFields.consigneeAddress));
    _cellValue(c, fonts, rx, bot, midX - rx, row2 - bot, 'Contact Name', d.get(BolFields.consigneeContactName));
    _cellValue(c, fonts, midX, bot, rx + colW - midX, row2 - bot, 'Contact Number', d.get(BolFields.consigneeContactNumber));
    y = bot - gap;

    final billH = 0.38 * inch;
    _sectionTitle(c, fonts, lx, y, colW, '3RD PARTY BILLING (COLLECT)', hdrH);
    final bodyBot = y - hdrH - billH;
    _rect(c, lx, bodyBot, colW, billH);
    _drawText(c, fonts, d.get(BolFields.thirdPartyBilling), lx + pad, bodyBot + 8, colW - 2 * pad, 7);

    final freightH = hdrH + billH;
    _rect(c, rx, y - freightH, colW, freightH);
    _sectionTitle(c, fonts, rx, y, colW, 'FREIGHT CHARGES', hdrH);
    final freight = d.get(BolFields.freightCharges).toLowerCase();
    final opts = ['Prepaid', 'Collect', '3rd Party'];
    final keys = ['prepaid', 'collect', 'third_party'];
    var ox = rx + pad;
    final ry = bodyBot + (billH - 10) / 2;
    for (var i = 0; i < opts.length; i++) {
      final on = freight == keys[i] || freight == opts[i].toLowerCase();
      c
        ..setStrokeColor(swift)
        ..setLineWidth(0.8)
        ..drawEllipse(ox, ry, 5, 5)
        ..strokePath();
      if (on) {
        c
          ..setFillColor(swift)
          ..drawEllipse(ox + 1.5, ry + 1.5, 2, 2)
          ..fillPath();
      }
      c
        ..setFillColor(black)
        ..setFont(fonts.regular, 6.5)
        ..drawString(fonts.regular, 6.5, opts[i], ox + 12, ry);
      ox += 70;
    }
    y -= freightH + gap;

    // Tracking
    const trackHdr = 13.0;
    _sectionTitle(c, fonts, margin, y, contentW, 'TRACKING & REFERENCE NUMBERS', trackHdr);
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
      c.setFillColor(tableHead);
      c.drawRect(cx, y - th, tWidths[i], th);
      c.fillPath();
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
      _drawText(c, fonts, d.get(trackCols[i].$1), cx + 3, y - rh + 3, tWidths[i] - 6, 7);
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
    const lh = 14.0, lr = 13.0;
    final lSum = lineCols.fold<double>(0, (a, e) => a + e.$3);
    final lWidths = lineCols.map((e) => contentW * e.$3 / lSum).toList();
    cx = margin;
    for (var i = 0; i < lineCols.length; i++) {
      _orangeBar(c, cx, y - lh, lWidths[i], lh, r: 0);
      _rect(c, cx, y - lh, lWidths[i], lh);
      c
        ..setFillColor(const PdfColor.fromInt(0xFFFFFFFF))
        ..setFont(fonts.bold, 5)
        ..drawString(fonts.bold, 5, lineCols[i].$2, cx + 3, y - lh + 4);
      cx += lWidths[i];
    }
    y -= lh;

    double totalPieces = 0, totalWeight = 0;
    final typeTotals = {for (final t in itemTypes) t: 0.0};

    for (var row = 0; row < lineRows; row++) {
      cx = margin;
      final n = row + 1;
      final pieces = d.get(BolFields.lineKey(n, 'pieces'));
      final itype = d.get(BolFields.lineKey(n, 'item_type'));
      final dims = d.get(BolFields.lineKey(n, 'dimensions'));
      final desc = d.get(BolFields.lineKey(n, 'description'));
      final weight = d.get(BolFields.lineKey(n, 'weight'));
      final vals = [pieces, itype, dims, desc, weight];
      final pq = double.tryParse(pieces.replaceAll(',', '')) ?? 0;
      final wq = double.tryParse(weight.replaceAll(',', '')) ?? 0;
      totalPieces += pq;
      totalWeight += wq;
      for (final t in itemTypes) {
        if (itype.toLowerCase() == t.toLowerCase()) {
          typeTotals[t] = (typeTotals[t] ?? 0) + pq;
        }
      }
      for (var i = 0; i < lineCols.length; i++) {
        if (row.isOdd) {
          c.setFillColor(zebra);
          c.drawRect(cx, y - lr, lWidths[i], lr);
          c.fillPath();
        }
        _rect(c, cx, y - lr, lWidths[i], lr);
        _drawText(c, fonts, vals[i], cx + 2, y - lr + 3, lWidths[i] - 4, 6.5);
        cx += lWidths[i];
      }
      y -= lr;
    }
    y -= gap;

    // Bottom: product totals | special instructions | totals
    final blockH = 1.15 * inch;
    final blockBot = y - blockH;
    final pw = 1.48 * inch;
    final tw = 1.28 * inch;
    final iw = contentW - pw - tw - 2 * gap;
    final ix = margin + pw + gap;
    final tx = ix + iw + gap;
    const bHdr = 14.0;
    final bodyH = blockH - bHdr;
    final bodyTop = y - bHdr;

    _sectionTitle(c, fonts, margin, y, pw, 'PRODUCT TOTAL', bHdr);
    _rect(c, margin, blockBot, pw, bodyH);
    _sectionTitle(c, fonts, ix, y, iw, 'SPECIAL INSTRUCTIONS', bHdr);
    _rect(c, ix, blockBot, iw, bodyH);
    _sectionTitle(c, fonts, tx, y, tw, 'TOTALS', bHdr);
    c.setFillColor(swiftLight);
    c.drawRect(tx, blockBot, tw, bodyH);
    c.fillPath();
    _rect(c, tx, blockBot, tw, bodyH);

    final avail = bodyH - 10;
    final rowH = avail / itemTypes.length;
    for (var i = 0; i < itemTypes.length; i++) {
      final label = itemTypes[i];
      final rowTop = bodyTop - 6 - i * rowH;
      _micro(c, fonts, margin + pad, rowTop - 8, label);
      final v = typeTotals[label] ?? 0;
      _drawText(
        c,
        fonts,
        v > 0 ? v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1) : '',
        margin + pad + 48,
        rowTop - 18,
        pw - 2 * pad - 48,
        8,
      );
    }
    _drawText(
      c,
      fonts,
      d.get(LabelFields.specialInstructions),
      ix + pad,
      blockBot + 6,
      iw - 2 * pad,
      7,
      maxLines: 6,
    );
    final midTot = blockBot + bodyH / 2;
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.45)
      ..drawLine(tx, midTot, tx + tw, midTot)
      ..strokePath();
    _micro(c, fonts, tx + pad, bodyTop - 8, 'Total Piece Count');
    _drawText(
      c,
      fonts,
      totalPieces > 0 ? totalPieces.toStringAsFixed(0) : d.get(BolFields.totalPieces),
      tx + pad,
      midTot + 6,
      tw - 2 * pad,
      9,
    );
    _micro(c, fonts, tx + pad, midTot - 8, 'Total Weight');
    _drawText(
      c,
      fonts,
      totalWeight > 0 ? totalWeight.toStringAsFixed(0) : d.get(BolFields.totalWeight),
      tx + pad,
      blockBot + 14,
      tw - 2 * pad,
      9,
    );
    c
      ..setFillColor(hint)
      ..setFont(fonts.regular, 5)
      ..drawString(fonts.regular, 5, 'LBS', tx + pad, blockBot + 5);

    y = blockBot - gap;

    // Signature columns (compact)
    final sw = (contentW - 2 * gap) / 3;
    final sh = 1.05 * inch;
    const shdr = 14.0;
    var sx = margin;
    final sTop = y - shdr;
    final sBot = sTop - sh;

    void sigCol(String title, List<(String, String)> fields) {
      _sectionTitle(c, fonts, sx, y, sw, title, shdr);
      _rect(c, sx, sBot, sw, sh);
      var yy = sTop - 12;
      for (final f in fields) {
        _micro(c, fonts, sx + pad, yy, f.$2);
        _drawText(c, fonts, d.get(f.$1), sx + pad, yy - 14, sw - 2 * pad, 7);
        c
          ..setStrokeColor(rule)
          ..setLineWidth(0.4)
          ..drawLine(sx + pad, yy - 16, sx + sw - pad, yy - 16)
          ..strokePath();
        yy -= 22;
      }
      sx += sw + gap;
    }

    sigCol('SHIPPER\'S CERTIFICATION', [
      (BolFields.shipperCertName, 'Name'),
      (BolFields.shipperCertDate, 'Date'),
    ]);
    sigCol('CARRIER / DRIVER ACCEPTANCE', [
      (BolFields.driverPrint, 'Driver Print Name'),
      (BolFields.vehicleId, 'Vehicle ID'),
      (BolFields.driverDate, 'Date'),
    ]);
    sigCol('CONSIGNEE DELIVERY RECEIPT', [
      (BolFields.consigneePrint, 'Print Name'),
      (BolFields.consigneeDate, 'Date'),
    ]);

    // Frame + footer
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.75)
      ..drawRect(margin - 3, sBot - 4, contentW + 6, pageH - margin + 2 - (sBot - 4))
      ..strokePath();
    c.setFillColor(swift);
    c.drawRect(margin - 3, pageH - margin + 2, contentW + 6, 3);
    c.fillPath();

    c
      ..setFillColor(muted)
      ..setFont(fonts.regular, 6)
      ..drawString(
        fonts.regular,
        6,
        'SWIFT OILFIELD SUPPLY  ·  NISKU, AB  ·  780-423-6979',
        margin,
        margin + 4,
      );
  }

  void _probillCutout(
    PdfGraphics c,
    _Fonts fonts,
    ShippingLabelData d,
    double logoX,
    double logoW,
    double logoTop,
    double logoH,
  ) {
    final boxW = 2.1 * inch;
    final boxH = logoH < 0.75 * inch ? logoH : 0.75 * inch;
    var boxX = logoX + logoW + 14;
    if (boxX + boxW > margin + contentW) {
      boxX = margin + contentW - boxW;
    }
    final boxY = logoTop - logoH + (logoH - boxH) / 2;
    c.setFillColor(const PdfColor.fromInt(0xFFFAFAFA));
    c.drawRect(boxX, boxY, boxW, boxH);
    c.fillPath();
    c
      ..setStrokeColor(swift)
      ..setLineWidth(1)
      ..setLineDashPattern(const [3, 2])
      ..drawRect(boxX, boxY, boxW, boxH)
      ..strokePath()
      ..setLineDashPattern([]);
    c
      ..setFillColor(swift)
      ..setFont(fonts.bold, 6)
      ..drawString(
        fonts.bold,
        6,
        'PROBILL',
        boxX + boxW / 2 - fonts.bold.stringMetrics('PROBILL').width * 3,
        boxY + boxH - 11,
      )
      ..setFillColor(muted)
      ..setFont(fonts.regular, 5)
      ..drawString(
        fonts.regular,
        5,
        'AFFIX STICKER HERE',
        boxX + boxW / 2 - fonts.regular.stringMetrics('AFFIX STICKER HERE').width * 2.5,
        boxY + boxH - 20,
      );
    _drawText(c, fonts, d.get(BolFields.probillNumber), boxX + 6, boxY + 6, boxW - 12, 8);
  }

  void _orangeBar(PdfGraphics c, double x, double y, double w, double h, {double r = 3}) {
    c.setFillColor(swift);
    if (r > 0) {
      c.drawRRect(x, y, w, h, r, r);
    } else {
      c.drawRect(x, y, w, h);
    }
    c.fillPath();
  }

  void _rect(PdfGraphics c, double x, double y, double w, double h) {
    c
      ..setStrokeColor(rule)
      ..setLineWidth(0.6)
      ..drawRect(x, y, w, h)
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
    _orangeBar(c, x, y - h, w, h);
    c
      ..setFillColor(const PdfColor.fromInt(0xFFFFFFFF))
      ..setFont(fonts.bold, 7)
      ..drawString(fonts.bold, 7, text, x + 6, y - h + 4);
  }

  void _micro(PdfGraphics c, _Fonts fonts, double x, double y, String text) {
    c
      ..setFillColor(muted)
      ..setFont(fonts.regular, 5.5)
      ..drawString(fonts.regular, 5.5, text.toUpperCase(), x, y);
  }

  String _latin1(String text) => text
      .replaceAll('\u2014', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll('\u2026', '...')
      .replaceAllMapped(RegExp(r'[^\x00-\xff]'), (_) => '?');

  void _drawText(
    PdfGraphics c,
    _Fonts fonts,
    String text,
    double x,
    double y,
    double w,
    double size, {
    int maxLines = 2,
  }) {
    text = _latin1(text).trim();
    if (text.isEmpty) return;
    c
      ..setFillColor(black)
      ..setFont(fonts.bold, size);
    // Simple wrap
    final words = text.split(RegExp(r'\s+'));
    var line = '';
    var yy = y + (maxLines > 1 ? (maxLines - 1) * (size + 1) : 0);
    var lines = 0;
    for (final word in words) {
      final trial = line.isEmpty ? word : '$line $word';
      if (fonts.bold.stringMetrics(trial).width * size > w && line.isNotEmpty) {
        c.drawString(fonts.bold, size, line, x, yy);
        yy -= size + 1;
        line = word;
        lines++;
        if (lines >= maxLines) return;
      } else {
        line = trial;
      }
    }
    if (line.isNotEmpty && lines < maxLines) {
      c.drawString(fonts.bold, size, line, x, yy);
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
    String value,
  ) {
    _rect(c, x, y, w, h);
    _micro(c, fonts, x + pad, y + h - 10, label);
    _drawText(c, fonts, value, x + pad, y + 4, w - 2 * pad, 7.5, maxLines: h > 28 ? 2 : 1);
  }

  double _metaStrip(PdfGraphics c, _Fonts fonts, ShippingLabelData d, double y) {
    const stripH = 36.0;
    final bot = y - stripH;
    c.setFillColor(fieldBg);
    c.drawRect(margin, bot, contentW, stripH);
    c.fillPath();
    _rect(c, margin, bot, contentW, stripH);
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
      _micro(c, fonts, cx + pad, y - 10, specs[i].$2);
      _drawText(c, fonts, d.get(specs[i].$1), cx + 4, bot + 5, colW - 8, 8);
    }
    return bot - gap;
  }
}

class _Fonts {
  _Fonts({
    required this.regular,
    required this.bold,
    required this.oswaldBold,
  });
  final PdfFont regular;
  final PdfFont bold;
  final PdfFont oswaldBold;
}
