import 'package:flutter/material.dart';

import 'app_storage.dart';
import 'home_screen.dart';
import 'pdf/shipping_label_pdf.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await AppStorage.open();
  final pdf = await ShippingLabelPdf.load();
  runApp(SwiftShippingLabelApp(storage: storage, pdf: pdf));
}

class SwiftShippingLabelApp extends StatelessWidget {
  const SwiftShippingLabelApp({
    super.key,
    required this.storage,
    required this.pdf,
  });

  final AppStorage storage;
  final ShippingLabelPdf pdf;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swift Document Generator',
      debugShowCheckedModeBanner: false,
      theme: SwiftTheme.light(),
      home: HomeScreen(storage: storage, pdf: pdf),
    );
  }
}
