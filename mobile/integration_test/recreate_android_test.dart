/// End-to-end Android proof that the Recreate cloud pipeline works
/// against the live Supabase Edge Function from a real device / emulator.
///
/// Run with:
///   flutter test integration_test/recreate_android_test.dart \
///       -d emulator-5554
///
/// Preconditions:
///   adb push customer_logos/Mastec.png \
///     /sdcard/Android/data/com.swiftoilfield.swift_shipping_label/files/test_mastec.png
///   adb push customer_logos/EPCOR.png \
///     /sdcard/Android/data/com.swiftoilfield.swift_shipping_label/files/test_epcor.png
///
/// The test writes recreated PNG/SVG outputs alongside the inputs so
/// they can be pulled back to the host for visual verification.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:swift_shipping_label/logo_recreate_cloud.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<Directory> testDir() async {
    // /sdcard/Android/data/<pkg>/files — no perms required, pushable via adb.
    final ext = await getExternalStorageDirectory();
    if (ext == null) {
      throw StateError('No external storage on this device');
    }
    await ext.create(recursive: true);
    return ext;
  }

  Future<void> runOne(String name) async {
    final dir = await testDir();
    final input = File(p.join(dir.path, 'test_$name.png'));
    final okExists = await input.exists();
    // ignore: avoid_print
    print('[recreate-test] input=${input.path} exists=$okExists '
        'size=${okExists ? await input.length() : 0}');
    expect(okExists, isTrue,
        reason: 'Push input PNG to ${input.path} before running');

    final bytes = await input.readAsBytes();
    final result = await LogoRecreateCloud.runBytes(
      bytes,
      timeout: const Duration(seconds: 120),
      // ignore: avoid_print
      onLog: (line) => print('[recreate-test] $line'),
    );
    // ignore: avoid_print
    print('[recreate-test] $name '
        'png=${result.pngBytes.length}B '
        'svg=${result.svgBytes?.length ?? 0}B '
        'palette=${result.paletteHex} '
        'sections=${result.sectionCount} '
        'bg=${result.backgroundStripped} '
        'elapsed=${result.elapsed.inMilliseconds}ms');

    // Basic byte sanity.
    expect(result.pngBytes.length, greaterThan(1024));
    expect(result.svgBytes, isNotNull);
    expect(result.svgBytes!.length, greaterThan(64));

    // The response must be a REAL vector — not a fake wrapper. Look for
    // at least one <path or <polygon element in the SVG.
    final svgText = String.fromCharCodes(result.svgBytes!);
    expect(
      svgText.contains('<path') || svgText.contains('<polygon'),
      isTrue,
      reason: 'SVG should contain real path geometry, not just a raster wrap',
    );
    // Ensure the SVG isn't just an embedded raster (base64 image data).
    expect(
      svgText.contains('<image '),
      isFalse,
      reason: 'Recreate SVG must not embed a raster instead of vector paths',
    );

    // Write outputs back so the host can pull them for visual check.
    final outPng = File(p.join(dir.path, 'recreated_$name.png'));
    final outSvg = File(p.join(dir.path, 'recreated_$name.svg'));
    await outPng.writeAsBytes(result.pngBytes, flush: true);
    await outSvg.writeAsBytes(result.svgBytes!, flush: true);
    // ignore: avoid_print
    print('[recreate-test] wrote ${outPng.path} + ${outSvg.path}');

    // Also emit the outputs to the test log so the host has durable
    // evidence even after the debug APK's data dir is wiped on uninstall.
    final b64 = base64.encode(result.pngBytes);
    const chunk = 512;
    for (var i = 0; i < b64.length; i += chunk) {
      final end = (i + chunk).clamp(0, b64.length);
      // ignore: avoid_print
      print('[recreate-b64:$name:${i ~/ chunk}] ${b64.substring(i, end)}');
    }
    // Full SVG (small, self-contained proof of true vector output).
    // ignore: avoid_print
    print('[recreate-svg:$name:begin]${String.fromCharCodes(result.svgBytes!)}'
        '[recreate-svg:$name:end]');
  }

  testWidgets(
    'Android Recreate: Mastec (solid background) end-to-end',
    (tester) async => runOne('mastec'),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'Android Recreate: EPCOR (already-transparent) end-to-end',
    (tester) async => runOne('epcor'),
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'Android Recreate: ATCO (wide aspect) end-to-end',
    (tester) async => runOne('atco'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
