import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/logo_ink_fit.dart';
import 'package:swift_shipping_label/logo_image_process.dart';
import 'package:swift_shipping_label/pdf/shipping_label_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnose bird logo ink + receiving PDF', () async {
    final root = Directory.current.parent;
    final src = File('${root.path}/customer_logos/bird_source.png');
    expect(src.existsSync(), isTrue, reason: src.path);
    final outDir = Directory('${root.path}/filled/bird_diag');
    await outDir.create(recursive: true);

    final bytes = await src.readAsBytes();
    final decoded = img.decodeImage(bytes)!;
    // ignore: avoid_print
    print('source ${decoded.width}x${decoded.height}');

    final normalized = LogoImageProcessor.normalizeToVisibleContent(bytes);
    await File('${outDir.path}/bird_normalized.png').writeAsBytes(normalized);
    final nImg = img.decodeImage(normalized)!;
    // ignore: avoid_print
    print('normalized ${nImg.width}x${nImg.height}');

    final prepared = LogoInkFit.prepare(bytes);
    await File('${outDir.path}/bird_prepared.png').writeAsBytes(prepared.png);
    final ink = prepared.ink;
    // ignore: avoid_print
    print(
      'ink canvas=${ink.canvasW}x${ink.canvasH} '
      'box=(${ink.left},${ink.top}) ${ink.width}x${ink.height} '
      'aspect=${(ink.width / ink.height).toStringAsFixed(3)}',
    );
    const targetH = ShippingLabelPdf.customerLogoTargetH;
    // ignore: avoid_print
    print(
      'drawW=${ink.drawWidth(targetH).toStringAsFixed(1)} '
      'drawH=${ink.drawHeight(targetH).toStringAsFixed(1)}',
    );

    var orange = 0, green = 0, other = 0, clear = 0;
    final pImg = img.decodeImage(prepared.png)!;
    for (var y = 0; y < pImg.height; y++) {
      for (var x = 0; x < pImg.width; x++) {
        final p = pImg.getPixel(x, y);
        if (p.a.toInt() < 40) {
          clear++;
          continue;
        }
        final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final sat = [r, g, b].reduce((a, b) => a > b ? a : b) -
            [r, g, b].reduce((a, b) => a < b ? a : b);
        if (r > 180 && g < 140 && b < 100 && sat > 40) {
          orange++;
        } else if (g >= r && g >= b && g > 30) {
          green++;
        } else {
          other++;
        }
      }
    }
    // ignore: avoid_print
    print('prepared orange=$orange green=$green other=$other clear=$clear');

    final pdf = await ShippingLabelPdf.load();
    final data = ShippingLabelData.receivingSample.copy()
      ..set(LabelFields.customer, 'bird');
    final pdfBytes = await pdf.buildReceiving(
      data: data,
      customerLogoBytes: [bytes],
    );
    await File('${outDir.path}/receiving_bird.pdf').writeAsBytes(pdfBytes);
    // ignore: avoid_print
    print('wrote receiving_bird.pdf ${pdfBytes.length}');
    expect(green, greaterThan(orange));
  });
}
