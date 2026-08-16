import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/sibling_apps.dart';

void main() {
  test('windows sibling candidates include per-user Programs install path', () {
    final sep = Platform.pathSeparator;
    final paths = windowsSiblingCandidatePaths(
      app: siblingStagingTracker,
      env: {
        'LOCALAPPDATA': 'C:${sep}Users${sep}test${sep}AppData${sep}Local',
        'PROGRAMFILES': 'C:${sep}Program Files',
      },
    );
    expect(
      paths,
      contains(
        'C:${sep}Users${sep}test${sep}AppData${sep}Local${sep}Programs$sep'
        'Swift Staging Shipping Log${sep}SwiftStagingLog.exe',
      ),
    );
    expect(
      paths,
      contains(
        'C:${sep}Users${sep}test${sep}AppData${sep}Local${sep}Programs$sep'
        'SLST${sep}SwiftStagingLog.exe',
      ),
    );
  });
}
