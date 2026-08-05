/// Public GitHub Releases feed for in-app Update (Windows/Android parity).
class AppConfig {
  static const githubOwner = 'StagingLogShippingTracker';
  static const githubRepo = 'swift-shipping-label';

  static const githubLatestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static const githubReleasesPage =
      'https://github.com/$githubOwner/$githubRepo/releases';

  static const windowsZipAsset = 'SwiftDocumentGenerator-windows.zip';
  static const androidApkAsset = 'SwiftDocumentGenerator-android.apk';

  /// Shared BOL serial counter (StagingLogShippingTracker Supabase).
  /// Anon key only — RPC is SECURITY DEFINER `next_bol_serial`.
  static const supabaseUrl = 'https://gdrpdiwykmnybmkadlrv.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdkcnBkaXd5a21ueWJta2FkbHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1MjMyMTIsImV4cCI6MjA5NjA5OTIxMn0.Z7ih_vQic1GtzCyZmTEV-RWJnmuaNZQDfOV2_Fvan5g';

  /// Optional Retool REST/workflow proxy for Clearbit logo lookups.
  /// Set at build time via `--dart-define=RETOOL_CLEARBIT_LOGO_URL=...` or
  /// the `RETOOL_CLEARBIT_LOGO_URL` environment variable. Use `{domain}` in
  /// the template, e.g. `https://your-org.retool.com/api/.../clearbit?domain={domain}`.
  /// When empty, only the public `https://logo.clearbit.com/{domain}` endpoint is used.
  static const retoolClearbitLogoUrl = String.fromEnvironment(
    'RETOOL_CLEARBIT_LOGO_URL',
    defaultValue: '',
  );

  /// Cloud Recreate fallback (Supabase Deno/`vtracer` edge function).
  /// Preferred paths are Windows local Python and on-device Rust — see
  /// `logo_recreate.dart`. Override with `--dart-define=RECREATE_LOGO_URL=...`.
  /// Do not point this at Fly.io (that experiment was aborted).
  static const recreateLogoUrl = String.fromEnvironment(
    'RECREATE_LOGO_URL',
    defaultValue:
        'https://gdrpdiwykmnybmkadlrv.supabase.co/functions/v1/recreate-logo',
  );
}
