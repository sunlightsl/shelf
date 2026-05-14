import 'webdav_storage.dart';

/// 飞牛OS (FnOS) 轻量集成
///
/// 飞牛OS 底层通过 WebDAV 协议通信，默认端口：
/// - HTTP: 5005
/// - HTTPS: 5006
///
/// 用户需在飞牛OS 设置中开启 WebDAV 服务。
/// 此实现继承 WebDavStorage，仅提供品牌层包装。
class FnOSStorage extends WebDavStorage {
  @override
  String get name => '飞牛OS';

  @override
  String get protocol => 'fnos';
}
