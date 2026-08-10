import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bulk/bulk_label_models.dart';

/// Avery 5163 Propak stickers — layout mirrors the Word label template:
/// centered Propak logo, then PO# / CPO LINE # / TAG#|PART# field rows.
class BulkLabelPdf {
  BulkLabelPdf._({
    required this.calibri,
    required this.calibriBold,
    required this.propakLogo,
  });

  final pw.Font calibri;
  final pw.Font calibriBold;
  final pw.ImageProvider? propakLogo;

  static BulkLabelPdf? _instance;

  // Avery 5163 / Propak Word template geometry (inches → PDF points).
  static const inch = PdfPageFormat.inch;
  static final pageFormat = PdfPageFormat.letter;
  static final labelW = 4.0 * inch;
  static final labelH = 2.0 * inch;
  static final topMargin = 0.5 * inch;
  static final leftMargin = 0.156 * inch;
  static final hPitch = 4.1875 * inch; // 4" label + 0.1875" gutter
  static final vPitch = 2.0 * inch;
  static const cols = 2;
  static const rows = 5;
  static const perSheet = cols * rows; // 10

  /// Propak logo size from the Word template (~1.95″ × 0.46″).
  static final logoW = 1.95 * inch;
  static final logoH = 0.46 * inch;

  /// Template uses 14pt (w:sz=28 half-points).
  static const fieldSize = 14.0;

  static Future<BulkLabelPdf> load() async {
    if (_instance != null) return _instance!;
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));

    pw.ImageProvider? logo;
    try {
      final data = await rootBundle.load('assets/images/propak_logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    _instance = BulkLabelPdf._(
      calibri: await font('assets/fonts/Calibri.ttf'),
      calibriBold: await font('assets/fonts/Calibri-Bold.ttf'),
      propakLogo: logo,
    );
    return _instance!;
  }

  /// Build a multi-page Avery 5163 PDF for [labels] (already qty-expanded).
  Future<Uint8List> build(List<BulkLabelInstance> labels) async {
    final doc = pw.Document();
    if (labels.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(
            child: pw.Text(
              'No labels to print',
              style: pw.TextStyle(font: calibri, fontSize: 14),
            ),
          ),
        ),
      );
      return doc.save();
    }

    final pages = (labels.length + perSheet - 1) ~/ perSheet;
    for (var p = 0; p < pages; p++) {
      final start = p * perSheet;
      final slice = labels.sublist(
        start,
        math.min(start + perSheet, labels.length),
      );
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              for (var i = 0; i < slice.length; i++)
                pw.Positioned(
                  left: leftMargin + (i % cols) * hPitch,
                  top: topMargin + (i ~/ cols) * vPitch,
                  child: pw.SizedBox(
                    width: labelW,
                    height: labelH,
                    child: _labelCell(slice[i]),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  pw.Widget _labelCell(BulkLabelInstance label) {
    // Match Word template: ~0.1" cell indent, logo centered, fields in 2 cols.
    const padX = 7.2; // ~144 twips
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(padX, 4, padX, 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: propakLogo != null
                ? pw.SizedBox(
                    width: logoW,
                    height: logoH,
                    child: pw.Image(propakLogo!, fit: pw.BoxFit.contain),
                  )
                : pw.Text(
                    'PROPAK',
                    style: pw.TextStyle(
                      font: calibriBold,
                      fontSize: 16,
                      color: PdfColor.fromInt(0xFF1E4B8E),
                    ),
                  ),
          ),
          pw.SizedBox(height: 6),
          _fieldRow('PO#', label.poNumber),
          pw.SizedBox(height: 2),
          _fieldRow('CPO LINE #', label.cpo),
          pw.SizedBox(height: 2),
          _fieldRow(label.idFieldLabel, label.tagOrPart),
        ],
      ),
    );
  }

  /// Word template nested table: italic right-aligned label | bold value.
  pw.Widget _fieldRow(String key, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 1.97 * inch,
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              key,
              style: pw.TextStyle(
                font: calibri,
                fontSize: fieldSize,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.black,
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              font: calibriBold,
              fontSize: fieldSize,
              color: PdfColors.black,
            ),
          ),
        ),
      ],
    );
  }
}
