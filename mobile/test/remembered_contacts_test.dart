import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/app_storage.dart';

void main() {
  late Directory tmp;
  late AppStorage store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('swift_remembered_contacts_');
    store = AppStorage.forTesting(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('rememberContact is MRU, case-insensitive, and capped', () async {
    expect(await store.rememberContact('  Alice  '), isTrue);
    expect(await store.rememberContact('Bob'), isTrue);
    expect(await store.rememberContact('alice'), isTrue); // bump to front
    expect(store.rememberedContacts.take(2).toList(), ['alice', 'Bob']);

    expect(await store.rememberContact('alice'), isFalse); // already first
    expect(await store.rememberContact('   '), isFalse);

    for (var i = 0; i < AppStorage.maxRememberedContacts + 5; i++) {
      await store.rememberContact('Person $i');
    }
    expect(store.rememberedContacts.length, AppStorage.maxRememberedContacts);
    expect(store.rememberedContacts.first, 'Person ${AppStorage.maxRememberedContacts + 4}');
  });

  test('contactSuggestions puts remembered ahead of roster', () async {
    await store.rememberContact('Custom Name');
    await store.rememberContact('Roster Dup');
    final suggestions = store.contactSuggestions(
      roster: const ['Roster Dup', 'Directory Only'],
    );
    expect(suggestions.first, 'Roster Dup');
    expect(suggestions, containsAllInOrder(['Roster Dup', 'Custom Name', 'Directory Only']));
    expect(suggestions.where((n) => n.toLowerCase() == 'roster dup').length, 1);
  });

  test('clearRememberedContacts wipes local memory only', () async {
    await store.rememberContact('Temp');
    await store.clearRememberedContacts();
    expect(store.rememberedContacts, isEmpty);
    expect(await store.rememberedContactsFile.exists(), isTrue);
    expect(await store.rememberedContactsFile.readAsString(), '[]');
    expect(
      store.contactSuggestions(roster: const ['From Roster']),
      ['From Roster'],
    );
  });
}
