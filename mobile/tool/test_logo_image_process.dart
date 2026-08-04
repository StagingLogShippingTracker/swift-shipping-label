// Standalone sanity test for LogoImageProcessor (non-recreate path).
//
//   dart run tool/test_logo_image_process.dart ../customer_logos/EPCOR.png _epcor_processed.png

import 'dart:io';

import 'package:swift_shipping_label/logo_image_process.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: test_logo_image_process.dart <in.png> <out.png>');
    exit(64);
  }
  final input = File(args[0]);
  if (!await input.exists()) {
    stderr.writeln('input not found: ${input.path}');
    exit(66);
  }
  final raw = await input.readAsBytes();
  final processed = LogoImageProcessor.process(raw);
  await File(args[1]).writeAsBytes(processed, flush: true);
  stdout.writeln('in=${raw.length} out=${processed.length} '
      'in_bytes=${raw.length} out_bytes=${processed.length} '
      '-> ${args[1]}');
}
