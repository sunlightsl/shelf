import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/cloud_file.dart';
import 'cloud_storage.dart';

/// 阿里云盘存储实现（框架版）
///
/// 阿里云盘开放平台 API: https://www.aliyundrive.com/developer
/// 认证方式: OAuth2 refresh_token
///
/// 使用方式:
/// 1. 用户从网页登录阿里云盘，获取 refresh_token
/// 2. 将 refresh_token 填入应用
/// 3. 应用用 refresh_token 换取 access_token，然后调用 API
///
/// 注意: 阿里云盘 API 经常变动，此实现基于公开 API 文档。
/// 如遇接口变更，需同步更新。
class AliyunDriveStorage implements CloudStorage {
  static const _authUrl = 'https://auth.aliyundrive.com/v2/account/token';
  static const _baseUrl = 'https://api.aliyundrive.com';

  String? _refreshToken;
  String? _accessToken;
  DateTime? _expiredAt;
  String? _driveId;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  @override
  String get name => '阿里云盘';

  @override
  String get protocol => 'aliyundrive';

  @override
  bool get isConnected => _accessToken != null && !_isTokenExpired && _driveId != null;

  bool get _isTokenExpired {
    final expiredAt = _expiredAt;
    if (expiredAt == null) return true;
    return DateTime.now().isAfter(expiredAt.subtract(const Duration(minutes: 5)));
  }

  @override
  Future<bool> connect(Map<String, String> credentials) async {
    _refreshToken = credentials['refreshToken'];

    if (_refreshToken == null || _refreshToken!.isEmpty) {
      throw ArgumentError('阿里云盘 refresh_token 不能为空');
    }

    try {
      await _refreshAccessToken();
      await _getDriveInfo();
      return true;
    } catch (e) {
      debugPrint('阿里云盘连接失败: $e');
      _accessToken = null;
      _driveId = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _expiredAt = null;
    _driveId = null;
  }

  @override
  Future<bool> testConnection() async {
    if (_accessToken == null || _driveId == null) return false;
    if (_isTokenExpired) {
      try {
        await _refreshAccessToken();
      } catch (_) {
        return false;
      }
    }
    try {
      // 尝试获取根目录文件列表
      await _post('/v2/file/list', {
        'drive_id': _driveId,
        'parent_file_id': 'root',
        'limit': 1,
      });
      return true;
    } catch (e) {
      debugPrint('阿里云盘连接测试失败: $e');
      return false;
    }
  }

  /// 用 refresh_token 换取 access_token
  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) {
      throw StateError('refresh_token 未设置');
    }

    final resp = await _dio.post(
      _authUrl,
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken,
      },
    );

    final data = resp.data;
    if (data == null) {
      throw Exception('响应为空');
    }

    _accessToken = data['access_token'] as String?;
    final newRefreshToken = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 7200;

    if (_accessToken == null) {
      throw Exception('access_token 为空');
    }

    // 更新 refresh_token（阿里云盘每次刷新都会返回新的）
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      _refreshToken = newRefreshToken;
    }

    _expiredAt = DateTime.now().add(Duration(seconds: expiresIn));
  }

  /// 获取默认 drive_id（直接请求，避免与 _post/_ensureAuthenticated 形成递归）
  Future<void> _getDriveInfo() async {
    if (_accessToken == null) {
      throw StateError('access_token 未设置');
    }

    final resp = await _dio.post(
      '$_baseUrl/v2/user/get',
      data: {},
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );

    final data = resp.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('响应为空');
    }
    if (data['code'] != null) {
      throw Exception('API 错误: ${data['message'] ?? '未知错误'}');
    }

    // 优先使用资源盘（resource_drive_id），没有则回退到默认盘
    _driveId = data['resource_drive_id'] as String?
        ?? data['default_drive_id'] as String?;
    if (_driveId == null) {
      throw Exception('无法获取 drive_id');
    }
  }

  Future<void> _ensureAuthenticated() async {
    if (_accessToken == null || _isTokenExpired) {
      await _refreshAccessToken();
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    await _ensureAuthenticated();
    if (_driveId == null) {
      throw StateError('未获取 drive_id，请先调用 connect()');
    }

    final resp = await _dio.post(
      '$_baseUrl$path',
      data: data,
      options: Options(headers: {'Authorization': 'Bearer $_accessToken'}),
    );

    final responseData = resp.data;
    if (responseData == null) {
      throw Exception('响应为空');
    }

    if (responseData['code'] != null) {
      throw Exception('API 错误: ${responseData['message'] ?? '未知错误'}');
    }

    return responseData as Map<String, dynamic>;
  }

  @override
  Future<List<CloudFile>> listDirectory(String path) async {
    await _ensureAuthenticated();

    final parentFileId = path.isEmpty || path == '/' || path == 'root' ? 'root' : path;
    final List<CloudFile> result = [];
    String? marker;

    while (true) {
      final data = await _post('/v2/file/list', {
        'drive_id': _driveId,
        'parent_file_id': parentFileId,
        'limit': 200,
        if (marker != null) 'marker': marker,
      });

      final items = data['items'] as List<dynamic>? ?? [];

      for (final item in items) {
        final fileId = item['file_id'] as String? ?? '';
        final fileName = item['name'] as String? ?? 'unknown';
        final type = item['type'] as String? ?? 'file'; // file | folder
        final size = (item['size'] as num?)?.toInt();
        final updatedAt = item['updated_at'] as String?;

        result.add(CloudFile(
          name: fileName,
          path: fileId,
          isDirectory: type == 'folder',
          size: size,
          modifiedDate: updatedAt != null ? DateTime.tryParse(updatedAt) : null,
        ));
      }

      final nextMarker = data['next_marker'] as String?;
      if (nextMarker == null || nextMarker.isEmpty || items.isEmpty) break;
      marker = nextMarker;
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
    await _ensureAuthenticated();

    // 1. 获取下载链接
    final downloadData = await _post('/v2/file/get_download_url', {
      'drive_id': _driveId,
      'file_id': remotePath,
    });

    final downloadUrl = downloadData['url'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('无法获取下载链接');
    }

    // 2. 流式下载
    await Directory(File(localPath).parent.path).create(recursive: true);

    final dioToken = CancelToken();
    if (cancelToken != null) {
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
    throw UnsupportedError('阿里云盘上传功能暂未实现');
  }

  @override
  Future<void> delete(String remotePath) async {
    await _ensureAuthenticated();
    await _post('/v2/recyclebin/trash', {
      'drive_id': _driveId,
      'file_id': remotePath,
    });
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    throw UnsupportedError('阿里云盘创建目录功能暂未实现');
  }

  @override
  String? getStreamUrl(String remotePath) {
    // 阿里云盘下载链接需要异步获取，同步方法返回 null
    return null;
  }

  /// 异步获取串流 URL
  Future<String?> getStreamUrlAsync(String remotePath) async {
    try {
      final data = await _post('/adrive/v1.0/openFile/getDownloadUrl', {
        'drive_id': _driveId,
        'file_id': remotePath,
      });
      return data['url'] as String?;
    } catch (e) {
      debugPrint('获取阿里云盘串流链接失败: $e');
      return null;
    }
  }
}
