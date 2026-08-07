import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Desktop-friendly scroll behavior for the whole app.
///
/// Ensures mouse wheel and trackpad gestures are recognized on all scrollables
/// without requiring the pointer to sit on a [Scrollbar] thumb. Touch / stylus
/// remain enabled for Android tablets and convertible devices.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Windows / Linux: clamping feels closer to native desktop apps.
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return const ClampingScrollPhysics(
          parent: RangeMaintainingScrollPhysics(),
        );
      default:
        return super.getScrollPhysics(context);
    }
  }
}
