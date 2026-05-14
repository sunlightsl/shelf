import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as p;
import '../../models/cloud_file.dart';
import 'cloud_storage.dart';

/// S3 / MinIO / COS / OSS 兼容存储实现
///
/// 支持所有兼容 AWS S3 API 的对象存储服务。
class S3Storage implements CloudStorage {
  Minio? _client;
  String? _bucket;

  @override
  String get name => 'S3';

  @override
  String get protocol => 's3';

  @override
  bool get isConnected => _client != null && _bucket != null;

  @override
  Future<bool> connect(Map<String, String> credentials) async {
    final endPoint = credentials['endPoint'];
    final accessKey = credentials['accessKey'];
    final secretKey = credentials['secretKey'];
    final bucket = credentials['bucket'];

    if (endPoint == null || endPoint.isEmpty) {
      throw ArgumentError('S3 Endpoint 不能为空');
    }
    if (accessKey == null || accessKey.isEmpty) {
      throw ArgumentError('Access Key 不能为空');
    }
    if (secretKey == null || secretKey.isEmpty) {
      throw ArgumentError('Secret Key 不能为空');
    }
    if (bucket == null || bucket.isEmpty) {
      throw ArgumentError('Bucket 名称不能为空');
    }

    final portStr = credentials['port'];
    final useSSLStr = credentials['useSSL'];
    final region = credentials['region'];
    final pathStyleStr = credentials['pathStyle'];

    try {
      _client = Minio(
        endPoint: endPoint,
        port: portStr != null ? int.tryParse(portStr) : null,
        useSSL: useSSLStr != 'false',
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        pathStyle: pathStyleStr == 'true',
      );
      _bucket = bucket;

      // 测试连接：检查 bucket 是否存在
      final exists = await _client!.bucketExists(bucket);
      return exists;
    } catch (e) {
      debugPrint('S3 连接失败: $e');
      _client = null;
      _bucket = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _client = null;
    _bucket = null;
  }

  @override
  Future<bool> testConnection() async {
    if (_client == null || _bucket == null) return false;
    try {
      return await _client!.bucketExists(_bucket!);
    } catch (e) {
      debugPrint('S3 连接测试失败: $e');
      return false;
    }
  }

  @override
  Future<List<CloudFile>> listDirectory(String path) async {
    if (_client == null || _bucket == null) throw StateError('S3 未连接');

    final prefix = path == '/' || path.isEmpty ? '' : _ensureTrailingSlash(path);
    final result = <CloudFile>[];

    // S3 使用 delimiter=/ 来模拟目录层级
    final stream = _client!.listObjects(
      _bucket!,
      prefix: prefix,
      recursive: false,
    );

    await for (final chunk in stream) {
      // 子目录（CommonPrefixes）
      for (final prefix in chunk.prefixes) {
        final name = _lastSegment(prefix);
        result.add(CloudFile(
          name: name,
          path: prefix,
          isDirectory: true,
          size: null,
          modifiedDate: null,
        ));
      }

      // 文件（Contents）
      for (final obj in chunk.objects) {
        // 跳过目录占位符本身（如 "folder/"）
        if (obj.key == prefix || (obj.key?.endsWith('/') == true && obj.size == 0)) {
          continue;
        }
        result.add(CloudFile(
          name: _lastSegment(obj.key ?? ''),
          path: obj.key ?? '',
          isDirectory: false,
          size: obj.size,
          modifiedDate: obj.lastModified,
        ));
      }
    }

    return result;
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    DownloadProgressCallback? onProgress,
    CloudCancelToken? cancelToken,
  }) async {
    if (_client == null || _bucket == null) throw StateError('S3 未连接');

    await Directory(p.dirname(localPath)).create(recursive: true);

    final stream = await _client!.getObject(_bucket!, remotePath);
    final file = File(localPath);
    final sink = file.openWrite();

    var received = 0;
    final total = stream.contentLength ?? 0;

    try {
      await for (final chunk in stream) {
        if (cancelToken?.isCancelled == true) {
          throw Exception('用户取消');
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received, total);
        }
      }
    } finally {
      await sink.close();
      if (cancelToken?.isCancelled == true) {
        try { await file.delete(); } catch (_) {}
      }
    }
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    if (_client == null || _bucket == null) throw StateError('S3 未连接');

    final file = File(localPath);
    if (!await file.exists()) {
      throw ArgumentError('本地文件不存在: $localPath');
    }

    final bytes = await file.readAsBytes();
    await _client!.putObject(
      _bucket!,
      remotePath,
      Stream.fromIterable([bytes]),
      size: bytes.length,
    );
  }

  @override
  Future<void> delete(String remotePath) async {
    if (_client == null || _bucket == null) throw StateError('S3 未连接');
    await _client!.removeObject(_bucket!, remotePath);
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    if (_client == null || _bucket == null) throw StateError('S3 未连接');

    // S3 中目录是虚拟的，创建一个空对象作为目录占位符
    final path = _ensureTrailingSlash(remotePath);
    await _client!.putObject(
      _bucket!,
      path,
      Stream.fromIterable([Uint8List(0)]),
      size: 0,
    );
  }

  @override
  String? getStreamUrl(String remotePath) {
    // S3 直接串流需要预签名 URL，暂不支持
    return null;
  }

  // ===================== 辅助方法 =====================

  String _ensureTrailingSlash(String path) {
    return path.endsWith('/') ? path : '$path/';
  }

  String _lastSegment(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }
}
