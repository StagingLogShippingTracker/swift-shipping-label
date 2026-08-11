import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_image_process.dart';

void main() {
  test('prepareSignatureInk knocks out white and crops to ink', () {
    final canvas = img.Image(width: 200, height: 80, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
    // Dark stroke in the middle.
    for (var x = 40; x < 160; x++) {
      for (var y = 30; y < 50; y++) {
        canvas.setPixelRgba(x, y, 20, 20, 20, 255);
      }
    }
    final png = Uint8List.fromList(img.encodePng(canvas));
    final out = LogoImageProcessor.prepareSignatureInk(png);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, lessThan(200));
    expect(decoded.height, lessThan(80));
    // Corners of output should be transparent.
    expect(decoded.getPixel(0, 0).a.toInt(), lessThan(20));
  });
}
