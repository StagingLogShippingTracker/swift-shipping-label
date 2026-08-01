import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _native = MethodChannel('com.swiftoilfield.swift_shipping_label/native');

const _imageGroup = XTypeGroup(
  label: 'Images',
  extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
);

/// Platform image picker (Android MethodChannel / desktop file_selector).
Future<List<String>> pickImagePaths({required bool multiple}) async {
  if (Platform.isAndroid) {
    final raw = await _native.invokeMethod<List<dynamic>>('pickImages', {
      'multiple': multiple,
    });
    return (raw ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  if (multiple) {
    final files = await openFiles(acceptedTypeGroups: [_imageGroup]);
    return files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
  }
  final file = await openFile(acceptedTypeGroups: [_imageGroup]);
  if (file == null || file.path.isEmpty) return const [];
  return [file.path];
}

/// Share sheet on Android; open with the default viewer on desktop.
Future<void> shareOrOpenFile({
  required File file,
  String mime = 'application/pdf',
  String subject = 'Swift Supply Shipping Label',
}) async {
  if (Platform.isAndroid) {
    await _native.invokeMethod<bool>('shareFile', {
      'path': file.path,
      'mime': mime,
      'subject': subject,
    });
    return;
  }

  final uri = Uri.file(file.path);
  final ok = await launchUrl(uri);
  if (!ok && Platform.isWindows) {
    await Process.start('cmd', ['/c', 'start', '', file.path], runInShell: true);
  }
}

Future<void> openFolder(String path) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [path]);
    return;
  }
  await launchUrl(Uri.file(path));
}
