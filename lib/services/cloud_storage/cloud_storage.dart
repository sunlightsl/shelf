import '../../models/cloud_file.dart';

/// 取消令牌
class CloudCancelToken {
  bool _isCancelled = false;
  String? _reason;

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  void cancel([String? reason]) {
    _isCancelled = true;
    _reason = reason;
  }
}

/// 云存储统一抽象接口
///
/// 所有云存储协议（WebDAV、阿里云盘、百度网盘等）均实现此接口。
abstract class CloudStorage {
  /// 协议名称（如 "WebDAV"、"阿里云盘"）
  String get name;

  /// 协议标识（如 "webdav"、"aliyun"）
  String get protocol;

  /// 当前是否已连接
  bool get isConnected;

  /// 连接云存储服务
  ///
  /// [credentials] 必须包含协议所需字段：
  /// - WebDAV: serverUrl, username, password
  /// - 阿里云盘: accessToken, refreshToken
  Future<bool> connect(Map<String, String> credentials);

  /// 断开连接
  Future<void> disconnect();

  /// 测试连接是否可用
  Future<bool> testConnection();

  /// 列出目录内容
  ///
  /// [path] 云端路径，如 "/dav/小说/"
  Future<List<CloudFile>> listDirectory(String path);

  /// 下载文件到本地
  ///
  /// [remotePath] 云端文件路径
  /// [localPath] 本地保存路径
  /// [onProgress] 可选的进度回调
  /// [cancelToken] 可选的取消令牌
  Future<void> download(
    String remotePath,
    String localPath, {
    DownloadProgressCallback? onProgress,
    CloudCancelToken? cancelToken,
  });

  /// 上传本地文件到云端
  ///
  /// [localPath] 本地文件路径
  /// [remotePath] 云端目标路径
  Future<void> upload(String localPath, String remotePath);

  /// 删除云端文件/文件夹
  Future<void> delete(String remotePath);

  /// 创建云端文件夹
  Future<void> createDirectory(String remotePath);

  /// 获取可直接串流播放的 URL（如 HTTP URL）
  ///
  /// 返回 null 表示该协议不支持直接串流
  String? getStreamUrl(String remotePath);
}
