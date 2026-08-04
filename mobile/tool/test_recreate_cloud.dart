// Standalone sanity test for LogoRecreateCloud. Runs outside Flutter.
//
//   dart run tool/test_recreate_cloud.dart ..\customer_logos\EPCOR.png _epcor_dart_out.png
//
// Prints palette + timing and writes the recreated PNG (and SVG when
// available) next to the output PNG so we can eyeball parity with the
// curl-driven test.

import 'dart:io';

import 'package:swift_shipping_label/logo_recreate_cloud.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: test_recreate_cloud.dart <input.png> <output.png>');
    exit(64);
  }
  final input = File(args[0]);
  if (!await input.exists()) {
    stderr.writeln('input not found: ${input.path}');
    exit(66);
  }
  final result = await LogoRecreateCloud.run(
    input,
    onLog: (m) => stdout.writeln('[log] $m'),
  );
  final outPng = File(args[1]);
  await outPng.writeAsBytes(result.pngBytes, flush: true);
  stdout.writeln(
    'ok: sections=${result.sectionCount} '
    'palette=${result.paletteHex.join(",")} '
    'bg=${result.backgroundStripped} '
    '${result.elapsed.inMilliseconds}ms '
    '-> ${outPng.path}',
  );
  if (result.svgBytes != null) {
    final outSvg = File('${outPng.path}.svg');
    await outSvg.writeAsBytes(result.svgBytes!, flush: true);
    stdout.writeln('svg: ${outSvg.path}');
  }
}
