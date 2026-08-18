import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:swift_shipping_label/gemini_client.dart';
import 'package:swift_shipping_label/logo_image_process.dart';
import 'package:swift_shipping_label/restore_catalog.dart';

void main() {
  test('stripForeignMarks removes a corner watermark, keeps the logo', () {
    final src = img.Image(width: 200, height: 120, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 40,
      y1: 30,
      x2: 120,
      y2: 90,
      color: img.ColorRgba8(200, 40, 40, 255),
    );
    img.fillRect(
      src,
      x1: 180,
      y1: 100,
      x2: 198,
      y2: 118,
      color: img.ColorRgba8(30, 30, 30, 255),
    );

    LogoImageProcessor.stripForeignMarks(src);
    expect(src.getPixel(90, 60).a.toInt(), greaterThan(200));
    expect(src.getPixel(190, 110).a.toInt(), lessThan(20));
  });

  test('stripForeignMarks keeps a registered-mark next to the lockup', () {
    final src = img.Image(width: 200, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 20,
      y1: 20,
      x2: 140,
      y2: 60,
      color: img.ColorRgba8(20, 20, 20, 255),
    );
    img.fillRect(
      src,
      x1: 148,
      y1: 22,
      x2: 162,
      y2: 36,
      color: img.ColorRgba8(20, 20, 20, 255),
    );

    LogoImageProcessor.stripForeignMarks(src);
    expect(src.getPixel(80, 40).a.toInt(), greaterThan(200));
    expect(src.getPixel(155, 29).a.toInt(), greaterThan(200));
  });

  test('stripHaloFringe punches a white rim, keeps the brand fill', () {
    final src = img.Image(width: 80, height: 80, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 20,
      y1: 20,
      x2: 59,
      y2: 59,
      color: img.ColorRgba8(200, 40, 40, 255),
    );
    for (var x = 19; x <= 60; x++) {
      src.setPixelRgba(x, 19, 240, 240, 240, 255);
      src.setPixelRgba(x, 60, 240, 240, 240, 255);
    }
    for (var y = 19; y <= 60; y++) {
      src.setPixelRgba(19, y, 240, 240, 240, 255);
      src.setPixelRgba(60, y, 240, 240, 240, 255);
    }

    LogoImageProcessor.stripHaloFringe(src);
    expect(src.getPixel(40, 40).a.toInt(), greaterThan(200));
    expect(src.getPixel(40, 40).r.toInt(), greaterThan(150));
    expect(src.getPixel(19, 40).a.toInt(), lessThan(20));
  });

  test('restore prompt bans Gemini watermarks and extra wordmarks', () {
    final prompt = GeminiClient.restorePrompt(
      addenda: RestoreCatalog().winningAddenda(),
    );
    expect(prompt.toLowerCase(), contains('watermark'));
    expect(prompt.toLowerCase(), contains('gemini'));
    expect(prompt.toLowerCase(), contains('enhance'));
    expect(prompt.toLowerCase(), contains('blotch'));
    expect(prompt.toLowerCase(), contains('stair'));
    expect(prompt.toLowerCase(), contains('over-sharpen'));
  });

  test('catalog records pristine restores and replays addenda', () {
    final cat = RestoreCatalog();
    cat.record(
      sourceName: 'Arc Resources LTD.png',
      grade: RestoreGrade.pristine,
      used: ['gemini_primary', 'no_watermark', 'plate_knockout'],
      note: 'Knock out opaque white plates after Gemini.',
    );
    expect(cat.techniques['gemini_primary']!.wins, greaterThan(0));
    expect(
      cat.winningAddenda().any((e) => e.toLowerCase().contains('watermark')),
      isTrue,
    );
    expect(cat.history.last.grade, RestoreGrade.pristine);
    final roundTrip = RestoreCatalog.fromJson(cat.toJson());
    expect(roundTrip.history, isNotEmpty);
    expect(roundTrip.techniques['no_watermark']!.uses, greaterThan(0));
  });

  test('catalog learns from a scored pass and replays it', () {
    final cat = RestoreCatalog();
    final q = RestoreQuality(
      geminiOk: true,
      height: 3000,
      opaqueFrac: 0.5,
      whitePlateFrac: 0.04,
      aspectDrift: 0.22,
      hadCornerMark: false,
    );
    cat.record(
      sourceName: 'Trialta Projects.png',
      grade: q.grade,
      used: ['gemini_primary', 'studio_finish', 'solid_fills'],
      notes: RestoreCatalog.lessonsFrom(q),
    );
    final replay = cat.winningAddenda().join('\n').toLowerCase();
    expect(replay, contains('aspect'));
    expect(replay, contains('enhance'));
    expect(cat.techniques['studio_finish']!.wins, greaterThan(0));
  });

  test('quality grades a clean tall restore as pristine', () {
    final q = RestoreQuality(
      geminiOk: true,
      height: 3000,
      opaqueFrac: 0.52,
      whitePlateFrac: 0.0,
      aspectDrift: 0.04,
      hadCornerMark: false,
    );
    expect(q.grade, RestoreGrade.pristine);
  });

  test('quality measure flags an opaque white plate', () {
    final src = img.Image(width: 80, height: 40, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      src,
      x1: 8,
      y1: 8,
      x2: 70,
      y2: 32,
      color: img.ColorRgba8(180, 20, 20, 255),
    );
    final dst = img.Image(width: 200, height: 100, numChannels: 4);
    img.fill(dst, color: img.ColorRgba8(255, 255, 255, 255));
    img.fillRect(
      dst,
      x1: 20,
      y1: 20,
      x2: 180,
      y2: 80,
      color: img.ColorRgba8(180, 20, 20, 255),
    );
    final q = RestoreQuality.measure(
      geminiOk: true,
      source: Uint8List.fromList(img.encodePng(src)),
      restored: Uint8List.fromList(img.encodePng(dst)),
      hadCornerMark: false,
    );
    expect(q.whitePlateFrac, greaterThan(0.18));
    expect(q.grade, RestoreGrade.fail);
  });
}
