import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../label_data.dart';

/// Port of `generate_swift_shipping_label_pdf.py` — Swiss layout, flat print PDF.
class ShippingLabelPdf {
  ShippingLabelPdf._({
    required this.oswald,
    required this.oswaldMedium,
    required this.oswaldSemiBold,
    required this.oswaldBold,
    required this.calibri,
    required this.calibriBold,
    required this.swiftLogoBytes,
  });

  final pw.Font oswald;
  final pw.Font oswaldMedium;
  final pw.Font oswaldSemiBold;
  final pw.Font oswaldBold;
  final pw.Font calibri;
  final pw.Font calibriBold;
  final Uint8List? swiftLogoBytes;

  static const swift = PdfColor.fromInt(0xFFCE4E30);
  static const black = PdfColor.fromInt(0xFF111111);
  static const labelC = PdfColor.fromInt(0xFF6A6A6A);
  static const rule = PdfColor.fromInt(0xFFC8C8C8);
  static const ruleSoft = PdfColor.fromInt(0xFFE2E2E2);
  static const notesBg = PdfColor.fromInt(0xFFF7F0D8);
  static const pieceFill = PdfColor.fromInt(0xFFF7F7F7);
  static const soBg = PdfColor.fromInt(0xFFF8EBE7);
  static const recvSoBg = PdfColor.fromInt(0xFFFFEB3B);
  static const recvInstructionsAlert = PdfColor.fromInt(0xFFE53935);
  static const white = PdfColor.fromInt(0xFFFFFFFF);

  static final pageFormat = PdfPageFormat.letter.landscape;
  static const inch = PdfPageFormat.inch;
  static final mx = 0.52 * inch;
  static final my = 0.48 * inch;
  static final contentW = pageFormat.width - 2 * mx;
  static const gutter = 32.0;
  static final colW = (contentW - gutter) / 2;

  static const entrySize = 18.0;
  static const entryHero = 22.0;
  static const entrySo = 36.0;
  static const entryRecvSo = 48.0;
  static const entryNotes = 18.0;
  static const entryMin = 9.0;
  static const lineGap = 3.0;
  static const wrapMaxLines = 2;

  static ShippingLabelPdf? _instance;

