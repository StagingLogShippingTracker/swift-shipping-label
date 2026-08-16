import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_image_process.dart';

void main() {
  test('normalizeToVisibleContent crops transparent padding', () {
    // 100×100 canvas with a 40×40 opaque square in the center.
    final canvas = img.Image(width: 100, height: 100, numChannels: 4);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 100; x++) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    for (var y = 30; y < 70; y++) {
      for (var x = 30; x < 70; x++) {
        canvas.setPixelRgba(x, y, 200, 40, 40, 255);
      }
    }
    // Faint shadow fringe that used to block whole-row peeling.
    canvas.setPixelRgba(20, 50, 0, 0, 0, 20);
    canvas.setPixelRgba(80, 50, 0, 0, 0, 20);

    final raw = Uint8List.fromList(img.encodePng(canvas));
    final out = LogoImageProcessor.normalizeToVisibleContent(raw);
    final decoded = img.decodeImage(out)!;

    // Cropped + tiny pad — much smaller than 100×100, roughly square.
    expect(decoded.width, lessThan(60));
    expect(decoded.height, lessThan(60));
    expect(decoded.width, greaterThan(38));
    expect(decoded.height, greaterThan(38));
    expect(decoded.height, lessThan(48));
    final aspect = decoded.width / decoded.height;
    expect(aspect, closeTo(1.0, 0.25));
  });
}
