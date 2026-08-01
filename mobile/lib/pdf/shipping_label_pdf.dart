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

  static const swift = PdfColor.fromInt(0xFFD94B2B);
  static const black = PdfColor.fromInt(0xFF111111);
  static const labelC = PdfColor.fromInt(0xFF6A6A6A);
  static const rule = PdfColor.fromInt(0xFFC8C8C8);
  static const ruleSoft = PdfColor.fromInt(0xFFE2E2E2);
  static const notesBg = PdfColor.fromInt(0xFFF7F0D8);
  static const pieceFill = PdfColor.fromInt(0xFFF7F7F7);

  static final pageFormat = PdfPageFormat.letter.landscape;
  static const inch = PdfPageFormat.inch;
  static final mx = 0.52 * inch;
  static final my = 0.48 * inch;
  static final contentW = pageFormat.width - 2 * mx;
  static const gutter = 32.0;
  static final colW = (contentW - gutter) / 2;

  static const entrySize = 9.0;
  static const entryHero = 15.0;
  static const entryNotes = 9.0;
  static const lineGap = 2.5;
  static const wrapMaxLines = 2;

  static ShippingLabelPdf? _instance;

  static Future<ShippingLabelPdf> load() async {
    if (_instance != null) return _instance!;
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/swift_supply_logo.png');
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

  double fieldHeightFor(
    String text,
    PdfFont entryFont, {
    double colWidth = 0,
    double size = entrySize,
    int maxLines = wrapMaxLines,
    double pad = 7,
    double minH = 16,
  }) {
    final w = colWidth <= 0 ? colW : colWidth;
    final lines = wrapLines(text, w - 4, entryFont, size);
    final n = (lines.isEmpty ? 1 : lines.length).clamp(1, maxLines);
    final h = n * (size + lineGap) + pad;
    return h < minH ? minH : h.toDouble();
  }

  Future<Uint8List> build({
    required ShippingLabelData data,
    Uint8List? customerLogoBytes,
  }) async {
    final doc = pw.Document(
      title: 'Swift Oilfield Supply — Shipping Label',
      author: 'Swift Oilfield Supply',
    );

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

          PdfImage? customerLogo;
          if (customerLogoBytes != null && customerLogoBytes.isNotEmpty) {
            customerLogo = PdfImage.file(
              context.document,
              bytes: customerLogoBytes,
            );
          }
          PdfImage? swiftLogo;
          if (swiftLogoBytes != null) {
            swiftLogo = PdfImage.file(context.document, bytes: swiftLogoBytes!);
          }

          return pw.CustomPaint(
            size: PdfPoint(pageFormat.width, pageFormat.height),
            painter: (PdfGraphics canvas, PdfPoint size) {
              _drawPage(canvas, fonts, data, customerLogo, swiftLogo);
            },
          );
        },
      ),
    );

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
    PdfImage? customerLogo,
    PdfImage? swiftLogo,
  ) {
    final pageH = pageFormat.height;

    _bumper(c, pageH - my + 4);

    final footY = my + 6;
    final pieceTop = footY + 70;

    var y = _drawHeader(c, fonts, customerLogo, swiftLogo);
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
  }) {
    if (text.isEmpty) return;
    final f = font ?? fonts.calibri;
    c
      ..setFillColor(black)
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
      c.drawString(f, fontSize, text, x + 1, y + (h - fontSize) / 2 + 1);
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

  double _drawHeader(
    PdfGraphics c,
    _ResolvedFonts fonts,
    PdfImage? customerLogo,
    PdfImage? swiftLogo,
  ) {
    final pageH = pageFormat.height;
    final yTop = pageH - my - 14;
    final bandH = 0.92 * inch;
    final logoBottom = yTop - bandH;

    if (customerLogo != null) {
      _drawImageFit(
        c,
        customerLogo,
        mx,
        logoBottom + 10,
        colW * 0.7,
        bandH - 18,
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

    if (swiftLogo != null) {
      _drawImageFit(
        c,
        swiftLogo,
        mx + contentW,
        logoBottom + 2,
        colW * 0.95,
        bandH - 4,
        right: true,
      );
    }

    final airUnderLogos = 0.40 * inch;
    final ruleY = logoBottom - airUnderLogos;
    c.setFillColor(swift);
    _fillRRect(c, mx, ruleY - 0.5, contentW, 2.5, 1.0);
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
    double valueH = 18,
    double valueSize = entrySize,
    PdfFont? valueFont,
    bool multiline = false,
  }) {
    _microLabel(c, fonts, x, y, label);
    y -= 3;
    final val = sample.get(key);
    if (val.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        val,
        x,
        y - valueH,
        colWidth,
        valueH,
        fontSize: valueSize,
        font: valueFont ?? fonts.calibri,
        multiline: multiline,
      );
    }
    _hairline(c, x, y - valueH - 1, colWidth);
    return y - valueH - 12;
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
    const heroH = 28.0;
    final ship = sample.get(LabelFields.shipTo);
    if (ship.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        ship,
        rx,
        y - heroH,
        colW,
        heroH,
        fontSize: entryHero,
        font: fonts.calibriBold,
      );
    }
    c
      ..setStrokeColor(black)
      ..setLineWidth(1.0)
      ..drawLine(rx, y - heroH - 2, rx + colW, y - heroH - 2)
      ..strokePath();
    y -= heroH + 12;

    _microLabel(c, fonts, rx, y, 'Location');
    y -= 3;
    const locH = 24.0;
    final loc = sample.get(LabelFields.location);
    if (loc.isNotEmpty) {
      _drawValue(c, fonts, loc, rx, y - locH, colW, locH, multiline: true);
    }
    _hairline(c, rx, y - locH - 1, colW);
    y -= locH + 12;

    _microLabel(c, fonts, rx, y, 'Attn');
    y -= 3;
    const attnH = 18.0;
    final attn = sample.get(LabelFields.attn);
    if (attn.isNotEmpty) {
      _drawValue(c, fonts, attn, rx, y - attnH, colW, attnH);
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

    var yL = _fieldRow(
      c,
      fonts,
      y,
      'Customer',
      LabelFields.customer,
      lx,
      colW,
      sample,
      valueH: 18,
    );

    final poH = fieldHeightFor(sample.get(LabelFields.poNum), fonts.calibri);
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
      multiline: true,
    );

    final projH = fieldHeightFor(sample.get(LabelFields.project), fonts.calibri);
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

    final meta = <(String, String, double, double)>[
      ('Carrier', LabelFields.carrier, 18, entrySize),
      ('Swift Packing Slip No.', LabelFields.packingSlip, 18, entrySize),
      ('Swift Sales Order No.', LabelFields.salesOrder, 18, entrySize),
      ('Swift Contact', LabelFields.swiftContact, 18, entrySize),
    ];
    final usable = (yRight - (bandBottom + 20)).clamp(90.0, 10000.0);
    final slot = usable / meta.length;
    var y = yRight;
    for (final m in meta) {
      _fieldRow(
        c,
        fonts,
        y,
        m.$1,
        m.$2,
        rx,
        colW,
        sample,
        valueH: m.$3,
        valueSize: m.$4,
      );
      y -= slot;
    }

    _microLabel(c, fonts, lx, yLeft, 'Special Instructions');
    final notesTop = yLeft - 4;
    final notesFloor = bandBottom + 20;
    final notesH = (notesTop - notesFloor).clamp(48.0, 10000.0);
    c.setFillColor(notesBg);
    _fillRect(c, lx, notesTop - notesH, colW, notesH);
    c.setFillColor(swift);
    _fillRect(c, lx, notesTop - notesH, 3.5, notesH);

    final notes = sample.get(LabelFields.specialInstructions);
    if (notes.isNotEmpty) {
      _drawValue(
        c,
        fonts,
        notes,
        lx + 10,
        notesTop - notesH + 4,
        colW - 14,
        notesH - 8,
        fontSize: entryNotes,
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
      final midY = y - rowH / 2 - 2.5;
      for (final ch in _chars(label.toUpperCase())) {
        c.drawString(fonts.oswaldMedium, 7.5, ch, cx, midY);
        cx += stringWidth(fonts.oswaldMedium, ch, 7.5) + 0.7;
      }

      const box = 34.0;
      const ofW = 28.0;
      final fx = x + half - 12 - box * 2 - ofW;

      final numVal = sample.get('${prefix}_num');
      final ofVal = sample.get('${prefix}_of');

      if (numVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          numVal,
          fx,
          y - rowH + 7,
          box,
          24,
          fontSize: entrySize + 2,
          font: fonts.calibriBold,
        );
      }
      _hairline(c, fx, y - rowH + 6, box);

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
        midY,
      );

      if (ofVal.isNotEmpty) {
        _drawValue(
          c,
          fonts,
          ofVal,
          fx + box + ofW,
          y - rowH + 7,
          box,
          24,
          fontSize: entrySize + 2,
          font: fonts.calibriBold,
        );
      }
      _hairline(c, fx + box + ofW, y - rowH + 6, box);
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
