import 'base_media_storage.dart';

/// Emby 媒体服务器实现
///
/// 基于 Emby REST API，默认端口 8096。
/// 支持 API Key 或用户名密码认证。
///
/// 与 Jellyfin API 高度同源，差异主要在 API 路由前缀。
class EmbyStorage extends BaseMediaServerStorage {
  @override
  String get name => 'Emby';

  @override
  String get protocol => 'emby';

  /// Emby API 使用 /emby 前缀
  @override
  String get apiBasePath => '/emby';
}
