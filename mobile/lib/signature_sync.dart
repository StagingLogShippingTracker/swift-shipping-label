import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'app_storage.dart';
import 'label_data.dart';

/// Syncs saved BOL signatures with Supabase (shared across devices).
class SignatureSync {
  SignatureSync(this.storage);

  final AppStorage storage;

  static const bucket = 'signatures';
  static const _timeout = Duration(seconds: 25);

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  List<SavedSignature> get localSignatures => List.unmodifiable(storage.signatures);

  Future<void> syncOnLaunch() async {
    final remoteRows = await _fetchRemote();
    if (remoteRows.isEmpty) {
      await _pushAllLocal();
      return;
    }
    await _mergeRemoteIntoLocal(remoteRows);
    await _pushLocalOnly(remoteRows);
    await _pushNewerLocal(remoteRows);
  }

  Future<SavedSignature> saveSignature({
    required String name,
    required Uint8List pngBytes,
  }) async {
    final displayName = name.trim().isEmpty ? 'My signature' : name.trim();
    final id = _newId();
    final fileName = '$id.png';
    final localFile = File(p.join(storage.signaturesDir.path, fileName));
    await localFile.writeAsBytes(pngBytes, flush: true);

    final storagePath = _storagePath(id);
    await _uploadBytes(storagePath, pngBytes);

    final sig = SavedSignature(
      id: id,
      name: displayName,
      fileName: fileName,
      updatedAt: DateTime.now().toUtc(),
    );
    storage.signatures = [
      sig,
      ...storage.signatures.where((s) => s.id != id),
    ];
    await storage.saveSignatures();

    await _upsertRemote(sig, storagePath);
    return sig;
  }

  Future<Uint8List?> loadBytes(SavedSignature sig) async {
    final local = File(p.join(storage.signaturesDir.path, sig.fileName));
    if (await local.exists()) {
      return local.readAsBytes();
    }
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/storage/v1/object/public/$bucket/${_storagePath(sig.id)}',
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    await local.writeAsBytes(res.bodyBytes, flush: true);
    return res.bodyBytes;
  }

  Future<void> deleteSignature(SavedSignature sig) async {
    storage.signatures =
        storage.signatures.where((s) => s.id != sig.id).toList();
    await storage.saveSignatures();
    try {
      await File(p.join(storage.signaturesDir.path, sig.fileName)).delete();
    } catch (_) {}
    final idEnc = Uri.encodeComponent(sig.id);
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/signatures?id=eq.$idEnc',
    );
    await http.delete(uri, headers: _headers).timeout(_timeout);
    try {
      final storageUri = Uri.parse(
        '${AppConfig.supabaseUrl}/storage/v1/object/$bucket/${_storagePath(sig.id)}',
      );
      await http.delete(storageUri, headers: _headers).timeout(_timeout);
    } catch (_) {}
  }

  Future<List<_RemoteSignature>> _fetchRemote() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/signatures'
      '?select=id,name,storage_path,updated_at',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SignatureSyncException(
        'Could not fetch signatures (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    final out = <_RemoteSignature>[];
    for (final row in body) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final id = '${m['id'] ?? ''}'.trim();
      final name = '${m['name'] ?? ''}'.trim();
      final path = '${m['storage_path'] ?? ''}'.trim();
      if (id.isEmpty || name.isEmpty || path.isEmpty) continue;
      out.add(
        _RemoteSignature(
          id: id,
          name: name,
          storagePath: path,
          updatedAt: parseTime(m['updated_at']),
        ),
      );
    }
    return out;
  }

  Future<void> _mergeRemoteIntoLocal(List<_RemoteSignature> remoteRows) async {
    var changed = false;
    final byId = {for (final s in storage.signatures) s.id: s};
    for (final remote in remoteRows) {
      final local = byId[remote.id];
      if (local != null) {
        final localStamp = local.updatedAt;
        if (localStamp.isAfter(remote.updatedAt)) continue;
      }
      final fileName = '${remote.id}.png';
      await _downloadIfMissing(remote.storagePath, fileName);
      byId[remote.id] = SavedSignature(
        id: remote.id,
        name: remote.name,
        fileName: fileName,
        updatedAt: remote.updatedAt,
      );
      changed = true;
    }
    if (changed) {
      storage.signatures = byId.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await storage.saveSignatures();
    }
  }

  Future<void> _pushLocalOnly(List<_RemoteSignature> remoteRows) async {
    final remoteIds = {for (final r in remoteRows) r.id};
    for (final sig in storage.signatures) {
      if (remoteIds.contains(sig.id)) continue;
      final local = File(p.join(storage.signaturesDir.path, sig.fileName));
      if (!await local.exists()) continue;
      final bytes = await local.readAsBytes();
      final path = _storagePath(sig.id);
      await _uploadBytes(path, bytes);
      await _upsertRemote(sig, path);
    }
  }

  Future<void> _pushNewerLocal(List<_RemoteSignature> remoteRows) async {
    final remoteById = {for (final r in remoteRows) r.id: r};
    final indexStamp = storage.signaturesIndexModified;
    for (final sig in storage.signatures) {
      final remote = remoteById[sig.id];
      if (remote == null) continue;
      if (indexStamp.isAfter(remote.updatedAt)) {
        final local = File(p.join(storage.signaturesDir.path, sig.fileName));
        if (!await local.exists()) continue;
        final bytes = await local.readAsBytes();
        final path = _storagePath(sig.id);
        await _uploadBytes(path, bytes);
        await _upsertRemote(sig, path);
      }
    }
  }

  Future<void> _pushAllLocal() async {
    for (final sig in storage.signatures) {
      final local = File(p.join(storage.signaturesDir.path, sig.fileName));
      if (!await local.exists()) continue;
      final bytes = await local.readAsBytes();
      final path = _storagePath(sig.id);
      await _uploadBytes(path, bytes);
      await _upsertRemote(sig, path);
    }
  }

  Future<void> _upsertRemote(SavedSignature sig, String storagePath) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/signatures?on_conflict=id',
    );
    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'id': sig.id,
            'name': sig.name,
            'storage_path': storagePath,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SignatureSyncException(
        'Could not save signature to cloud (${res.statusCode}).',
      );
    }
  }

  Future<void> _uploadBytes(String storagePath, Uint8List bytes) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/storage/v1/object/$bucket/$storagePath',
    );
    final res = await http
        .post(
          uri,
          headers: {
            'apikey': AppConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
            'Content-Type': 'image/png',
            'x-upsert': 'true',
          },
          body: bytes,
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SignatureSyncException(
        'Could not upload signature (${res.statusCode}).',
      );
    }
  }

  Future<void> _downloadIfMissing(String storagePath, String fileName) async {
    final dest = File(p.join(storage.signaturesDir.path, fileName));
    if (await dest.exists()) return;
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/storage/v1/object/public/$bucket/$storagePath',
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return;
    await dest.writeAsBytes(res.bodyBytes, flush: true);
  }

  static String _storagePath(String id) => '$id.png';

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static DateTime parseTime(Object? raw) {
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse('$raw').toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class _RemoteSignature {
  const _RemoteSignature({
    required this.id,
    required this.name,
    required this.storagePath,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String storagePath;
  final DateTime updatedAt;
}

class SignatureSyncException implements Exception {
  const SignatureSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
