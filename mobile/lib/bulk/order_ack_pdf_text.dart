import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'bulk_label_models.dart';
import 'order_ack_parser.dart';

bool _pdfrxReady = false;

Future<void> ensurePdfTextRuntime() async {
  if (_pdfrxReady) return;
  await pdfrxFlutterInitialize();
  _pdfrxReady = true;
}

/// Extract plain text from an Order Acknowledgement PDF via PDFium (pdfrx).
Future<String> extractOrderAckPdfText(Uint8List bytes) async {
  await ensurePdfTextRuntime();
  final doc = await PdfDocument.openData(bytes);
  try {
    final buf = StringBuffer();
    for (final page in doc.pages) {
      final raw = await page.loadText();
      final pageText = raw?.fullText ?? '';
      if (pageText.trim().isEmpty) continue;
      buf.writeln(pageText);
      buf.writeln();
    }
    return buf.toString();
  } finally {
    await doc.dispose();
  }
}

Future<OrderAckParseResult> parseOrderAckPdf(
  Uint8List bytes, {
  String sourceFileName = '',
}) async {
  final text = await extractOrderAckPdfText(bytes);
  return const OrderAckParser().parseText(
    text,
    sourceFileName: sourceFileName,
  );
}
