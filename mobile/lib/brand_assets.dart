/// Brand image paths used in app chrome (not PDF).
class SwiftBrandAssets {
  SwiftBrandAssets._();

  /// Light mode: orange mark with soft edge treatment.
  static const logoOrange = 'assets/images/swift_supply_logo_orange.png';

  /// Dark mode: solid orange mark (no light halo) for dark chrome.
  static const logoOrangeSolid =
      'assets/images/swift_supply_logo_orange_solid.png';

  /// White wordmark for legacy orange headers (light-only accents).
  static const headerWhite = 'assets/images/swift_supply_header_white.png';

  /// Chrome logo — always the solid orange mark so light and dark match.
  static String chromeLogo({required bool dark}) => logoOrangeSolid;
}
