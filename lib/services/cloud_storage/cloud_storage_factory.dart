import 'cloud_storage.dart';
import 's3_storage.dart';
import 'webdav_storage.dart';
import 'pan123_storage.dart';
import 'aliyundrive_storage.dart';
import 'jellyfin_storage.dart';
import 'emby_storage.dart';
import 'fnos_storage.dart';

/// 云存储实例工厂
class CloudStorageFactory {
  static CloudStorage create(String protocol) {
    return switch (protocol) {
      'webdav' => WebDavStorage(),
      's3' => S3Storage(),
      'pan123' => Pan123Storage(),
      'aliyundrive' => AliyunDriveStorage(),
      'jellyfin' => JellyfinStorage(),
      'emby' => EmbyStorage(),
      'fnos' => FnOSStorage(),
      _ => throw UnsupportedError('不支持的云存储协议: $protocol'),
    };
  }

  static List<String> get supportedProtocols =>
      ['webdav', 's3', 'pan123', 'aliyundrive', 'jellyfin', 'emby', 'fnos'];

  static String getProtocolName(String protocol) {
    return switch (protocol) {
      'webdav' => 'WebDAV',
      's3' => 'S3 / MinIO',
      'pan123' => '123云盘',
      'aliyundrive' => '阿里云盘',
      'jellyfin' => 'Jellyfin',
      'emby' => 'Emby',
      'fnos' => '飞牛OS',
      _ => protocol,
    };
  }

  /// 获取协议的描述信息
  static String getProtocolDescription(String protocol) {
    return switch (protocol) {
      'webdav' => '坚果云、AList、NAS 等',
      's3' => 'AWS S3、MinIO、阿里云 OSS 等',
      'pan123' => '需前往 123pan.com 开放平台申请',
      'aliyundrive' => '需自行获取 refresh_token',
      'jellyfin' => '本地或远程 Jellyfin 服务器',
      'emby' => '本地或远程 Emby 服务器',
      'fnos' => '通过 WebDAV 连接飞牛OS，默认端口 5005',
      _ => '',
    };
  }

  /// 获取协议需要的配置字段
  static List<ProtocolField> getProtocolFields(String protocol) {
    return switch (protocol) {
      'webdav' => [
        ProtocolField(key: 'serverUrl', label: '服务器地址', placeholder: 'https://dav.jianguoyun.com/dav/'),
        ProtocolField(key: 'username', label: '用户名', placeholder: '用户名'),
        ProtocolField(key: 'password', label: '密码 / 应用密码', placeholder: '密码', isSecret: true),
      ],
      's3' => [
        ProtocolField(key: 'endPoint', label: 'Endpoint', placeholder: 's3.amazonaws.com'),
        ProtocolField(key: 'accessKey', label: 'Access Key', placeholder: 'Access Key'),
        ProtocolField(key: 'secretKey', label: 'Secret Key', placeholder: 'Secret Key', isSecret: true),
        ProtocolField(key: 'bucket', label: 'Bucket 名称', placeholder: 'my-bucket'),
      ],
      'pan123' => [
        ProtocolField(key: 'clientId', label: 'Client ID', placeholder: '从 123云盘开放平台获取'),
        ProtocolField(key: 'clientSecret', label: 'Client Secret', placeholder: '从 123云盘开放平台获取', isSecret: true),
      ],
      'aliyundrive' => [
        ProtocolField(key: 'refreshToken', label: 'Refresh Token', placeholder: '粘贴 refresh_token', isSecret: true, helperText: '在阿里云盘网页版登录后从浏览器控制台获取'),
      ],
      'jellyfin' => [
        ProtocolField(key: 'serverUrl', label: '服务器地址', placeholder: 'http://192.168.1.100:8096'),
        ProtocolField(key: 'apiKey', label: 'API Key', placeholder: '从 Jellyfin 控制台获取', isSecret: true, helperText: '推荐方式：管理控制台 → 高级 → API 密钥'),
        ProtocolField(key: 'username', label: '用户名', placeholder: '备用：用户名认证'),
        ProtocolField(key: 'password', label: '密码', placeholder: '备用：密码', isSecret: true),
      ],
      'emby' => [
        ProtocolField(key: 'serverUrl', label: '服务器地址', placeholder: 'http://192.168.1.100:8096'),
        ProtocolField(key: 'apiKey', label: 'API Key', placeholder: '从 Emby 控制台获取', isSecret: true, helperText: '推荐方式：管理控制台 → 高级 → API 密钥'),
        ProtocolField(key: 'username', label: '用户名', placeholder: '备用：用户名认证'),
        ProtocolField(key: 'password', label: '密码', placeholder: '备用：密码', isSecret: true),
      ],
      'fnos' => [
        ProtocolField(key: 'serverUrl', label: '服务器地址', placeholder: 'http://192.168.1.100:5005', helperText: '飞牛OS 需在设置中开启 WebDAV 服务，默认端口 5005（HTTP）或 5006（HTTPS）'),
        ProtocolField(key: 'username', label: '用户名', placeholder: '飞牛OS 账号'),
        ProtocolField(key: 'password', label: '密码', placeholder: '飞牛OS 密码', isSecret: true),
      ],
      _ => [],
    };
  }
}

/// 协议配置字段定义
class ProtocolField {
  final String key;
  final String label;
  final String placeholder;
  final bool isSecret;
  final String? helperText;

  const ProtocolField({
    required this.key,
    required this.label,
    required this.placeholder,
    this.isSecret = false,
    this.helperText,
  });
}
