import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_shipping_label/brand_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SwiftChromeLogo uses solid orange PNG', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SwiftChromeLogo(height: 40)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SwiftChromeLogo), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    ImageProvider provider = image.image;
    if (provider is ResizeImage) {
      provider = provider.imageProvider;
    }
    expect(provider, isA<AssetImage>());
    expect(
      (provider as AssetImage).assetName,
      SwiftBrandAssets.logoOrangeSolid,
    );
  });
}
