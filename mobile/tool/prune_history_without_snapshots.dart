import 'dart:io';

import 'package:swift_shipping_label/app_storage.dart';
import 'package:swift_shipping_label/document_history_sync.dart';

/// One-off cloud prune of PDF-only history (no form snapshot).
Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('swift_hist_prune_');
  try {
    final sync = DocumentHistorySync(AppStorage.forTesting(tmp));
    stdout.writeln('Pruning history without form snapshots…');
    final n = await sync.pruneWithoutSnapshots();
    stdout.writeln('Deleted $n snapshot-less history row(s).');
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}
