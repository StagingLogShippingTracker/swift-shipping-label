import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Parsed semver (major.minor.patch) plus optional build number.
class AppVersion {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// Parses `1.0.0`, `1.0.0+1`, `v1.0.0`, etc.
  static AppVersion? tryParse(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    final match = RegExp(
      r'(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?',
    ).firstMatch(cleaned);
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() =>
      build > 0 ? '$major.$minor.$patch+$build' : '$major.$minor.$patch';
}

enum AppUpdatePlatform { windows, android }

enum ReleaseAssetKind { windowsSetup, windowsZip, androidApk, unknown }

ReleaseAssetKind classifyReleaseAsset(String fileName) {
  final lower = fileName.trim().toLowerCase();
  if (lower.isEmpty) return ReleaseAssetKind.unknown;
  if (lower.endsWith('.exe') &&
      (lower.contains('setup') ||
          lower == AppConfig.windowsSetupAsset.toLowerCase())) {
    return ReleaseAssetKind.windowsSetup;
  }
  if (lower.endsWith('.zip') &&
      (lower.contains('windows') ||
          lower == AppConfig.windowsZipAsset.toLowerCase())) {
    return ReleaseAssetKind.windowsZip;
  }
  if (lower.endsWith('.apk')) {
    if (lower.contains('android') ||
        lower == AppConfig.androidApkAsset.toLowerCase() ||
        lower == 'swiftshippinglabel.apk' ||
        lower.contains('-debug') ||
        lower.contains('-release')) {
      return ReleaseAssetKind.androidApk;
    }
  }
  return ReleaseAssetKind.unknown;
}

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    this.windowsSetupUrl,
    this.windowsZipUrl,
    this.androidApkUrl,
  });

  final String tagName;
  final String name;
  final String htmlUrl;
  final String? windowsSetupUrl;
  final String? windowsZipUrl;
  final String? androidApkUrl;

  AppVersion? get version =>
      AppVersion.tryParse(tagName) ?? AppVersion.tryParse(name);

  bool isNewerThanInstalled(String version, [String? buildNumber]) {
    final remote = this.version;
    if (remote == null) return false;
    final build = int.tryParse((buildNumber ?? '').trim()) ?? 0;
    final local = AppVersion.tryParse(
          build > 0 ? '$version+$build' : version,
        ) ??
        AppVersion.tryParse(version);
    if (local == null) return false;
    return remote.isNewerThan(local);
  }

  /// Preferred Windows asset URL — Setup.exe only for in-app updates.
  String? get windowsInstallUrl => windowsSetupUrl;

  String? assetUrlFor(AppUpdatePlatform platform) {
    switch (platform) {
      case AppUpdatePlatform.windows:
        return windowsInstallUrl;
      case AppUpdatePlatform.android:
        return androidApkUrl;
    }
  }

  String? assetLabelFor(AppUpdatePlatform platform) {
    switch (platform) {
      case AppUpdatePlatform.windows:
        return windowsSetupUrl == null ? null : AppConfig.windowsSetupAsset;
      case AppUpdatePlatform.android:
        return androidApkUrl == null ? null : AppConfig.androidApkAsset;
    }
  }

  bool hasAssetFor(AppUpdatePlatform platform) {
    final url = assetUrlFor(platform);
    return url != null && url.isNotEmpty;
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.latest,
    required this.updateAvailable,
    required this.platform,
    this.missingPlatformAsset = false,
  });

  final AppReleaseInfo latest;
  final AppUpdatePlatform platform;
  final bool updateAvailable;
  final bool missingPlatformAsset;
}

class AppUpdateService {
  const AppUpdateService();

