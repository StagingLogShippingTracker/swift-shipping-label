import 'dart:convert';
import 'dart:io';

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

  /// Storage map key for a preset (`shipping::Name`, etc.).
  static String presetStorageKey(LabelKind kind, String displayName) =>
      '${kind.name}::$displayName';

  static LabelKind presetKindFromStorageKey(String storageKey) {
    final sep = storageKey.indexOf('::');
    if (sep <= 0) return LabelKind.shipping;
    final kindName = storageKey.substring(0, sep);
    return LabelKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => LabelKind.shipping,
    );
  }

  static String presetDisplayNameFromStorageKey(String storageKey) {
    final sep = storageKey.indexOf('::');
    if (sep < 0) return storageKey;
    return storageKey.substring(sep + 2);
  }

  List<String> presetDisplayNamesFor(LabelKind kind) {
    final prefix = '${kind.name}::';
    return presets.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => e.value.name)
        .toList()
      ..sort();
  }

  CustomerPreset? presetFor(LabelKind kind, String displayName) =>
      presets[presetStorageKey(kind, displayName)];

  static Future<AppStorage> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'swift_document_generator'));
    final legacy = Directory(p.join(docs.path, 'swift_shipping_label'));
    // One-time migrate presets/logos from the old app folder name.
    if (!await root.exists() && await legacy.exists()) {
      try {
        await legacy.rename(root.path);
      } catch (_) {
        await root.create(recursive: true);
      }
    }
    final store = AppStorage._(root);
    await store.ensureDirs();
    await store.loadPresets();
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
    var migrated = false;
    try {
      final data = jsonDecode(await presetsFile.readAsString()) as Map<String, dynamic>;
      final customers = data['customers'];
      if (customers is Map) {
        for (final entry in customers.entries) {
          final rawKey = entry.key.toString();
          final v = entry.value;
          if (v is! Map) continue;
          final json = v is Map<String, dynamic>
              ? v
              : Map<String, dynamic>.from(v);

          final legacy = !rawKey.contains('::');
          final kind = legacy
              ? LabelKind.shipping
              : presetKindFromStorageKey(rawKey);
          final displayName = legacy
              ? rawKey
              : presetDisplayNameFromStorageKey(rawKey);
          final storageKey = presetStorageKey(kind, displayName);

          if (legacy) migrated = true;
          presets[storageKey] = CustomerPreset.fromJson(
            displayName,
            json,
            defaultKind: kind,
          );
        }
      }
      if (migrated) {
        await savePresets();
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

  /// Save downloaded logo bytes into [logosDir] (unique filename).
  Future<File> importLogoBytes(
    List<int> bytes, {
    required String preferredName,
  }) async {
    await logosDir.create(recursive: true);
    var name = preferredName.trim();
    if (name.isEmpty) name = 'logo.png';
    name = name.replaceAll(RegExp(r'[^\w\- .]+'), '_');
    var dest = File(p.join(logosDir.path, name));
    if (await dest.exists()) {
      final stem = p.basenameWithoutExtension(name);
      final suf = p.extension(name);
      var n = 2;
      while (await dest.exists()) {
        dest = File(p.join(logosDir.path, '$stem ($n)$suf'));
        n++;
      }
    }
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Write PDF under [filledDir], uniquifying with `(1)`, `(2)`, … if needed
  /// (no space before the parentheses — e.g. `SL-StrikeSO1223344(1).pdf`).
  Future<File> writePdf(String fileName, List<int> bytes) async {
    await filledDir.create(recursive: true);
    var base = p.basename(fileName.trim());
    if (!base.toLowerCase().endsWith('.pdf')) base = '$base.pdf';
    // Allow letters, digits, dash, underscore, parentheses; strip other junk.
    base = base.replaceAll(RegExp(r'[^\w.\-()]+'), '');
    if (base.isEmpty || base == '.pdf') base = 'label.pdf';

    final stem = p.basenameWithoutExtension(base);
    const ext = '.pdf';
    var out = File(p.join(filledDir.path, '$stem$ext'));
    var n = 1;
    while (await out.exists()) {
      out = File(p.join(filledDir.path, '$stem($n)$ext'));
      n++;
    }
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  String safeCustomerName(String text) {
    final t = text.trim().isEmpty ? 'customer' : text.trim();
    final cleaned = t.replaceAll(RegExp(r'[^\w\- ]+'), '').trim();
    return cleaned.isEmpty ? 'customer' : cleaned;
  }

  /// Compact token for `SL-` / `RL-` filenames (alphanumeric only).
  String compactFileToken(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return cleaned;
  }

  /// e.g. `SL-StrikeSO1223344.pdf`, `RL-…`, or `BOL-…`
  String labelPdfBaseName({
    required LabelKind kind,
    required String customer,
    required String salesOrder,
  }) {
    final prefix = switch (kind) {
      LabelKind.receiving => 'RL-',
      LabelKind.bol => 'BOL-',
      LabelKind.shipping => 'SL-',
    };
    final cust = compactFileToken(customer);
    final so = compactFileToken(salesOrder);
    final body = '$cust$so';
    if (body.isEmpty) return '${prefix}label.pdf';
    return '$prefix$body.pdf';
  }
}
