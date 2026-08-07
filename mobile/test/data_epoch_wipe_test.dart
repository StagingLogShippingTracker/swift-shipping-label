import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/app_storage.dart';

void main() {
  late Directory tmp;
  late AppStorage store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('swift_data_epoch_');
    store = AppStorage.forTesting(tmp);
    await store.ensureDirs();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('applyLocalDataEpochIfNeeded wipes once then no-ops', () async {
    await File('${tmp.path}/presets.json').writeAsString('{"customers":{}}');
    await File('${tmp.path}/customer_logos/x.png').writeAsBytes([1, 2, 3]);
    await store.rememberContact('Keep Me');

    expect(await store.applyLocalDataEpochIfNeeded(), isTrue);
    expect(store.rememberedContacts, isEmpty);
    expect(await File('${tmp.path}/customer_logos/x.png').exists(), isFalse);
    expect(await store.dataEpochFile.exists(), isTrue);

    await store.rememberContact('After Wipe');
    expect(await store.applyLocalDataEpochIfNeeded(), isFalse);
    expect(store.rememberedContacts, ['After Wipe']);
  });
}
