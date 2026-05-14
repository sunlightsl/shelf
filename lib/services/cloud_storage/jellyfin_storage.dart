import 'base_media_storage.dart';

/// Jellyfin 媒体服务器实现
///
/// 基于 Jellyfin REST API，默认端口 8096。
/// 支持 API Key 或用户名密码认证。
///
/// API 文档：https://api.jellyfin.org/
class JellyfinStorage extends BaseMediaServerStorage {
  @override
  String get name => 'Jellyfin';

  @override
  String get protocol => 'jellyfin';

  /// Jellyfin API 无需额外前缀
  @override
  String get apiBasePath => '';
}
