import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'label_data.dart';

/// App-private storage for presets, logos, and generated PDFs.
class AppStorage {
  AppStorage._(this.root);

  final Directory root;

  Directory get logosDir => Directory(p.join(root.path, 'customer_logos'));
  Directory get filledDir => Directory(p.join(root.path, 'filled'));
  File get presetsFile => File(p.join(root.path, 'presets.json'));

  Map<String, CustomerPreset> presets = {};

  static Future<AppStorage> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'swift_shipping_label'));
    final store = AppStorage._(root);
    await store.ensureDirs();
    await store.loadPresets();
    await store.seedSample();
    return store;
  }

  Future<void> ensureDirs() async {
    await root.create(recursive: true);
    await logosDir.create(recursive: true);
    await filledDir.create(recursive: true);
  }

  Future<void> loadPresets() async {
    presets = {};
    if (!await presetsFile.exists()) return;
    try {
      final data = jsonDecode(await presetsFile.readAsString()) as Map<String, dynamic>;
      final customers = data['customers'];
      if (customers is Map) {
        for (final entry in customers.entries) {
          final v = entry.value;
          if (v is Map<String, dynamic>) {
            presets[entry.key.toString()] = CustomerPreset.fromJson(
              entry.key.toString(),
              v,
            );
          } else if (v is Map) {
            presets[entry.key.toString()] = CustomerPreset.fromJson(
              entry.key.toString(),
              Map<String, dynamic>.from(v),
            );
          }
        }
      }
    } catch (_) {
      presets = {};
    }
  }

  Future<void> savePresets() async {
    final customers = <String, dynamic>{};
    for (final e in presets.entries) {
      customers[e.key] = e.value.toJson();
    }
    await presetsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'customers': customers}),
    );
  }

  Future<void> seedSample() async {
    final dest = File(p.join(logosDir.path, 'Pacific Canbriam.png'));
    if (!await dest.exists()) {
      final bytes = await rootBundle.load('assets/images/sample_customer_logo.png');
      await dest.writeAsBytes(bytes.buffer.asUint8List());
    }
    if (!presets.containsKey('Pacific Canbriam')) {
      presets['Pacific Canbriam'] = CustomerPreset(
        name: 'Pacific Canbriam',
        logoFileNames: const ['Pacific Canbriam.png'],
        fields: {
          LabelFields.customer: 'PACIFIC CANBRIAM',
          LabelFields.shipTo: 'STRAIT PROJECTS',
          LabelFields.location: '12341 271 RD, FORT ST. JOHN, BC',
          LabelFields.attn: 'RICK SHUMAN / JEREMY PLATZ',
          LabelFields.carrier: 'WILLYS',
        },
      );
      await savePresets();
    }
  }

  List<File> listLogos() {
    if (!logosDir.existsSync()) return [];
    const exts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
    final files = logosDir
        .listSync()
        .whereType<File>()
        .where((f) => exts.contains(p.extension(f.path).toLowerCase()))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  Future<File> importLogo(File source, {String? preferredName}) async {
    var name = preferredName ?? p.basename(source.path);
    var dest = File(p.join(logosDir.path, name));
    final sameFile = await dest.exists() &&
        p.normalize(dest.absolute.path) == p.normalize(source.absolute.path);
    if (await dest.exists() && !sameFile) {
      final stem = p.basenameWithoutExtension(name);
      final suf = p.extension(name);
      var n = 2;
      while (await dest.exists()) {
        dest = File(p.join(logosDir.path, '$stem ($n)$suf'));
        n++;
      }
    }
    if (!sameFile) {
      await source.copy(dest.path);
    }
    return dest;
  }

  Future<File> writePdf(String fileName, List<int> bytes) async {
    await filledDir.create(recursive: true);
    final safe = fileName.replaceAll(RegExp(r'[^\w\- .]+'), '').trim();
    final out = File(p.join(filledDir.path, safe.isEmpty ? 'label.pdf' : safe));
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  String safeCustomerName(String text) {
    final t = text.trim().isEmpty ? 'customer' : text.trim();
    final cleaned = t.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    return cleaned.isEmpty ? 'customer' : cleaned;
  }
}
