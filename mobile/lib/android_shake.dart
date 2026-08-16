import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Hard-shake events from the Android accelerometer (no-op on other platforms).
class AndroidShake {
  AndroidShake._();

  static const _channel = EventChannel(
    'com.swiftoilfield.swift_shipping_label/shake',
  );

  static Stream<void> get events {
    if (!Platform.isAndroid) return const Stream.empty();
    return _channel.receiveBroadcastStream().map((_) {});
  }
}
