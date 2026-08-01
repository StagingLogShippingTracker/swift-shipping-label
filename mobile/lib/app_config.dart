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
}
