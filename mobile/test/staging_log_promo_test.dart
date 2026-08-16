import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/changelog.dart';
import 'package:swift_shipping_label/sibling_apps.dart';
import 'package:swift_shipping_label/staging_log_promo.dart';

void main() {
  test('v1.1.78 campaign is three launches and lists the Staging Log intro', () {
    expect(AppChangelog.campaignId, 'whats_new_1_1_78');
    expect(AppChangelog.maxShows, 3);
    expect(AppChangelog.sections.first.version, 'v1.1.78');
    expect(
      AppChangelog.sections.first.bullets.join(' '),
      contains('Staging & Shipping Log'),
    );
  });

  test('promo Try it today targets the same sibling app as MORE APPS', () {
    expect(siblingStagingTracker.id, 'staging-tracker');
    expect(slstPromoIconAsset, siblingStagingTracker.iconAsset);
    expect(slstPromoStills, hasLength(4));
  });
}
