import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_crop_geometry.dart';

void main() {
  test('containImageRect letterboxes wide image', () {
    const container = Size(400, 200);
    const image = Size(800, 200);
    final rect = LogoCropGeometry.containImageRect(container, image);
    expect(rect.width, 400);
    expect(rect.height, 100);
    expect(rect.top, 50);
    expect(rect.left, 0);
  });

  test('containImageRect letterboxes tall image', () {
    const container = Size(400, 200);
    const image = Size(200, 400);
    final rect = LogoCropGeometry.containImageRect(container, image);
    expect(rect.height, 200);
    expect(rect.width, 100);
    expect(rect.left, 150);
    expect(rect.top, 0);
  });

  test('normalized round-trip through display coords', () {
    const container = Size(480, 220);
    const image = Size(1000, 500);
    const norm = Rect.fromLTWH(0.25, 0.1, 0.5, 0.8);

    final display = LogoCropGeometry.normalizedToDisplay(norm, container, image);
    final back = LogoCropGeometry.displayToNormalized(
      display.topLeft,
      container,
      image,
    );
    expect(back.dx, closeTo(0.25, 0.001));
    expect(back.dy, closeTo(0.1, 0.001));
  });

  test('clampNormalized preserves size when shifted against edge', () {
    const start = Rect.fromLTWH(0.7, 0.2, 0.25, 0.5);
    final shifted = Rect.fromLTWH(0.85, 0.2, 0.25, 0.5);
    final clamped = LogoCropGeometry.clampNormalized(shifted);
    expect(clamped.right, 1.0);
    expect(clamped.width, closeTo(start.width, 0.001));
  });
}
