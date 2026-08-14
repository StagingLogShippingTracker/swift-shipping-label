import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'app_storage.dart';
import 'label_data.dart';

/// Metadata for a generated PDF stored in Supabase.
class GeneratedDocumentRecord {
  const GeneratedDocumentRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.customer,
    required this.salesOrder,
    required this.fileName,
    required this.storagePath,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final LabelKind kind;
  final String title;
  final String customer;
  final String salesOrder;
  final String fileName;
  final String storagePath;
  final int byteSize;
  final DateTime createdAt;
}

/// Uploads / lists / downloads generated PDFs (cloud source of truth).
class DocumentHistorySync {
  DocumentHistorySync(this.storage);

  final AppStorage storage;

  static const bucket = 'generated-documents';
  static const _timeout = Duration(seconds: 45);

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  Future<GeneratedDocumentRecord> upload({
    required LabelKind kind,
    required String fileName,
    required Uint8List bytes,
    required String customer,
    required String salesOrder,
    String? title,
  }) async {
    final id = _newId();
    final safeName = fileName.trim().isEmpty ? '$id.pdf' : fileName.trim();
    final storagePath = '${kind.name}/$id/${p.basename(safeName)}';
    await _uploadBytes(storagePath, bytes);

    final created = DateTime.now().toUtc();
    final displayTitle = (title ?? safeName).trim();
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/generated_documents?on_conflict=id',
    );
    final res = await http
        .post(
          uri,
          headers: {
            ..._headers,
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'id': id,
            'kind': kind.name,
            'title': displayTitle,
            'customer': customer.trim(),
            'sales_order': salesOrder.trim(),
            'file_name': safeName,
            'storage_path': storagePath,
            'byte_size': bytes.length,
            'created_at': created.toIso8601String(),
          }),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DocumentHistorySyncException(
        'Could not save document metadata (${res.statusCode}).',
      );
    }
    return GeneratedDocumentRecord(
      id: id,
      kind: kind,
      title: displayTitle,
      customer: customer.trim(),
      salesOrder: salesOrder.trim(),
      fileName: safeName,
      storagePath: storagePath,
      byteSize: bytes.length,
      createdAt: created,
    );
  }

  Future<List<GeneratedDocumentRecord>> listForKind(
    LabelKind kind, {
    int limit = 60,
  }) async {
    await purgeExpired();
    final kindEnc = Uri.encodeComponent(kind.name);
    final cutoff = Uri.encodeComponent(_retentionCutoff().toIso8601String());
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/generated_documents'
      '?kind=eq.$kindEnc'
      '&created_at=gte.$cutoff'
      '&select=id,kind,title,customer,sales_order,file_name,storage_path,byte_size,created_at'
      '&order=created_at.desc'
      '&limit=$limit',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DocumentHistorySyncException(
        'Could not list documents (${res.statusCode}).',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! List) return [];
    final out = <GeneratedDocumentRecord>[];
    for (final row in body) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final id = '${m['id'] ?? ''}'.trim();
      final kindName = '${m['kind'] ?? ''}'.trim();
      final path = '${m['storage_path'] ?? ''}'.trim();
      final fileName = '${m['file_name'] ?? ''}'.trim();
      if (id.isEmpty || path.isEmpty) continue;
      final k = LabelKind.values.firstWhere(
        (x) => x.name == kindName,
        orElse: () => LabelKind.shipping,
      );
      out.add(
        GeneratedDocumentRecord(
          id: id,
          kind: k,
          title: '${m['title'] ?? fileName}'.trim(),
          customer: '${m['customer'] ?? ''}'.trim(),
          salesOrder: '${m['sales_order'] ?? ''}'.trim(),
          fileName: fileName.isEmpty ? p.basename(path) : fileName,
          storagePath: path,
          byteSize: (m['byte_size'] is num) ? (m['byte_size'] as num).toInt() : 0,
          createdAt: DateTime.tryParse('${m['created_at']}')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    return out;
  }

  /// Download the unique cloud object for this history row.
  ///
  /// Cache is keyed by document [id], never by display [fileName] — regenerating
  /// the same customer+SO overwrites `filled/{fileName}` locally, which must not
  /// be reused for an older history entry.
  Future<File> downloadToCache(GeneratedDocumentRecord doc) async {
    final stem = p.basenameWithoutExtension(
      doc.fileName.isEmpty ? 'document' : doc.fileName,
    );
    final cache = File(
      p.join(storage.filledDir.path, '${stem}_${doc.id}.pdf'),
    );
    if (await cache.exists()) {
      final len = await cache.length();
      if (len > 0 && (doc.byteSize <= 0 || len == doc.byteSize)) {
        return cache;
      }
    }

    final encodedPath = doc.storagePath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/storage/v1/object/public/$bucket/$encodedPath',
    );
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DocumentHistorySyncException(
        'Could not download PDF (${res.statusCode}).',
      );
    }
    await storage.filledDir.create(recursive: true);
    await cache.writeAsBytes(res.bodyBytes, flush: true);
    return cache;
  }

  /// Drop history older than 90 days from Supabase (rows + PDFs) and local cache.
  Future<void> purgeExpired() async {
    final cutoff = _retentionCutoff();
    try {
      await _purgeExpiredRemote(cutoff);
    } catch (_) {}
    try {
      await _purgeExpiredLocalCache(cutoff);
    } catch (_) {}
  }

  static DateTime _retentionCutoff() =>
      DateTime.now().toUtc().subtract(retention);

  static const retention = Duration(days: 90);

  Future<void> _purgeExpiredRemote(DateTime cutoff) async {
    final cutoffEnc = Uri.encodeComponent(cutoff.toIso8601String());
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/generated_documents'
      '?created_at=lt.$cutoffEnc'
      '&select=id,storage_path,file_name',
    );
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return;
    final body = jsonDecode(res.body);
    if (body is! List) return;
    for (final row in body) {
      if (row is! Map) continue;
      final path = '${row['storage_path'] ?? ''}'.trim();
      final id = '${row['id'] ?? ''}'.trim();
      if (path.isNotEmpty) {
        await _deleteStorageObject(path);
      }
      if (id.isEmpty) continue;
      final del = Uri.parse(
        '${AppConfig.supabaseUrl}/rest/v1/generated_documents?id=eq.${Uri.encodeComponent(id)}',
      );
      await http
          .delete(del, headers: _headers)
          .timeout(const Duration(seconds: 20));
    }
  }

  Future<void> _deleteStorageObject(String storagePath) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/storage/v1/object/$bucket/${storagePath.split('/').map(Uri.encodeComponent).join('/')}',
    );
    await http
        .delete(
          uri,
          headers: {
            'apikey': AppConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
          },
        )
        .timeout(const Duration(seconds: 20));
  }

  Future<void> _purgeExpiredLocalCache(DateTime cutoff) async {
    final dir = storage.filledDir;
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.pdf') continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.toUtc().isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
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
            'Content-Type': 'application/pdf',
            'x-upsert': 'true',
          },
          body: bytes,
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DocumentHistorySyncException(
        'Could not upload PDF (${res.statusCode}).',
      );
    }
  }

  static String _newId() =>
      DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
}

class DocumentHistorySyncException implements Exception {
  DocumentHistorySyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
