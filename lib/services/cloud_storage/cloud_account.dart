/// 云存储账户配置
class CloudAccount {
  final String id;
  final String protocol;
  final String displayName;

  /// 非敏感配置（存储在 SharedPreferences）
  final Map<String, String> config;

  /// 上次同步时间（毫秒时间戳）
  final int? lastSyncAt;

  /// 根目录路径（云端）
  final String rootPath;

  CloudAccount({
    required this.id,
    required this.protocol,
    required this.displayName,
    this.config = const {},
    this.lastSyncAt,
    this.rootPath = '/',
  });

  CloudAccount copyWith({
    String? id,
    String? protocol,
    String? displayName,
    Map<String, String>? config,
    int? lastSyncAt,
    String? rootPath,
  }) {
    return CloudAccount(
      id: id ?? this.id,
      protocol: protocol ?? this.protocol,
      displayName: displayName ?? this.displayName,
      config: config ?? this.config,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      rootPath: rootPath ?? this.rootPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocol': protocol,
      'displayName': displayName,
      'config': config,
      'lastSyncAt': lastSyncAt,
      'rootPath': rootPath,
    };
  }

  factory CloudAccount.fromJson(Map<String, dynamic> json) {
    return CloudAccount(
      id: json['id'] as String,
      protocol: json['protocol'] as String,
      displayName: json['displayName'] as String,
      config: (json['config'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          {},
      lastSyncAt: json['lastSyncAt'] as int?,
      rootPath: json['rootPath'] as String? ?? '/',
    );
  }
}
