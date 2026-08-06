import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/logo_finder.dart';

void main() {
  test('known domain hints prefer real corporate sites', () {
    expect(
      LogoFinder.debugExpandedQueries('Strike Group'),
      contains('Strike Group Canada logo'),
    );
  });

  test('live: Strike Group tops with strikegroup.ca scrape (not navy wiki)', () async {
    final finder = LogoFinder();
    final results = await finder.findDownloadedCandidates(
      companyName: 'Strike Group',
      engine: LogoSearchEngine.all,
    );
    expect(results, isNotEmpty);
    final top = results.first;
    // ignore: avoid_print
    print('Strike top: [${top.score}] ${top.source}');
    expect(top.source.toLowerCase(), isNot(contains('wikipedia')));
    expect(
      top.source.toLowerCase().contains('strikegroup') ||
          top.source.toLowerCase().contains('known brand') ||
          top.source.toLowerCase().contains('site scrape'),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