  static Future<ShippingLabelPdf> load() async {
    if (_instance != null) return _instance!;
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));

    Uint8List? logoBytes;
    try {
      final data =
          await rootBundle.load('assets/images/swift_supply_logo_orange.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }

    _instance = ShippingLabelPdf._(
      oswald: await font('assets/fonts/Oswald-Regular.ttf'),
      oswaldMedium: await font('assets/fonts/Oswald-Medium.ttf'),
      oswaldSemiBold: await font('assets/fonts/Oswald-SemiBold.ttf'),
      oswaldBold: await font('assets/fonts/Oswald-Bold.ttf'),
      calibri: await font('assets/fonts/Calibri.ttf'),
      calibriBold: await font('assets/fonts/Calibri-Bold.ttf'),
      swiftLogoBytes: logoBytes,
    );
    return _instance!;
  }

  double stringWidth(PdfFont font, String text, double size) {
    if (text.isEmpty) return 0;
    return font.stringMetrics(text).width * size;
  }

  List<String> wrapLines(
    String text,
    double maxW,
    PdfFont font,
    double size,
  ) {
    text = text.trim();
    if (text.isEmpty) return [];
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      final words = paragraph.isEmpty ? [''] : paragraph.split(' ');
      var cur = '';
      for (var word in words) {
        while (stringWidth(font, word, size) > maxW && word.length > 1) {
          var fit = 1;
          while (fit < word.length &&
              stringWidth(font, word.substring(0, fit + 1), size) <= maxW) {
            fit++;
          }
          final chunk = word.substring(0, fit);
          word = word.substring(fit);
          if (cur.isNotEmpty) {
            lines.add(cur);
            cur = '';
          }
          lines.add(chunk);
        }
        final trial = cur.isEmpty ? word : '$cur $word';
        if (cur.isNotEmpty && stringWidth(font, trial, size) > maxW) {
          lines.add(cur);
          cur = word;
        } else {
          cur = trial;
        }
      }
      if (cur.isNotEmpty || paragraph.isEmpty) {
        lines.add(cur);
      }
    }
    return lines;
  }

  double fitSingleLineSize(
    String text,
    double maxW,
    PdfFont font, {
    double preferred = entrySize,
    double minSize = entryMin,
  }) {
    text = text.trim();
    if (text.isEmpty) return preferred;
    var size = preferred;
    while (size > minSize && stringWidth(font, text, size) > maxW) {
      size -= 0.5;
    }
    return size;
  }

  double fitWrappedSize(
    String text,
    double maxW,
    PdfFont font, {
    double preferred = entrySize,
    int maxLines = wrapMaxLines,
    double minSize = entryMin,
  }) {
    text = text.trim();
    if (text.isEmpty) return preferred;
    var size = preferred;
    while (size > minSize) {
      final lines = wrapLines(text, maxW, font, size);
      if (lines.length <= maxLines) return size;
      size -= 0.5;
    }
    return minSize;
  }

  double fieldHeightFor(
    String text,
    PdfFont entryFont, {
    double colWidth = 0,
    double? size,
    int maxLines = wrapMaxLines,
    double pad = 8,
    double minH = 22,
  }) {
    final w = colWidth <= 0 ? colW : colWidth;
    final sz = size ??
        fitWrappedSize(text, w - 4, entryFont, preferred: entrySize);
    final lines = wrapLines(text, w - 4, entryFont, sz);
    final n = (lines.isEmpty ? 1 : lines.length).clamp(1, maxLines);
    final h = n * (sz + lineGap) + pad;
    return h < minH ? minH : h.toDouble();
  }

  /// One page per pallet/crate and per box (e.g. 8 skids + 2 boxes → 10 pages).
  Future<Uint8List> build({
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
    PieceCountPlan piecePlan = const PieceCountPlan(palletCrates: 1),
  }) async {
    final pages = <ShippingLabelData>[];
    for (var i = 1; i <= piecePlan.palletCrates; i++) {
      final page = data.copy();
      page.set(LabelFields.palletNum, '$i');
      page.set(LabelFields.palletOf, '${piecePlan.palletCrates}');
      page.set(LabelFields.boxNum, '');
      page.set(LabelFields.boxOf, '');
      pages.add(page);
    }
    for (var i = 1; i <= piecePlan.boxes; i++) {
      final page = data.copy();
      page.set(LabelFields.boxNum, '$i');
      page.set(LabelFields.boxOf, '${piecePlan.boxes}');
      page.set(LabelFields.palletNum, '');
      page.set(LabelFields.palletOf, '');
      pages.add(page);
    }
    if (pages.isEmpty) {
      pages.add(data.copy());
    }
    return _buildDoc(
      title: 'Swift Oilfield Supply — Shipping Label',
      pages: pages,
      customerLogoBytes: customerLogoBytes,
      painter: _drawPage,
    );
  }

  Future<Uint8List> buildReceiving({
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
  }) async {
    return _buildDoc(
      title: 'Swift Oilfield Supply — Receiving Label',
      pages: [data],
      customerLogoBytes: customerLogoBytes,
      painter: _drawReceivingPage,
    );
  }

  Future<Uint8List> _buildDoc({
    required String title,
    required List<ShippingLabelData> pages,
    required List<Uint8List> customerLogoBytes,
    required void Function(
      PdfGraphics c,
      _ResolvedFonts fonts,
      ShippingLabelData data,
      List<PdfImage> customerLogos,
      PdfImage? swiftLogo,
    ) painter,
  }) async {
    final doc = pw.Document(title: title, author: 'Swift Oilfield Supply');

    for (final pageData in pages) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            final fonts = _ResolvedFonts(
              oswald: oswald.getFont(context),
              oswaldMedium: oswaldMedium.getFont(context),
              oswaldBold: oswaldBold.getFont(context),
              calibri: calibri.getFont(context),
              calibriBold: calibriBold.getFont(context),
            );

            final customerLogos = <PdfImage>[];
            for (final bytes in customerLogoBytes.take(maxCustomerLogos)) {
              if (bytes.isNotEmpty) {
                customerLogos.add(
                  PdfImage.file(context.document, bytes: bytes),
                );
              }
            }
            PdfImage? swiftLogo;
            if (swiftLogoBytes != null) {
              swiftLogo =
                  PdfImage.file(context.document, bytes: swiftLogoBytes!);
            }

            return pw.CustomPaint(
              size: PdfPoint(pageFormat.width, pageFormat.height),
              painter: (PdfGraphics canvas, PdfPoint size) {
                painter(canvas, fonts, pageData, customerLogos, swiftLogo);
              },
            );
          },
        ),
      );
    }

    return doc.save();
  }

  void _fillRRect(
    PdfGraphics c,
    double x,
    double y,
    double w,
    double h,
    double r,
  ) {
    c.drawRRect(x, y, w, h, r, r);
    c.fillPath();
  }

  void _strokeRRect(
    PdfGraphics c,
    double x,
    double y,
    double w,
    double h,
    double r,
  ) {
    c.drawRRect(x, y, w, h, r, r);
    c.strokePath();
  }

  void _fillRect(PdfGraphics c, double x, double y, double w, double h) {
    c.drawRect(x, y, w, h);
    c.fillPath();
  }

  void _drawPage(
    PdfGraphics c,
    _ResolvedFonts fonts,
    ShippingLabelData sample,
    List<PdfImage> customerLogos,
    PdfImage? swiftLogo,
  ) {
    final pageH = pageFormat.height;

    _bumper(c, pageH - my + 4);

    final footY = my + 6;
    final pieceTop = footY + 70;

    var y = _drawHeader(c, fonts, customerLogos, swiftLogo);
    final pair = _drawIdentityPair(c, fonts, y, sample);
    _drawNotesAndMeta(c, fonts, pair.$1, pair.$2, sample, pieceTop + 4);

    _hairline(c, mx, pieceTop + 8, contentW, ruleSoft);
    _drawPieceBand(c, fonts, pieceTop, sample);

    c
      ..setFillColor(labelC)
      ..setFont(fonts.oswald, 7);
    c.drawString(
      fonts.oswald,
      7,
      'SWIFT OILFIELD SUPPLY  ·  NISKU, AB  ·  780-423-6979',
      mx,
      footY,
    );
    const right = 'ONE LABEL PER UNIT  ·  MATCH BOL PIECE COUNT';
    final rw = stringWidth(fonts.oswald, right, 7);
    c.drawString(fonts.oswald, 7, right, mx + contentW - rw, footY);

    _bumper(c, my - 12);
  }

  void _bumper(PdfGraphics c, double y, {double h = 10, double r = 3.5}) {
    c.setFillColor(swift);
    _fillRRect(c, mx, y, contentW, h, r);
  }

  void _hairline(
    PdfGraphics c,
    double x,
    double y,
    double w, [
    PdfColor col = rule,
    double lw = 0.6,
  ]) {
    c
      ..setStrokeColor(col)
      ..setLineWidth(lw)
      ..drawLine(x, y, x + w, y)
      ..strokePath();
  }

  void _microLabel(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double x,
    double y,
    String text,
  ) {
    c
      ..setFillColor(labelC)
      ..setFont(fonts.oswaldMedium, 7.5);
    var cx = x;
    for (final ch in _chars(text.toUpperCase())) {
      c.drawString(fonts.oswaldMedium, 7.5, ch, cx, y);
      cx += stringWidth(fonts.oswaldMedium, ch, 7.5) + 0.7;
    }
  }

  void _drawValue(
    PdfGraphics c,
    _ResolvedFonts fonts,
    String text,
    double x,
    double y,
    double w,
    double h, {
    double fontSize = entrySize,
    PdfFont? font,
    bool multiline = false,
    PdfColor textColor = black,
    bool centered = false,
  }) {
    if (text.isEmpty) return;
    final f = font ?? fonts.calibriBold;
    c
      ..setFillColor(textColor)
      ..setFont(f, fontSize);
    if (multiline) {
      final lines = wrapLines(text, w - 4, f, fontSize);
      var yy = y + h - fontSize - 2;
      for (final line in lines) {
        if (yy < y - 1) break;
        c.drawString(f, fontSize, line, x + 1, yy);
        yy -= fontSize + lineGap;
      }
    } else {
      final tx = centered ? x + (w - stringWidth(f, text, fontSize)) / 2 : x + 1;
      c.drawString(f, fontSize, text, tx, y + (h - fontSize) / 2 + 1);
    }
  }

  PdfPoint _drawImageFit(
    PdfGraphics c,
    PdfImage image,
    double x,
    double y,
    double maxW,
    double maxH, {
    bool right = false,
  }) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return const PdfPoint(0, 0);
    final scale = (maxW / iw < maxH / ih) ? maxW / iw : maxH / ih;
    final w = iw * scale;
    final h = ih * scale;
    final drawX = right ? x - w : x;
    c.drawImage(image, drawX, y, w, h);
    return PdfPoint(w, h);
  }

  /// Fit [image] inside a box at (x,y) bottom-left, centered on both axes.
  void _drawImageInBox(
    PdfGraphics c,
    PdfImage image,
    double x,
    double y,
    double maxW,
    double maxH,
  ) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0 || maxW <= 0 || maxH <= 0) return;
    final scale = (maxW / iw < maxH / ih) ? maxW / iw : maxH / ih;
    final w = iw * scale;
    final h = ih * scale;
    c.drawImage(image, x + (maxW - w) / 2, y + (maxH - h) / 2, w, h);
  }

  /// Customer-logo target height on Shipping & Receiving.
  /// Matches the Swift header mark exactly (bandH - 4 == 62.24 pt).
  static const customerLogoTargetH = 62.24;

  /// Horizontal breathing gap between Logo 1 and Logo 2.
  static const customerLogoGap = 20.0;

  /// Small breathing gap between the customer-logo row and Swift.
  static const customerLogoToSwiftGap = 12.0;

  /// Compute Swift's rendered width when fit into a [maxW]×[maxH] box.
  double _swiftRenderedWidth(PdfImage? logo, double maxW, double maxH) {
    if (logo == null) return 0;
    final iw = logo.width.toDouble();
    final ih = logo.height.toDouble();
    if (iw <= 0 || ih <= 0) return 0;
    final scale = (maxW / iw < maxH / ih) ? maxW / iw : maxH / ih;
    return iw * scale;
  }

  /// Left-align 1–2 customer logos at fixed [targetH] height with a 20 pt
  /// gap. Widths come from source aspect ratio (nativeW/nativeH * targetH).
  /// If the row exceeds [availW], both logos scale down proportionally so
  /// they share the same reduced height and preserve aspect ratios.
  ///
  /// Layout formulas (matches Shipping/Receiving spec):
  ///   logo1_x = mx
  ///   logo1_w = ih>0 ? iw/ih * H : 0
  ///   logo2_x = logo1_x + logo1_w + gap        (gap = 20)
  ///   logo2_w = ih>0 ? iw/ih * H : 0
  ///   if (logo1_w + logo2_w + gap) > availW:
  ///     scale = availW / total;  H *= scale; logo1_w *= scale; logo2_w *= scale
  void _drawCustomerLogoRow(
    PdfGraphics c,
    List<PdfImage> logos,
    double leftX,
    double logoBottom,
    double bandTop,
    double targetH,
    double availW, {
    double gap = customerLogoGap,
  }) {
    final valid = <PdfImage>[];
    for (final l in logos) {
      final iw = l.width.toDouble();
      final ih = l.height.toDouble();
      if (iw > 0 && ih > 0) valid.add(l);
    }
    if (valid.isEmpty || availW <= 0) return;

    var h = targetH;
    final widths = <double>[
      for (final l in valid) l.width / l.height * h,
    ];
    var combined = widths.fold<double>(0, (a, b) => a + b) +
        gap * (valid.length - 1);
    if (combined > availW) {
      final scale = availW / combined;
      h *= scale;
      for (var i = 0; i < widths.length; i++) {
        widths[i] *= scale;
      }
    }

    // Vertically center within the header band (bandTop..logoBottom).
    final bandCenter = (bandTop + logoBottom) / 2;
    final y = bandCenter - h / 2;

    var x = leftX;
    for (var i = 0; i < valid.length; i++) {
      c.drawImage(valid[i], x, y, widths[i], h);
      x += widths[i] + gap;
    }
  }

  double _drawHeader(
    PdfGraphics c,
    _ResolvedFonts fonts,
    List<PdfImage> customerLogos,
    PdfImage? swiftLogo, {
    bool receivingChip = false,
  }) {
    final pageH = pageFormat.height;
    final yTop = pageH - my - 14;
    final bandH = 0.92 * inch;
    final logoBottom = yTop - bandH;
    final logos = customerLogos.take(maxCustomerLogos).toList();

    // Swift wordmark on the right (aspect-preserving fit into colW*0.95 × bandH-4).
    final swiftMaxW = colW * 0.95;
    final swiftMaxH = bandH - 4;
    final swiftW = _swiftRenderedWidth(swiftLogo, swiftMaxW, swiftMaxH);
    final swiftLeftX = mx + contentW - swiftW;

    // Available width for customer logos: from left margin to Swift's left edge,
    // minus a small breathing gap. If Swift is absent, use the full band width.
    final availForCustomer = swiftW > 0
        ? (swiftLeftX - customerLogoToSwiftGap - mx)
        : contentW;

    if (logos.isNotEmpty) {
      _drawCustomerLogoRow(
        c,
        logos,
        mx,
        logoBottom,
        yTop,
        customerLogoTargetH,
        availForCustomer,
      );
    } else {
      c
        ..setStrokeColor(ruleSoft)
        ..setLineWidth(0.7)
        ..setLineDashPattern(const [2, 2]);
      final phW = 1.85 * inch;
      final phH = 0.5 * inch;
      _strokeRRect(c, mx, logoBottom + 14, phW, phH, 3);
      c.setLineDashPattern();
      c
        ..setFillColor(labelC)
        ..setFont(fonts.oswaldMedium, 7.5);
      const ph = 'CUSTOMER LOGO';
      final tw = stringWidth(fonts.oswaldMedium, ph, 7.5);
      c.drawString(
        fonts.oswaldMedium,
        7.5,
        ph,
        mx + phW / 2 - tw / 2,
        logoBottom + 14 + phH / 2 - 3,
      );
    }

    if (swiftLogo != null && swiftW > 0) {
      _drawImageFit(
        c,
        swiftLogo,
        mx + contentW,
        logoBottom + 2,
        swiftMaxW,
        swiftMaxH,
        right: true,
      );
    }

    final airUnderLogos = receivingChip ? 0.36 * inch : 0.40 * inch;
    final ruleY = logoBottom - airUnderLogos;
    c.setFillColor(swift);
    _fillRRect(c, mx, ruleY - 0.5, contentW, 2.5, 1.0);

    if (receivingChip) {
      const chip = 'RECEIVING';
      final chipW = stringWidth(fonts.oswaldBold, chip, 9) + 16;
      const chipH = 16.0;
      final chipX = mx + contentW - chipW;
      final chipY = ruleY + 8;
      c.setFillColor(soBg);
      _fillRRect(c, chipX, chipY, chipW, chipH, 4);
      c
        ..setFillColor(swift)
        ..setFont(fonts.oswaldBold, 9);
      final tw = stringWidth(fonts.oswaldBold, chip, 9);
      c.drawString(
        fonts.oswaldBold,
        9,
        chip,
        chipX + chipW / 2 - tw / 2,
        chipY + 4,
      );
      return ruleY - 18;
    }

    return ruleY - 14;
  }

  double _fieldRow(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    String label,
    String key,
    double x,
    double colWidth,
    ShippingLabelData sample, {
    double? valueH,
    double? valueSize,
    bool multiline = false,
    double preferredSize = entrySize,
    int maxLines = wrapMaxLines,
    bool hero = false,
    PdfColor? valueBgWhenNonEmpty,
  }) {
    _microLabel(c, fonts, x, y, label);
    y -= 3;
    final val = sample.get(key);
    final bold = fonts.calibriBold;
    late final double size;
    late final double vh;
    if (multiline) {
      size = valueSize ??
          fitWrappedSize(
            val,
            colWidth - 4,
            bold,
            preferred: preferredSize,
            maxLines: maxLines,
          );
      vh = valueH ??
          fieldHeightFor(
            val,
            bold,
            colWidth: colWidth,
            size: size,
            maxLines: maxLines,
          );
    } else {
      final pref = hero ? entryHero : preferredSize;
      size = valueSize ??
          fitSingleLineSize(
            val,
            colWidth - 4,
            bold,
            preferred: pref,
            minSize: hero ? 12 : entryMin,
          );
      final base = size + (hero ? 12 : 10);
      vh = valueH ?? (hero ? (base < 30 ? 30 : base) : (base < 26 ? 26 : base));
    }
    final alertFill = valueBgWhenNonEmpty != null && val.isNotEmpty;
    if (alertFill) {
      c.setFillColor(valueBgWhenNonEmpty);
      _fillRect(c, x, y - vh, colWidth, vh);
    }
    if (val.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        val,
        x,
        y - vh,
        colWidth,
        vh,
        fontSize: size,
        font: bold,
        multiline: multiline,
        textColor: alertFill ? white : black,
      );
    }
    _hairline(c, x, y - vh - 1, colWidth);
    return y - vh - 12;
  }

  void _drawReceivingPage(
    PdfGraphics c,
    _ResolvedFonts fonts,
    ShippingLabelData sample,
    List<PdfImage> customerLogos,
    PdfImage? swiftLogo,
  ) {
    final pageH = pageFormat.height;
    _bumper(c, pageH - my + 4);

    final footY = my + 6;
    final recvTop = footY + 78;
    var y = _drawHeader(
      c,
      fonts,
      customerLogos,
      swiftLogo,
      receivingChip: true,
    );

    final lx = mx;
    final rx = mx + colW + gutter;

    var yL = _fieldRow(
      c,
      fonts,
      y,
      'Customer',
      LabelFields.customer,
      lx,
      colW,
      sample,
      hero: true,
    );
    yL = _fieldRow(
      c,
      fonts,
      yL,
      'Project',
      LabelFields.project,
      lx,
      colW,
      sample,
      multiline: true,
      maxLines: 3,
    );
    yL = _fieldRow(
      c,
      fonts,
      yL,
      'PO Number',
      LabelFields.poNum,
      lx,
      colW,
      sample,
      multiline: true,
      maxLines: 2,
    );

    var yR = _drawSalesOrderRow(
      c,
      fonts,
      y,
      rx,
      colW,
      sample,
      pillBg: recvSoBg,
      preferredSize: entryRecvSo,
      minRowH: 48,
    );
    yR = _fieldRow(c, fonts, yR, 'PM', LabelFields.pm, rx, colW, sample);

    final yMid = yL < yR ? yL : yR;
    _fieldRow(
      c,
      fonts,
      yMid,
      'Special Instructions',
      LabelFields.specialInstructions,
      mx,
      contentW,
      sample,
      multiline: true,
      maxLines: 2,
      valueBgWhenNonEmpty: recvInstructionsAlert,
    );

    _hairline(c, mx, recvTop + 10, contentW, ruleSoft);
    _drawReceivedBand(c, fonts, recvTop, sample);

    c
      ..setFillColor(labelC)
      ..setFont(fonts.oswald, 7);
    c.drawString(
      fonts.oswald,
      7,
      'SWIFT OILFIELD SUPPLY  ·  NISKU, AB  ·  780-423-6979',
      mx,
      footY,
    );
    const right = 'STAGED  ·  AWAITING SHIP INSTRUCTIONS';
    final rw = stringWidth(fonts.oswald, right, 7);
    c.drawString(fonts.oswald, 7, right, mx + contentW - rw, footY);

    _bumper(c, my - 12);
  }

  void _drawReceivedBand(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    ShippingLabelData sample,
  ) {
    const rowH = 56.0;
    const gap = 12.0;
    final half = (contentW - gap) / 2;

    c.setFillColor(notesBg);
    _fillRRect(c, mx, y - rowH, contentW, rowH, 6);
    c.setFillColor(swift);
    _fillRect(c, mx, y - rowH, 3.5, rowH);

    void halfCell(double x, String label, String key) {
      _microLabel(c, fonts, x + 14, y - 14, label);
      final val = sample.get(key);
      final size = fitSingleLineSize(
        val,
        half - 28,
        fonts.calibriBold,
        preferred: entryHero,
        minSize: 12,
      );
      if (val.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          val,
          x + 14,
          y - rowH + 8,
          half - 28,
          size + 6,
          fontSize: size,
          font: fonts.calibriBold,
        );
      }
    }

    halfCell(mx, 'Date Received', LabelFields.dateReceived);
    halfCell(mx + half + gap, 'Received By', LabelFields.receivedBy);
  }

  double _drawSalesOrderRow(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    double x,
    double colWidth,
    ShippingLabelData sample, {
    PdfColor? pillBg,
    double? preferredSize,
    double minRowH = 44,
  }) {
    _microLabel(c, fonts, x, y, 'Swift Sales Order No.');
    y -= 4;
    final val = sample.get(LabelFields.salesOrder);
    const padX = 12.0;
    const padY = 8.0;
    final pref = preferredSize ?? entrySo;
    final size = fitSingleLineSize(
      val,
      colWidth - 2 * padX,
      fonts.calibriBold,
      preferred: pref,
      minSize: 14,
    );
    final textW =
        val.isEmpty ? size * 2 : stringWidth(fonts.calibriBold, val, size);
    final pillW =
        textW + 2 * padX > colWidth ? colWidth : textW + 2 * padX;
    final pillH = size + 2 * padY;
    final rowH = pillH < minRowH ? minRowH : pillH;

    c.setFillColor(pillBg ?? soBg);
    _fillRRect(c, x, y - pillH, pillW, pillH, 8);

    if (val.isNotEmpty) {
      final textBoxH = size + 4;
      final textY = y - pillH + (pillH - textBoxH) / 2;
      _drawValue(
        c,
        fonts,
        val,
        x + padX,
        textY,
        pillW - 2 * padX,
        textBoxH,
        fontSize: size,
        font: fonts.calibriBold,
      );
    }
    _hairline(c, x, y - rowH - 1, colWidth);
    return y - rowH - 12;
  }

  double _drawHero(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    ShippingLabelData sample,
  ) {
    final rx = mx + colW + gutter;
    _microLabel(c, fonts, rx, y, 'Ship to');
    y -= 5;
    final ship = sample.get(LabelFields.shipTo);
    final shipSize = fitSingleLineSize(
      ship,
      colW - 4,
      fonts.calibriBold,
      preferred: entryHero,
      minSize: 12,
    );
    final heroH = shipSize + 12 < 30 ? 30.0 : shipSize + 12;
    if (ship.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        ship,
        rx,
        y - heroH,
        colW,
        heroH,
        fontSize: shipSize,
        font: fonts.calibriBold,
      );
    }
    c
      ..setStrokeColor(black)
      ..setLineWidth(1.0)
      ..drawLine(rx, y - heroH - 2, rx + colW, y - heroH - 2)
      ..strokePath();
    y -= heroH + 12;

    final loc = sample.get(LabelFields.location);
    final locSize = fitWrappedSize(loc, colW - 4, fonts.calibriBold);
    final locH = fieldHeightFor(loc, fonts.calibriBold, size: locSize);
    _microLabel(c, fonts, rx, y, 'Location');
    y -= 3;
    if (loc.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        loc,
        rx,
        y - locH,
        colW,
        locH,
        fontSize: locSize,
        font: fonts.calibriBold,
        multiline: true,
      );
    }
    _hairline(c, rx, y - locH - 1, colW);
    y -= locH + 12;

    final attn = sample.get(LabelFields.attn);
    final attnSize = fitSingleLineSize(attn, colW - 4, fonts.calibriBold);
    final attnH = attnSize + 10 < 26 ? 26.0 : attnSize + 10;
    _microLabel(c, fonts, rx, y, 'Attn');
    y -= 3;
    if (attn.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        attn,
        rx,
        y - attnH,
        colW,
        attnH,
        fontSize: attnSize,
        font: fonts.calibriBold,
      );
    }
    _hairline(c, rx, y - attnH - 1, colW);
    return y - attnH - 12;
  }

  (double, double) _drawIdentityPair(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    ShippingLabelData sample,
  ) {
    final lx = mx;
    final bold = fonts.calibriBold;

    var yL = _fieldRow(
      c,
      fonts,
      y,
      'Customer',
      LabelFields.customer,
      lx,
      colW,
      sample,
    );

    final po = sample.get(LabelFields.poNum);
    final poSize = fitWrappedSize(po, colW - 4, bold);
    final poH = fieldHeightFor(po, bold, size: poSize);
    yL = _fieldRow(
      c,
      fonts,
      yL,
      'PO No.',
      LabelFields.poNum,
      lx,
      colW,
      sample,
      valueH: poH,
      valueSize: poSize,
      multiline: true,
    );

    final proj = sample.get(LabelFields.project);
    final projSize = fitWrappedSize(proj, colW - 4, bold);
    final projH = fieldHeightFor(proj, bold, size: projSize);
    yL = _fieldRow(
      c,
      fonts,
      yL,
      'Project',
      LabelFields.project,
      lx,
      colW,
      sample,
      valueH: projH,
      valueSize: projSize,
      multiline: true,
    );

    final yR = _drawHero(c, fonts, y, sample);
    return (yL, yR);
  }

  void _drawNotesAndMeta(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double yLeft,
    double yRight,
    ShippingLabelData sample,
    double bandBottom,
  ) {
    final lx = mx;
    final rx = mx + colW + gutter;

    const soReserve = 56.0;
    final usable = (yRight - (bandBottom + 20)).clamp(100.0, 10000.0);
    final otherBand = (usable - soReserve).clamp(72.0, 10000.0);
    final slot = otherBand / 3;

    var y = yRight;
    y = _fieldRow(c, fonts, y, 'Carrier', LabelFields.carrier, rx, colW, sample);
    final packFloor = yRight - 2 * slot;
    if (y > packFloor) y = packFloor;

    y = _fieldRow(
      c,
      fonts,
      y,
      'Swift Packing Slip No.',
      LabelFields.packingSlip,
      rx,
      colW,
      sample,
    );

    y = _drawSalesOrderRow(c, fonts, y, rx, colW, sample);

    final contactTop = bandBottom + 20 + slot;
    if (y > contactTop) y = contactTop;
    _fieldRow(
      c,
      fonts,
      y,
      'Swift Contact',
      LabelFields.swiftContact,
      rx,
      colW,
      sample,
    );

    _microLabel(c, fonts, lx, yLeft, 'Special Instructions');
    final notesTop = yLeft - 4;
    final notesFloor = bandBottom + 20;
    final notesH = (notesTop - notesFloor).clamp(48.0, 10000.0);
    c.setFillColor(notesBg);
    _fillRect(c, lx, notesTop - notesH, colW, notesH);
    c.setFillColor(swift);
    _fillRect(c, lx, notesTop - notesH, 3.5, notesH);

    final notes = sample.get(LabelFields.specialInstructions);
    final notesBoxH = notesH - 8;
    var notesSize = entryNotes;
    while (notesSize > entryMin && notes.isNotEmpty) {
      final lines = wrapLines(notes, colW - 18, fonts.calibriBold, notesSize);
      final need = lines.length * (notesSize + lineGap) + 4;
      if (need <= notesBoxH) break;
      notesSize -= 0.5;
    }
    if (notes.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        notes,
        lx + 10,
        notesTop - notesH + 4,
        colW - 14,
        notesBoxH,
        fontSize: notesSize,
        font: fonts.calibriBold,
        multiline: true,
      );
    }
  }

  void _drawPieceBand(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    ShippingLabelData sample,
  ) {
    const rowH = 38.0;
    const gap = 12.0;
    final half = (contentW - gap) / 2;

    void cell(double x, String label, String prefix) {
      c.setFillColor(pieceFill);
      _fillRRect(c, x, y - rowH, half, rowH, 4);
      c
        ..setStrokeColor(ruleSoft)
        ..setLineWidth(0.6);
      _strokeRRect(c, x, y - rowH, half, rowH, 4);

      c
        ..setFillColor(labelC)
        ..setFont(fonts.oswaldMedium, 7.5);
      var cx = x + 12;
      final cellMid = y - rowH / 2;
      final labelMidY = cellMid - 2.5;
      for (final ch in _chars(label.toUpperCase())) {
        c.drawString(fonts.oswaldMedium, 7.5, ch, cx, labelMidY);
        cx += stringWidth(fonts.oswaldMedium, ch, 7.5) + 0.7;
      }

      const box = 34.0;
      const ofW = 28.0;
      const blockW = box * 2 + ofW;
      final fx = x + (half - blockW) / 2;

      final numVal = sample.get('${prefix}_num');
      final ofVal = sample.get('${prefix}_of');

      const valueH = 20.0;
      final valueY = cellMid - valueH / 2;
      final underlineY = valueY - 1;

      final numSz = fitSingleLineSize(
        numVal,
        box - 4,
        fonts.calibriBold,
        preferred: entrySize,
        minSize: 11,
      );
      if (numVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          numVal,
          fx,
          valueY,
          box,
          valueH,
          fontSize: numSz,
          font: fonts.calibriBold,
          centered: true,
        );
      }
      _hairline(c, fx, underlineY, box);

      c
        ..setFillColor(swift)
        ..setFont(fonts.oswaldBold, 11);
      const ofText = 'OF';
      final ofTw = stringWidth(fonts.oswaldBold, ofText, 11);
      c.drawString(
        fonts.oswaldBold,
        11,
        ofText,
        fx + box + ofW / 2 - ofTw / 2,
        labelMidY,
      );

      final ofSz = fitSingleLineSize(
        ofVal,
        box - 4,
        fonts.calibriBold,
        preferred: entrySize,
        minSize: 11,
      );
      if (ofVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          ofVal,
          fx + box + ofW,
          valueY,
          box,
          valueH,
          fontSize: ofSz,
          font: fonts.calibriBold,
          centered: true,
        );
      }
      _hairline(c, fx + box + ofW, underlineY, box);
    }

    cell(mx, 'Pallet / Crate', 'pallet');
    cell(mx + half + gap, 'Box', 'box');
  }

  static Iterable<String> _chars(String s) sync* {
    for (final r in s.runes) {
      yield String.fromCharCode(r);
    }
  }
}

class _ResolvedFonts {
  _ResolvedFonts({
    required this.oswald,
    required this.oswaldMedium,
    required this.oswaldBold,
    required this.calibri,
    required this.calibriBold,
  });

  final PdfFont oswald;
  final PdfFont oswaldMedium;
  final PdfFont oswaldBold;
  final PdfFont calibri;
  final PdfFont calibriBold;
}
