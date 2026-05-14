import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as wd;
import '../../models/cloud_file.dart';
import 'cloud_storage.dart';

/// WebDAV 云存储实现
///
/// 支持：坚果云、AList、NAS 等所有标准 WebDAV 服务
class WebDavStorage implements CloudStorage {
  wd.Client? _client;
  String? _serverUrl;

  @override
  String get name => 'WebDAV';

  @override
  String get protocol => 'webdav';

  @override
  bool get isConnected => _client != null;

  @override
  Future<bool> connect(Map<String, String> credentials) async {
    final serverUrl = credentials['serverUrl'];
    final username = credentials['username'];
    final password = credentials['password'];

    if (serverUrl == null || serverUrl.isEmpty) {
      throw ArgumentError('WebDAV 服务器地址不能为空');
    }
    if (username == null || username.isEmpty) {
      throw ArgumentError('WebDAV 用户名不能为空');
    }
    if (password == null || password.isEmpty) {
      throw ArgumentError('WebDAV 密码不能为空');
    }

    try {
      _client = wd.newClient(
        serverUrl,
        user: username,
        password: password,
        debug: kDebugMode,
      );
      _serverUrl = serverUrl;

      // 测试连接
      return await testConnection();
    } catch (e) {
      debugPrint('WebDAV 连接失败: $e');
      _client = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _client = null;
    _serverUrl = null;
  }

  @override
  Future<bool> testConnection() async {
    if (_client == null) return false;
    try {
      await _client!.ping();
      return true;
    } catch (e) {
      debugPrint('WebDAV 连接测试失败: $e');
      return false;
    }
  }

  @override
  Future<List<CloudFile>> listDirectory(String path) async {
    if (_client == null) throw StateError('WebDAV 未连接');

    final files = await _client!.readDir(path);
    return files.map((f) {
      return CloudFile(
        name: f.name ?? p.basename(f.path ?? ''),
        path: f.path ?? '',
        isDirectory: f.isDir ?? false,
        size: f.size,
        modifiedDate: f.mTime is DateTime ? f.mTime as DateTime : (f.mTime != null ? DateTime.tryParse(f.mTime.toString()) : null),
        etag: f.eTag,
      );
    }).toList();
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    DownloadProgressCallback? onProgress,
    CloudCancelToken? cancelToken,
  }) async {
    if (_client == null) throw StateError('WebDAV 未连接');

    await Directory(p.dirname(localPath)).create(recursive: true);

    final dioToken = CancelToken();
    // 将 CloudCancelToken 与 dio CancelToken 关联
    Timer? timer;
    if (cancelToken != null) {
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (cancelToken.isCancelled && !dioToken.isCancelled) {
          dioToken.cancel(cancelToken.reason ?? '用户取消');
        }
      });
    }

    try {
      // 流式下载，避免大文件内存溢出
      await _client!.read2File(
        remotePath,
        localPath,
        onProgress: (count, total) {
          onProgress?.call(count, total);
        },
        cancelToken: dioToken,
      );
    } finally {
      timer?.cancel();
    }
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    if (_client == null) throw StateError('WebDAV 未连接');

    final file = File(localPath);
    if (!await file.exists()) {
      throw ArgumentError('本地文件不存在: $localPath');
    }

    await _client!.writeFromFile(localPath, remotePath);
  }

  @override
  Future<void> delete(String remotePath) async {
    if (_client == null) throw StateError('WebDAV 未连接');
    await _client!.remove(remotePath);
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    if (_client == null) throw StateError('WebDAV 未连接');
    await _client!.mkdir(remotePath);
  }

  @override
  String? getStreamUrl(String remotePath) {
    if (_client == null || _serverUrl == null) return null;
    // WebDAV 文件可直接通过 HTTP(S) URL 访问
    // 拼接 serverUrl 和 remotePath，去除重复斜杠
    final base = _serverUrl!.endsWith('/') ? _serverUrl!.substring(0, _serverUrl!.length - 1) : _serverUrl!;
    final path = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    return '$base$path';
  }
}
