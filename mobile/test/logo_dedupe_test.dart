import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:swift_shipping_label/app_storage.dart';
import 'package:swift_shipping_label/label_data.dart';
import 'package:swift_shipping_label/logo_dedupe.dart';
import 'package:swift_shipping_label/logo_import_options.dart';

Uint8List _png({
  required int w,
  required int h,
  required img.ColorRgba8 fill,
  img.ColorRgba8? mark,
  int markPad = 8,
}) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: fill);
  if (mark != null) {
    img.fillRect(
      im,
      x1: markPad,
      y1: markPad,
      x2: w - markPad - 1,
      y2: h - markPad - 1,
      color: mark,
    );
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('stemsRelated ignores (n), copy, restored suffixes', () {
    expect(
      LogoDedupe.stemsRelated('Arc Resources LTD.png', 'arc resources.png'),
      isTrue,
    );
    expect(
      LogoDedupe.stemsRelated('trialta.png', 'trialta (3).png'),
      isTrue,
    );
    expect(
      LogoDedupe.stemsRelated('ALCO ENERGY SOLUTIONS LP.png', 'ALCO ENERGY SOLUTIONS LP (2).png'),
      isTrue,
    );
    expect(
      LogoDedupe.stemsRelated('ARJAE.png', 'Propak-Energy-Services-Logo.png'),
      isFalse,
    );
    expect(
      LogoDedupe.stemsRelated(
        'trialta.png',
        'trialta _3__restored.png',
      ),
      isTrue,
    );
  });

  test('visual scan matches same mark, rejects different mark', () {
    final redA = _png(
      w: 80,
      h: 80,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(180, 30, 40, 255),
    );
    final redB = _png(
      w: 80,
      h: 80,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(180, 30, 40, 255),
    );
    final blue = _png(
      w: 160,
      h: 40,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(20, 40, 180, 255),
    );
    final fa = LogoDedupe.fingerprint(redA)!;
    final fb = LogoDedupe.fingerprint(redB)!;
    final fc = LogoDedupe.fingerprint(blue)!;
    expect(LogoDedupe.isVisualMatch(fa, fb), isTrue);
    expect(LogoDedupe.isVisualMatch(fa, fc), isFalse);
  });

  test('import reuses existing file; different mark gets stem(1).png', () async {
    final tmp = await Directory.systemTemp.createTemp('logo_dedupe_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = AppStorage.forTesting(tmp);
    await store.logosDir.create(recursive: true);

    final red = _png(
      w: 90,
      h: 90,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(180, 30, 40, 255),
    );
    final first = await store.importLogoBytes(
      red,
      preferredName: 'image1.png',
      options: LogoImportOptions.standard(removeBackground: false),
    );
    expect(p.basename(first.file.path), 'image1.png');
    expect(first.reused, isFalse);

    final again = await store.importLogoBytes(
      red,
      preferredName: 'image1.png',
      options: LogoImportOptions.standard(removeBackground: false),
    );
    expect(again.reused, isTrue);
    expect(p.equals(again.file.path, first.file.path), isTrue);
    expect(
      store.listLogos().where((f) => p.basename(f.path).startsWith('image1')).length,
      1,
    );

    final blue = _png(
      w: 160,
      h: 48,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(20, 50, 190, 255),
    );
    final other = await store.importLogoBytes(
      blue,
      preferredName: 'image1.png',
      options: LogoImportOptions.standard(removeBackground: false),
    );
    expect(other.reused, isFalse);
    expect(p.basename(other.file.path), 'image1(1).png');
  });

  test('library cleanup keeps one file per visual cluster', () async {
    final tmp = await Directory.systemTemp.createTemp('logo_clean_');
    addTearDown(() => tmp.delete(recursive: true));
    final dir = Directory(p.join(tmp.path, 'customer_logos'));
    await dir.create(recursive: true);

    final mark = _png(
      w: 80,
      h: 80,
      fill: img.ColorRgba8(255, 255, 255, 255),
      mark: img.ColorRgba8(10, 120, 40, 255),
    );
    await File(p.join(dir.path, 'trialta.png')).writeAsBytes(mark);
    await File(p.join(dir.path, 'trialta (2).png')).writeAsBytes(mark);
    await File(p.join(dir.path, 'trialta (3).png')).writeAsBytes(mark);

    final store = AppStorage.forTesting(tmp);
    store.presets['shipping::Trialta'] = CustomerPreset(
      name: 'Trialta',
      kind: LabelKind.shipping,
      fields: const {},
      logoFileNames: const ['trialta (2).png'],
    );
    final report = await store.dedupeStoredLogos();
    expect(report.deleted, 2);
    expect(store.listLogos().map((f) => p.basename(f.path)).toList(), ['trialta.png']);
    expect(store.presets['shipping::Trialta']!.logoFileNames, ['trialta.png']);
  });
}
