import 'dart:typed_data';

/// Demo stub — production uses smart crop / background removal.
/// Portfolio web build skips heavy image processing dependencies.
class LogoImageProcessor {
  LogoImageProcessor._();

  static Uint8List normalizeToVisibleContent(Uint8List input) => input;

  static Uint8List prepareSignatureInk(Uint8List input) => input;
}
