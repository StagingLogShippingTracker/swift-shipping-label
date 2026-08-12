import 'dart:html' as html;
import 'dart:typed_data';

/// Open generated PDF bytes in a new browser tab.
void openPdfInBrowser(Uint8List bytes, {String filename = 'document.pdf'}) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(minutes: 2), () {
    html.Url.revokeObjectUrl(url);
  });
}
