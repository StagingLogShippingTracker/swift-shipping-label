import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/logo_image_process.dart';

void main() {
  test('removes white background and trims padding', () {
    final src = img.Image(width: 120, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      src,
      x1: 40,
      y1: 20,
      x2: 79,
      y2: 59,
      color: img.ColorRgba8(20, 80, 200, 255),
    );

    final input = Uint8List.fromList(img.encodePng(src));
    final out = LogoImageProcessor.process(input);
    final decoded = img.decodePng(out);
    expect(decoded, isNotNull);

    // Tight crop + small pad — much smaller than source canvas.
    expect(decoded!.width, lessThan(60));
    expect(decoded.height, lessThan(50));

    // Corners should be transparent after bg removal.
    expect(decoded.getPixel(0, 0).a.toInt(), lessThan(12));

    // Logo color survives near center.
    final cx = decoded.width ~/ 2;
    final cy = decoded.height ~/ 2;
    final center = decoded.getPixel(cx, cy);
    expect(center.b.toInt(), greaterThan(150));
    expect(center.a.toInt(), greaterThan(200));
  });

  test('trims empty alpha padding on already-transparent PNG', () {
    final src = img.Image(width: 100, height: 60, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 30,
      y1: 10,
      x2: 69,
      y2: 49,
      color: img.ColorRgba8(200, 40, 40, 255),
    );

    final input = Uint8List.fromList(img.encodePng(src));
    final out = LogoImageProcessor.process(input);
    final decoded = img.decodePng(out)!;

    expect(decoded.width, lessThan(50));
    expect(decoded.height, lessThan(50));
    expect(decoded.getPixel(0, 0).a.toInt(), lessThan(12));
  });

  test('preserves anti-aliased logo edge pixels', () {
    final src = img.Image(width: 80, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      src,
      x1: 30,
      y1: 30,
      x2: 49,
      y2: 49,
      color: img.ColorRgba8(10, 10, 10, 255),
    );
    for (var i = 0; i < 4; i++) {
      final a = 180 - i * 40;
      src.setPixelRgba(29 - i, 40, 10, 10, 10, a);
      src.setPixelRgba(50 + i, 40, 10, 10, 10, a);
    }

    final out = LogoImageProcessor.process(Uint8List.fromList(img.encodePng(src)));
    final decoded = img.decodePng(out)!;

    final coreX = decoded.width ~/ 2;
    final coreY = decoded.height ~/ 2;
    expect(decoded.getPixel(coreX, coreY).a.toInt(), greaterThan(200));
  });
}
