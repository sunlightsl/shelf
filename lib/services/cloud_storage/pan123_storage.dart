import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/cloud_file.dart';
import 'cloud_storage.dart';

/// 123云盘存储实现
///
/// API 文档: https://www.123pan.com/open
/// Base URL: https://open-api.123pan.com
class Pan123Storage implements CloudStorage {
  static const _baseUrl = 'https://open-api.123pan.com';

  String? _clientId;
  String? _clientSecret;
  String? _accessToken;
  DateTime? _expiredAt;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Platform': 'open_platform',
      'Content-Type': 'application/json',
    },
  ));

  @override
  String get name => '123云盘';

  @override
  String get protocol => 'pan123';

  @override
  bool get isConnected => _accessToken != null && !_isTokenExpired;

  bool get _isTokenExpired {
    if (_expiredAt == null) return true;
    return DateTime.now().isAfter(_expiredAt!);
  }

  @override
  Future<bool> connect(Map<String, String> credentials) async {
    _clientId = credentials['clientId'];
    _clientSecret = credentials['clientSecret'];

    if (_clientId == null || _clientId!.isEmpty) {
      throw ArgumentError('123云盘 Client ID 不能为空');
    }
    if (_clientSecret == null || _clientSecret!.isEmpty) {
      throw ArgumentError('123云盘 Client Secret 不能为空');
    }

    try {
      await _refreshToken();
      return true;
    } catch (e) {
      debugPrint('123云盘连接失败: $e');
      _accessToken = null;
      _expiredAt = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _accessToken = null;
    _expiredAt = null;
    _clientId = null;
    _clientSecret = null;
  }

  @override
  Future<bool> testConnection() async {
    if (_accessToken == null) return false;
    if (_isTokenExpired) {
      try {
        await _refreshToken();
      } catch (_) {
        return false;
      }
    }
    try {
      // 尝试获取用户信息来验证 token
      final resp = await _dio.get(
        '/api/v1/user/info',
        options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
      );
      return resp.data?['code'] == 0;
    } catch (e) {
      debugPrint('123云盘连接测试失败: $e');
      return false;
    }
  }

  /// 获取/刷新 access_token
  Future<void> _refreshToken() async {
    if (_clientId == null || _clientSecret == null) {
      throw StateError('Client ID 和 Client Secret 未设置');
    }

    final resp = await _dio.post(
      '/api/v1/access_token',
      data: {
        'clientID': _clientId,
        'clientSecret': _clientSecret,
      },
    );

    final data = resp.data;
    if (data == null || data['code'] != 0) {
      throw Exception('获取 access_token 失败: ${data?['message'] ?? '未知错误'}');
    }

    final tokenData = data['data'];
    _accessToken = tokenData['accessToken'] as String?;
    final expiredAtStr = tokenData['expiredAt'] as String?;

    if (_accessToken == null) {
      throw Exception('access_token 为空');
    }

    if (expiredAtStr != null) {
      _expiredAt = DateTime.tryParse(expiredAtStr);
    }
    // 默认 2 小时过期，提前 5 分钟刷新
    _expiredAt ??= DateTime.now().add(const Duration(hours: 1, minutes: 55));
  }

  Future<void> _ensureAuthenticated() async {
    if (_accessToken == null || _isTokenExpired) {
      await _refreshToken();
    }
  }

  Future<T> _request<T>(
    String method,
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? data,
    required T Function(dynamic) parser,
  }) async {
    await _ensureAuthenticated();

    final resp = await _dio.request(
      path,
      queryParameters: queryParameters,
      data: data,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer $_accessToken'},
      ),
    );

    final responseData = resp.data;
    if (responseData == null) {
      throw Exception('响应为空');
    }

    if (responseData['code'] != 0) {
      throw Exception('API 错误: ${responseData['message'] ?? '未知错误'} (code: ${responseData['code']})');
    }

    return parser(responseData['data']);
  }

  @override
  Future<List<CloudFile>> listDirectory(String path) async {
    // 123云盘用 parentFileId 标识目录，0 是根目录
    final parentFileId = int.tryParse(path) ?? 0;

    final List<CloudFile> result = [];
    int? lastFileId;

    while (true) {
      final params = <String, dynamic>{
        'parentFileId': parentFileId,
        'limit': 100,
      };
      if (lastFileId != null) {
        params['lastFileId'] = lastFileId;
      }

      final data = await _request(
        'GET',
        '/api/v2/file/list',
        queryParameters: params,
        parser: (d) => d,
      );

      final fileList = data['fileList'] as List<dynamic>? ?? [];

      for (final file in fileList) {
        final fileId = (file['fileId'] as num?)?.toInt() ?? 0;
        final filename = file['filename'] as String? ?? 'unknown';
        final type = file['type'] as int? ?? 0; // 0=file, 1=folder
        final size = (file['size'] as num?)?.toInt();
        final updatedAt = file['updatedAt'] as String?;

        result.add(CloudFile(
          name: filename,
          path: fileId.toString(), // 用 fileId 作为路径标识
          isDirectory: type == 1,
          size: size,
          modifiedDate: updatedAt != null ? DateTime.tryParse(updatedAt) : null,
        ));
      }

      final hasMore = data['next'] as bool? ?? false;
      if (!hasMore || fileList.isEmpty) break;

      // 获取最后一个文件的 ID 用于分页
      final lastFile = fileList.last;
      lastFileId = (lastFile['fileId'] as num?)?.toInt();
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
    final fileId = int.tryParse(remotePath);
    if (fileId == null) throw ArgumentError('无效的 fileId: $remotePath');

    // 1. 获取下载链接
    final downloadInfo = await _request(
      'GET',
      '/api/v1/file/download_info',
      queryParameters: {'fileId': fileId},
      parser: (d) => d,
    );

    final downloadUrl = downloadInfo['downloadUrl'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('无法获取下载链接');
    }

    // 2. 流式下载到本地
    await Directory(File(localPath).parent.path).create(recursive: true);

    final dioToken = CancelToken();
    if (cancelToken != null) {
      // 监听取消
      Timer? timer;
      timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (cancelToken.isCancelled && !dioToken.isCancelled) {
          dioToken.cancel(cancelToken.reason ?? '用户取消');
          timer?.cancel();
        }
      });
    }

    try {
      await _dio.download(
        downloadUrl,
        localPath,
        cancelToken: dioToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received, total);
          }
        },
      );
    } finally {
      if (cancelToken?.isCancelled == true) {
        try { await File(localPath).delete(); } catch (_) {}
      }
    }
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    // 123云盘上传较复杂，需要分片上传，暂不实现
    throw UnsupportedError('123云盘上传功能暂未实现');
  }

  @override
  Future<void> delete(String remotePath) async {
    final fileId = int.tryParse(remotePath);
    if (fileId == null) throw ArgumentError('无效的 fileId: $remotePath');

    await _request(
      'POST',
      '/api/v1/file/trash',
      data: {'fileIDs': [fileId]},
      parser: (d) => d,
    );
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    // 123云盘创建目录: POST /api/v1/file/upload
    // 需要指定 filename 和 type=1
    throw UnsupportedError('123云盘创建目录功能暂未实现');
  }

  @override
  String? getStreamUrl(String remotePath) {
    // 123云盘需要先获取 download_info 才能得到下载链接
    // 同步方法无法发起 HTTP 请求，返回 null
    // 如需串流，需先异步获取 downloadUrl
    return null;
  }

  /// 异步获取串流 URL（用于视频直接播放）
  Future<String?> getStreamUrlAsync(String remotePath) async {
    final fileId = int.tryParse(remotePath);
    if (fileId == null) return null;

    try {
      final downloadInfo = await _request(
        'GET',
        '/api/v1/file/download_info',
        queryParameters: {'fileId': fileId},
        parser: (d) => d,
      );
      return downloadInfo['downloadUrl'] as String?;
    } catch (e) {
      debugPrint('获取 123云盘串流链接失败: $e');
      return null;
    }
  }
}
