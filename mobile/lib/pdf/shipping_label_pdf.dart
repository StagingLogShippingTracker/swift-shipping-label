import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart';

import '../label_data.dart';
import '../logo_image_process.dart';
import '../pdf_render_options.dart';

/// Port of `generate_swift_shipping_label_pdf.py` — Swiss layout, flat print PDF.
class ShippingLabelPdf {
  ShippingLabelPdf._({
    required this.oswald,
    required this.oswaldMedium,
    required this.oswaldSemiBold,
    required this.oswaldBold,
    required this.calibri,
    required this.calibriBold,
    required this.montserrat,
    required this.montserratBold,
    required this.swiftLogoBytes,
  });

  final pw.Font oswald;
  final pw.Font oswaldMedium;
  final pw.Font oswaldSemiBold;
  final pw.Font oswaldBold;
  final pw.Font calibri;
  final pw.Font calibriBold;
  final pw.Font montserrat;
  final pw.Font montserratBold;
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
  /// Shipping Sales Order No. preferred font size (pt).
  static const entrySo = 48.0;
  static const entryRecvSo = 60.0;
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
      montserrat: await font('assets/fonts/Montserrat-Regular.ttf'),
      montserratBold: await font('assets/fonts/Montserrat-Bold.ttf'),
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
    PdfRenderOptions options = PdfRenderOptions.defaults,
  }) async {
    final doc = pw.Document(
      title: 'Swift Oilfield Supply — Shipping Label',
      author: 'Swift Oilfield Supply',
    );
    await appendPages(
      doc,
      data: data,
      customerLogoBytes: customerLogoBytes,
      piecePlan: piecePlan,
      options: options,
    );
    return doc.save();
  }

  /// Append shipping pages onto an existing document (e.g. after BOL pages).
  Future<void> appendPages(
    pw.Document doc, {
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
    PieceCountPlan piecePlan = const PieceCountPlan(palletCrates: 1),
    PdfRenderOptions options = PdfRenderOptions.defaults,
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
    await _appendDocPages(
      doc,
      pages: pages,
      customerLogoBytes: customerLogoBytes,
      painter: _drawPage,
      options: options,
    );
  }

  Future<Uint8List> buildReceiving({
    required ShippingLabelData data,
    List<Uint8List> customerLogoBytes = const [],
    PdfRenderOptions options = PdfRenderOptions.defaults,
  }) async {
    final doc = pw.Document(
      title: 'Swift Oilfield Supply — Receiving Label',
      author: 'Swift Oilfield Supply',
    );
    await _appendDocPages(
      doc,
      pages: [data],
      customerLogoBytes: customerLogoBytes,
      painter: _drawReceivingPage,
      options: options,
    );
    return doc.save();
  }

  Future<void> _appendDocPages(
    pw.Document doc, {
    required List<ShippingLabelData> pages,
    required List<Uint8List> customerLogoBytes,
    required void Function(
      PdfGraphics c,
      _ResolvedFonts fonts,
      ShippingLabelData data,
      List<PdfImage> customerLogos,
      PdfImage? swiftLogo,
      PdfRenderOptions options,
    ) painter,
    PdfRenderOptions options = PdfRenderOptions.defaults,
  }) async {
    // Shipping / Receiving labels are designed for landscape Letter.
    final format = pageFormat;

    for (final pageData in pages) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            var fonts = _ResolvedFonts(
              oswald: oswald.getFont(context),
              oswaldMedium: oswaldMedium.getFont(context),
              oswaldBold: oswaldBold.getFont(context),
              calibri: calibri.getFont(context),
              calibriBold: calibriBold.getFont(context),
            );
            fonts = fonts.withBodyFont(
              options.bodyFont,
              helvetica: options.bodyFont == PdfBodyFont.helvetica
                  ? pw.Font.helvetica().getFont(context)
                  : null,
              helveticaBold: options.bodyFont == PdfBodyFont.helvetica
                  ? pw.Font.helveticaBold().getFont(context)
                  : null,
              montserrat: options.bodyFont == PdfBodyFont.montserrat
                  ? montserrat.getFont(context)
                  : null,
              montserratBold: options.bodyFont == PdfBodyFont.montserrat
                  ? montserratBold.getFont(context)
                  : null,
            );

            final customerLogos = <PdfImage>[];
            for (final bytes in customerLogoBytes.take(maxCustomerLogos)) {
              if (bytes.isNotEmpty) {
                // Size by visible ink bounds so padded square icons match
                // tight rectangular wordmarks at the shared Swift height.
                final normalized =
                    LogoImageProcessor.normalizeToVisibleContent(bytes);
                customerLogos.add(
                  PdfImage.file(context.document, bytes: normalized),
                );
              }
            }
            PdfImage? swiftLogo;
            if (swiftLogoBytes != null) {
              swiftLogo =
                  PdfImage.file(context.document, bytes: swiftLogoBytes!);
            }
            final logos = options.showCustomerLogos &&
                    options.logoPlacement != PdfLogoPlacement.hidden
                ? customerLogos
                : <PdfImage>[];

            return pw.CustomPaint(
              size: PdfPoint(format.width, format.height),
              painter: (PdfGraphics canvas, PdfPoint size) {
                if (options.isBoxSized) {
                  // 50% scale, anchored in the top-left quadrant of landscape Letter.
                  // PDF origin is bottom-left → translate up by half page height, then scale.
                  canvas.saveContext();
                  final box = Matrix4.identity()
                    ..translateByDouble(0, format.height / 2, 0, 1)
                    ..scaleByDouble(0.5, 0.5, 1, 1);
                  canvas.setTransform(box);
                  painter(canvas, fonts, pageData, logos, swiftLogo, options);
                  canvas.restoreContext();
                } else {
                  painter(canvas, fonts, pageData, logos, swiftLogo, options);
                }
              },
            );
          },
        ),
      );
    }
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
    PdfRenderOptions options,
  ) {
    final pageH = pageFormat.height;

    _bumper(c, pageH - my + 4);

    final footY = my + 6;
    // Clearance above footer for the piece-count band (tight — contact sits above).
    final pieceTop = footY + pieceBandRowH + 14;

    var y = _drawHeader(c, fonts, customerLogos, swiftLogo, options: options);
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
        final tw = stringWidth(f, line, fontSize);
        final tx = centered ? x + (w - tw) / 2 : x + 1;
        c.drawString(f, fontSize, line, tx, yy);
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

  /// Fixed Swift logo height (pt). Never scaled by customer logos or logoScale.
  static const customerLogoTargetH = 62.24;

  /// Keep logos clear of the orange header frames (band edges).
  static const customerLogoBandInset = 2.0;

  /// Horizontal gap between Logo 1 and Logo 2 (C/O).
  static const customerLogoGap = 10.0;

  /// Breathing gap between the customer-logo row and Swift (never overlap).
  static const customerLogoToSwiftGap = 12.0;

  /// Draw 1–2 customer logos at height [h], left-to-right in [availW].
  void _drawCustomerLogoRowAt(
    PdfGraphics c,
    List<PdfImage> valid,
    List<double> widths,
    double leftX,
    double bandBottom,
    double bandTop,
    double h,
    double availW,
    double gap,
  ) {
    final bandCenter = (bandTop + bandBottom) / 2;
    var y = bandCenter - h / 2;
    final minY = bandBottom + customerLogoBandInset;
    final maxY = bandTop - customerLogoBandInset - h;
    if (y < minY) y = minY;
    if (maxY >= minY && y > maxY) y = maxY;

    var x = leftX;
    final rightLimit = leftX + availW;
    for (var i = 0; i < valid.length; i++) {
      var w = widths[i];
      final remain = rightLimit - x;
      if (remain < 2) break;
      if (w > remain) w = remain;
      c.drawImage(valid[i], x, y, w, h);
      x += w + gap;
    }
  }

  /// Size customer logos to [targetH] (Swift's height). Shrink uniformly only
  /// when the row is wider than [availW] — and only as much as needed.
  void _drawCustomerLogosMatchingHeight(
    PdfGraphics c,
    List<PdfImage> logos,
    double leftX,
    double bandBottom,
    double bandTop,
    double targetH,
    double availW,
  ) {
    final valid = <PdfImage>[
      for (final l in logos)
        if (l.width > 0 && l.height > 0) l,
    ];
    if (valid.isEmpty || availW <= 0 || targetH <= 0) return;

    final bandInnerH =
        (bandTop - bandBottom - 2 * customerLogoBandInset).clamp(1.0, 10000.0);
    var h = targetH > bandInnerH ? bandInnerH : targetH;

    var widths = <double>[
      for (final l in valid) l.width.toDouble() / l.height.toDouble() * h,
    ];
    var combined = widths.fold<double>(0, (a, b) => a + b) +
        customerLogoGap * (valid.length - 1);

    // Shrink only if the row cannot fit — single or multiple.
    if (combined > availW && combined > 0) {
      final scale = availW / combined;
      h *= scale;
      widths = [for (final w in widths) w * scale];
    }

    _drawCustomerLogoRowAt(
      c,
      valid,
      widths,
      leftX,
      bandBottom,
      bandTop,
      h,
      availW,
      customerLogoGap,
    );
  }

  double _drawHeader(
    PdfGraphics c,
    _ResolvedFonts fonts,
    List<PdfImage> customerLogos,
    PdfImage? swiftLogo, {
    bool receivingChip = false,
    PdfRenderOptions options = PdfRenderOptions.defaults,
  }) {
    final pageH = pageFormat.height;
    final yTop = pageH - my - 14;
    final bandH = 0.92 * inch;
    final logoBottom = yTop - bandH;
    final airUnderLogos = receivingChip ? 0.36 * inch : 0.40 * inch;
    final ruleY = logoBottom - airUnderLogos;

    final logos = customerLogos.take(maxCustomerLogos).toList();
    final place = options.showCustomerLogos
        ? options.logoPlacement
        : PdfLogoPlacement.hidden;

    // --- Swift size is FIXED. Never depends on customer logos or logoScale. ---
    final swiftMaxW = colW * 0.95;
    final swiftMaxH = customerLogoTargetH; // locked constant (62.24 pt)
    double swiftW = 0;
    double swiftH = 0;
    if (swiftLogo != null) {
      final iw = swiftLogo.width.toDouble();
      final ih = swiftLogo.height.toDouble();
      if (iw > 0 && ih > 0) {
        final scale =
            (swiftMaxW / iw < swiftMaxH / ih) ? swiftMaxW / iw : swiftMaxH / ih;
        swiftW = iw * scale;
        swiftH = ih * scale;
      }
    }

    // Customer logos match Swift's height. logoScale only when Swift is absent.
    final customerTargetH = swiftH > 0
        ? swiftH
        : (customerLogoTargetH * options.logoScale.clamp(0.6, 1.5));

    if (place == PdfLogoPlacement.left && logos.isNotEmpty) {
      final swiftLeftX = mx + contentW - swiftW;
      final availForCustomer = swiftW > 0
          ? (swiftLeftX - customerLogoToSwiftGap - mx).clamp(0.0, contentW)
          : contentW;
      _drawCustomerLogosMatchingHeight(
        c,
        logos,
        mx,
        logoBottom,
        yTop,
        customerTargetH,
        availForCustomer,
      );
    } else if (place == PdfLogoPlacement.right && logos.isNotEmpty) {
      final swiftRightEdge = mx + swiftW;
      final startX = swiftW > 0
          ? swiftRightEdge + customerLogoToSwiftGap
          : mx + contentW * 0.58;
      final avail = (mx + contentW - startX).clamp(0.0, contentW);
      _drawCustomerLogosMatchingHeight(
        c,
        logos,
        startX,
        logoBottom,
        yTop,
        customerTargetH,
        avail,
      );
    } else if (logos.isEmpty && place != PdfLogoPlacement.belowSwift) {
      c
        ..setStrokeColor(ruleSoft)
        ..setLineWidth(0.7)
        ..drawRect(mx, logoBottom + 8, 120, bandH - 20)
        ..strokePath();
    }

    if (swiftLogo != null && swiftW > 0) {
      final drawX =
          place == PdfLogoPlacement.right ? mx : (mx + contentW - swiftW);
      final bandCenter = (yTop + logoBottom) / 2;
      var yLogoBottom = bandCenter - swiftH / 2;
      final minY = logoBottom + customerLogoBandInset;
      final maxY = yTop - customerLogoBandInset - swiftH;
      if (yLogoBottom < minY) yLogoBottom = minY;
      if (maxY >= minY && yLogoBottom > maxY) yLogoBottom = maxY;
      c.drawImage(swiftLogo, drawX, yLogoBottom, swiftW, swiftH);
    }

    if (place == PdfLogoPlacement.belowSwift && logos.isNotEmpty) {
      final belowTop = logoBottom - customerLogoBandInset;
      final belowBottom = logoBottom - customerTargetH - 4;
      _drawCustomerLogosMatchingHeight(
        c,
        logos,
        mx,
        belowBottom,
        belowTop,
        customerTargetH,
        contentW,
      );
    }

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
    bool showRule = true,
    bool centered = false,
    String? valueOverride,
  }) {
    _microLabel(c, fonts, x, y, label);
    y -= 3;
    final val = valueOverride ?? sample.get(key);
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
        centered: centered,
      );
    }
    if (showRule) {
      _hairline(c, x, y - vh - 1, colWidth);
    }
    return y - vh - 12;
  }

  void _drawReceivingPage(
    PdfGraphics c,
    _ResolvedFonts fonts,
    ShippingLabelData sample,
    List<PdfImage> customerLogos,
    PdfImage? swiftLogo,
    PdfRenderOptions options,
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
      options: options,
    );

    // Full-width vertical stack (Customer → Project → PO → Special Instructions
    // → Sales Order → PM). Body entries prefer 22 pt; Sales Order prefers 60 pt.
    // Values are centered; PM has no underline (clean space above received band).
    y = _fieldRow(
      c,
      fonts,
      y,
      'Customer',
      LabelFields.customer,
      mx,
      contentW,
      sample,
      hero: true,
      preferredSize: entryHero,
      centered: true,
    );
    y = _fieldRow(
      c,
      fonts,
      y,
      'Project',
      LabelFields.project,
      mx,
      contentW,
      sample,
      multiline: true,
      maxLines: 3,
      preferredSize: entryHero,
      centered: true,
    );
    y = _fieldRow(
      c,
      fonts,
      y,
      'PO Number',
      LabelFields.poNum,
      mx,
      contentW,
      sample,
      multiline: true,
      maxLines: 2,
      preferredSize: entryHero,
      centered: true,
    );
    y = _fieldRow(
      c,
      fonts,
      y,
      'Special Instructions',
      LabelFields.specialInstructions,
      mx,
      contentW,
      sample,
      multiline: true,
      maxLines: 2,
      preferredSize: entryHero,
      valueBgWhenNonEmpty: recvInstructionsAlert,
      centered: true,
    );
    y = _drawSalesOrderRow(
      c,
      fonts,
      y,
      mx,
      contentW,
      sample,
      pillBg: recvSoBg,
      preferredSize: entryRecvSo,
      minRowH: 48,
      centerPill: true,
    );
    _fieldRow(
      c,
      fonts,
      y,
      'PM',
      LabelFields.swiftContact,
      mx,
      contentW,
      sample,
      preferredSize: entryHero,
      centered: true,
      showRule: false,
    );

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

  /// Sales Order — preferred size [entrySo] (Shipping) / [entryRecvSo] (Receiving).
  double _drawSalesOrderRow(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    double x,
    double colWidth,
    ShippingLabelData sample, {
    PdfColor? pillBg,
    double? preferredSize,
    double minRowH = 28,
    bool centerPill = false,
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
    final pillX = centerPill ? x + (colWidth - pillW) / 2 : x;

    c.setFillColor(pillBg ?? soBg);
    _fillRRect(c, pillX, y - pillH, pillW, pillH, 8);

    if (val.isNotEmpty) {
      final textBoxH = size + 4;
      final textY = y - pillH + (pillH - textBoxH) / 2;
      _drawValue(
        c,
        fonts,
        val,
        pillX + padX,
        textY,
        pillW - 2 * padX,
        textBoxH,
        fontSize: size,
        font: fonts.calibriBold,
        centered: centerPill,
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
    _microLabel(c, fonts, rx, y, 'Ship To Name');
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
    // Fixed Delivery Address box (~3 lines at preferred size). Shrink type to
    // fit width/height instead of growing into sections below.
    final locMaxH = 3 * (entrySize + lineGap) + 8;
    var locSize = entrySize;
    while (locSize > entryMin && loc.isNotEmpty) {
      final need = fieldHeightFor(
        loc,
        fonts.calibriBold,
        size: locSize,
        maxLines: 12,
        minH: 22,
      );
      if (need <= locMaxH) break;
      locSize -= 0.5;
    }
    // Also shrink if any wrapped line still exceeds column width at this size
    // (fitWrappedSize covers width; height loop above covers overflow).
    locSize = fitWrappedSize(
      loc,
      colW - 4,
      fonts.calibriBold,
      preferred: locSize,
      maxLines: 12,
      minSize: entryMin,
    );
    final locH = locMaxH;
    _microLabel(c, fonts, rx, y, 'Delivery Address');
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
    return y - locH - 12;
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

    // Carrier sits under Project (left); Attn opens the right meta stack.
    // Freight + 3rd Party Billing share a half-row under Carrier.
    yL = _fieldRow(
      c,
      fonts,
      yL,
      'Carrier',
      LabelFields.carrier,
      lx,
      colW,
      sample,
    );
    yL = _drawFreightBillingHalfRow(c, fonts, yL, lx, colW, sample);

    final yR = _drawHero(c, fonts, y, sample);
    return (yL, yR);
  }

  double _drawFreightBillingHalfRow(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    double x,
    double colWidth,
    ShippingLabelData sample,
  ) {
    const gap = 10.0;
    final half = (colWidth - gap) / 2;
    final freight = BolFields.freightChargesDisplay(
      sample.get(BolFields.freightCharges),
    );
    final billing = sample.get(BolFields.thirdPartyBilling);
    final yLeft = _fieldRow(
      c,
      fonts,
      y,
      'Freight Charges',
      BolFields.freightCharges,
      x,
      half,
      sample,
      valueOverride: freight,
    );
    final yRight = _fieldRow(
      c,
      fonts,
      y,
      '3rd Party Billing',
      BolFields.thirdPartyBilling,
      x + half + gap,
      half,
      sample,
      valueOverride: billing,
    );
    return yLeft < yRight ? yLeft : yRight;
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

    // Tight vertical stack (same gap as PO → Project). Artificial "slot floors"
    // used to open a large empty band under Carrier and shove Contact into the
    // piece-count boxes — removed. Attn leads the right stack (Carrier moved left).
    var y = yRight;
    y = _fieldRow(c, fonts, y, 'Attn', LabelFields.attn, rx, colW, sample);
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
    y = _drawSalesOrderRow(
      c,
      fonts,
      y,
      rx,
      colW,
      sample,
      preferredSize: entrySo,
    );

    // Natural stack keeps Contact clear of the piece band (no downward shove).
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
    // Shrinks when PO / Project / Carrier / freight push yLeft down — absorbs
    // expansion without overflowing the piece band.
    final notesH = (notesTop - notesFloor).clamp(28.0, 10000.0);
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

  /// Piece-count / page-number digits (e.g. "2 of 28") — kept compact so the
  /// band does not collide with Swift Contact above.
  static const pieceCountSize = 26.0;
  static const pieceOfSize = 15.0;
  static const pieceBandPadV = 3.0;
  static const pieceBandBoxPadH = 8.0;
  /// Label strip above the digits + digit line-box + pads.
  static const pieceBandLabelStrip = 11.0;
  static const pieceBandValueH = pieceCountSize + 4.0;
  static const pieceBandRowH =
      pieceBandLabelStrip + pieceBandValueH + pieceBandPadV * 2 + 2.0;

  void _drawPieceBand(
    PdfGraphics c,
    _ResolvedFonts fonts,
    double y,
    ShippingLabelData sample,
  ) {
    const rowH = pieceBandRowH;
    const gap = 12.0;
    final half = (contentW - gap) / 2;

    double countBoxW(String val) {
      final measure = val.isNotEmpty ? val : '88';
      final tw = stringWidth(fonts.calibriBold, measure, pieceCountSize);
      final raw = tw + pieceBandBoxPadH * 2;
      // Prefer room for 3-digit totals; never exceed half the cell.
      final prefer = stringWidth(fonts.calibriBold, '888', pieceCountSize) +
          pieceBandBoxPadH * 2;
      final maxW = half * 0.38;
      final target = raw < prefer ? prefer : raw;
      return target > maxW ? maxW : target;
    }

    void cell(double x, String label, String prefix) {
      c.setFillColor(pieceFill);
      _fillRRect(c, x, y - rowH, half, rowH, 4);
      c
        ..setStrokeColor(ruleSoft)
        ..setLineWidth(0.6);
      _strokeRRect(c, x, y - rowH, half, rowH, 4);

      // Micro-label along the top edge so digits have full width below.
      c
        ..setFillColor(labelC)
        ..setFont(fonts.oswaldMedium, 7.5);
      var cx = x + 10;
      final labelY = y - 11;
      for (final ch in _chars(label.toUpperCase())) {
        c.drawString(fonts.oswaldMedium, 7.5, ch, cx, labelY);
        cx += stringWidth(fonts.oswaldMedium, ch, 7.5) + 0.7;
      }

      final numVal = sample.get('${prefix}_num');
      final ofVal = sample.get('${prefix}_of');

      final numBox = countBoxW(numVal);
      final ofBox = countBoxW(ofVal);
      const ofText = 'OF';
      final ofW =
          stringWidth(fonts.oswaldBold, ofText, pieceOfSize) + 20;
      final blockW = numBox + ofW + ofBox;
      final fx = x + (half - blockW) / 2;

      const valueH = pieceBandValueH;
      // Digit band sits under the label strip, vertically padded.
      final valueTop = y - pieceBandLabelStrip - pieceBandPadV;
      final valueY = valueTop - valueH;
      final cellMid = valueY + valueH / 2;
      final underlineY = valueY - 2;

      if (numVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          numVal,
          fx,
          valueY,
          numBox,
          valueH,
          fontSize: pieceCountSize,
          font: fonts.calibriBold,
          centered: true,
        );
      }
      _hairline(c, fx, underlineY, numBox);

      c
        ..setFillColor(swift)
        ..setFont(fonts.oswaldBold, pieceOfSize);
      final ofTw = stringWidth(fonts.oswaldBold, ofText, pieceOfSize);
      final ofY = cellMid - pieceOfSize / 2 + 1;
      c.drawString(
        fonts.oswaldBold,
        pieceOfSize,
        ofText,
        fx + numBox + ofW / 2 - ofTw / 2,
        ofY,
      );

      if (ofVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          ofVal,
          fx + numBox + ofW,
          valueY,
          ofBox,
          valueH,
          fontSize: pieceCountSize,
          font: fonts.calibriBold,
          centered: true,
        );
      }
      _hairline(c, fx + numBox + ofW, underlineY, ofBox);
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

  _ResolvedFonts withBodyFont(
    PdfBodyFont body, {
    PdfFont? helvetica,
    PdfFont? helveticaBold,
    PdfFont? montserrat,
    PdfFont? montserratBold,
  }) {
    switch (body) {
      case PdfBodyFont.brand:
        return this;
      case PdfBodyFont.calibri:
        return _ResolvedFonts(
          oswald: calibri,
          oswaldMedium: calibriBold,
          oswaldBold: calibriBold,
          calibri: calibri,
          calibriBold: calibriBold,
        );
      case PdfBodyFont.oswald:
        return _ResolvedFonts(
          oswald: oswald,
          oswaldMedium: oswaldMedium,
          oswaldBold: oswaldBold,
          calibri: oswald,
          calibriBold: oswaldBold,
        );
      case PdfBodyFont.helvetica:
        // Keep Oswald micro-labels; swap entry values to true PDF Helvetica.
        final h = helvetica ?? calibri;
        final hb = helveticaBold ?? calibriBold;
        return _ResolvedFonts(
          oswald: oswald,
          oswaldMedium: oswaldMedium,
          oswaldBold: oswaldBold,
          calibri: h,
          calibriBold: hb,
        );
      case PdfBodyFont.montserrat:
        // Geometric sans close to Proxima Nova for entry values.
        final m = montserrat ?? calibri;
        final mb = montserratBold ?? calibriBold;
        return _ResolvedFonts(
          oswald: oswald,
          oswaldMedium: oswaldMedium,
          oswaldBold: oswaldBold,
          calibri: m,
          calibriBold: mb,
        );
    }
  }
}
