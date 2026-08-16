import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _native = MethodChannel('com.swiftoilfield.swift_shipping_label/native');

const _imageGroup = XTypeGroup(
  label: 'Images',
  extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
);

const _pdfGroup = XTypeGroup(
  label: 'PDF',
  extensions: <String>['pdf'],
  mimeTypes: <String>['application/pdf'],
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

/// Pick a single PDF document (Order Acknowledgement for Bulk Labels).
///
/// Android uses the same SAF → cache copy path as logo picking so Dart can
/// read a real filesystem path. Desktop uses file_selector.
Future<String?> pickPdfPath() async {
  final paths = await pickPdfPaths(multiple: false);
  if (paths.isEmpty) return null;
  return paths.first;
}

/// Pick one or more PDFs (OA or packing list).
Future<List<String>> pickPdfPaths({bool multiple = false}) async {
  if (Platform.isAndroid) {
    if (!multiple) {
      final path = await _native.invokeMethod<String?>('pickPdf');
      if (path == null || path.isEmpty) return const [];
      return [path];
    }
    final raw = await _native.invokeMethod<List<dynamic>>('pickPdfs', {
      'multiple': true,
    });
    return (raw ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  if (multiple) {
    final files = await openFiles(acceptedTypeGroups: [_pdfGroup]);
    return files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
  }
  final file = await openFile(acceptedTypeGroups: [_pdfGroup]);
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
    if (!await file.exists()) {
      throw StateError('File not found: ${file.path}');
    }
    await _native.invokeMethod<bool>('shareFile', {
      'path': file.absolute.path,
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