  Future<AppReleaseInfo> fetchLatestRelease() async {
    late final http.Response res;
    try {
      res = await http
          .get(
            Uri.parse(AppConfig.githubLatestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'SwiftDocumentGenerator',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception(
        'Update check timed out. Check your network and try again.',
      );
    } on SocketException {
      throw Exception(
        'Could not reach GitHub. Check your network and try again.',
      );
    }
    if (res.statusCode == 404) {
      throw Exception('No GitHub releases published yet.');
    }
    if (res.statusCode == 403 || res.statusCode == 429) {
      throw Exception(
        'GitHub rate-limited the update check (HTTP ${res.statusCode}). '
        'Wait a minute or open Releases in the browser.',
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Could not check for updates (HTTP ${res.statusCode}).');
    }

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Unexpected release payload.');
    }

    String? windowsSetup;
    String? windowsZip;
    String? androidApk;
    final assets = body['assets'];
    if (assets is List) {
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? ''}'.trim();
        final url = '${raw['browser_download_url'] ?? ''}'.trim();
        if (name.isEmpty || url.isEmpty) continue;
        switch (classifyReleaseAsset(name)) {
          case ReleaseAssetKind.windowsSetup:
            windowsSetup = url;
          case ReleaseAssetKind.windowsZip:
            windowsZip = url;
          case ReleaseAssetKind.androidApk:
            androidApk = url;
          case ReleaseAssetKind.unknown:
            break;
        }
      }
    }

    return AppReleaseInfo(
      tagName: '${body['tag_name'] ?? ''}'.trim(),
      name: '${body['name'] ?? body['tag_name'] ?? 'Latest'}'.trim(),
      htmlUrl: '${body['html_url'] ?? AppConfig.githubReleasesPage}'.trim(),
      windowsSetupUrl: windowsSetup,
      windowsZipUrl: windowsZip,
      androidApkUrl: androidApk,
    );
  }

  Future<AppUpdateCheckResult> checkForUpdate({
    required String installedVersion,
    String? installedBuild,
    required AppUpdatePlatform platform,
  }) async {
    final latest = await fetchLatestRelease();
    final newer = latest.isNewerThanInstalled(
      installedVersion,
      installedBuild,
    );
    final hasAsset = latest.hasAssetFor(platform);
    return AppUpdateCheckResult(
      latest: latest,
      platform: platform,
      updateAvailable: newer && hasAsset,
      missingPlatformAsset: newer && !hasAsset,
    );
  }

  /// Windows: durable app-support path. Android: temp is fine for OpenFilex.
  Future<File> downloadAndInstall({
    required AppUpdatePlatform platform,
    required AppReleaseInfo release,
    void Function(double progress)? onProgress,
  }) async {
    final url = release.assetUrlFor(platform);
    final fileName = release.assetLabelFor(platform);
    if (url == null || url.isEmpty || fileName == null) {
      if (platform == AppUpdatePlatform.windows) {
        throw Exception(
          'No Windows Setup.exe asset on this release. '
          'In-app Update requires ${AppConfig.windowsSetupAsset}.',
        );
      }
      throw Exception('No Android APK asset on this release.');
    }

    final file = platform == AppUpdatePlatform.windows
        ? await downloadToAppStorage(
            url: url,
            fileName: fileName,
            onProgress: onProgress,
          )
        : await downloadToTemp(
            url: url,
            fileName: fileName,
            onProgress: onProgress,
          );
    await installDownloadedFile(platform: platform, file: file);
    return file;
  }

  Future<File> downloadToAppStorage({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'updates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _downloadToFile(
      url: url,
      target: File(p.join(dir.path, fileName)),
      onProgress: onProgress,
    );
  }

  Future<File> downloadToTemp({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    return _downloadToFile(
      url: url,
      target: File(p.join(dir.path, fileName)),
      onProgress: onProgress,
    );
  }

  Future<File> _downloadToFile({
    required String url,
    required File target,
    void Function(double progress)? onProgress,
  }) async {
    if (await target.exists()) {
      await target.delete();
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'SwiftDocumentGenerator';
      final res = await client.send(req);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Download failed (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength ?? 0;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
        if (onProgress != null) onProgress(1.0);
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }

    if (!await target.exists() || await target.length() == 0) {
      throw Exception('Download produced an empty file.');
    }
    return target;
  }

  Future<void> installDownloadedFile({
    required AppUpdatePlatform platform,
    required File file,
  }) async {
    switch (platform) {
      case AppUpdatePlatform.windows:
        await Process.start(
          file.path,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      case AppUpdatePlatform.android:
        // Match SLST: open_filex → system package installer (ACTION_VIEW).
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          throw Exception(
            result.message.isEmpty
                ? 'Could not open the downloaded package for install.'
                : result.message,
          );
        }
    }
  }

  /// Android install — same path as SLST (`open_filex` + temp download).
  Future<File> downloadAndInstallAndroid({
    required AppReleaseInfo release,
    void Function(double progress)? onProgress,
  }) =>
      downloadAndInstall(
        platform: AppUpdatePlatform.android,
        release: release,
        onProgress: onProgress,
      );

  /// Download Windows Setup.exe and launch the installer.
  Future<File> downloadAndInstallWindows({
    required AppReleaseInfo release,
    void Function(double progress)? onProgress,
  }) =>
      downloadAndInstall(
        platform: AppUpdatePlatform.windows,
        release: release,
        onProgress: onProgress,
      );
}
