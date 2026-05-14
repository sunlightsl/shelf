import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/cloud_file.dart';
import 'cloud_storage.dart';

/// 媒体服务器（Jellyfin / Emby）共享基类
///
/// 两者 API 高度同源，差异主要在 apiBasePath 和少量字段名。
abstract class BaseMediaServerStorage implements CloudStorage {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  String? _serverUrl;
  String? _apiKey;
  String? _accessToken;
  String? _userId;

  String get _clientName => 'ShelfApp';
  String get _clientVersion => '1.0.0';

  /// API 路由前缀（Jellyfin: ''，Emby: '/emby'）
  String get apiBasePath;

  @override
  String get protocol;

  @override
  String get name;

  @override
  bool get isConnected =>
      _serverUrl != null && (_apiKey != null || _accessToken != null);

  // ── 认证 ──

  Future<void> _authenticate(Map<String, String> credentials) async {
    _serverUrl = credentials['serverUrl']?.trim();
    _apiKey = credentials['apiKey']?.trim();

    if (_serverUrl == null || _serverUrl!.isEmpty) {
      throw ArgumentError('服务器地址不能为空');
    }
    _serverUrl = _serverUrl!.replaceAll(RegExp(r'/+$'), '');

    if (_apiKey != null && _apiKey!.isNotEmpty) {
      _dio.options.headers['X-Emby-Token'] = _apiKey;
      await _validateApiKey();
    } else {
      final username = credentials['username'];
      final password = credentials['password'];
      if (username == null ||
          username.isEmpty ||
          password == null ||
          password.isEmpty) {
        throw ArgumentError('请提供 API Key 或用户名密码');
      }
      await _authenticateByPassword(username, password);
    }
  }

  Future<void> _validateApiKey() async {
    final data = await _get('/Users');
    final users = data as List<dynamic>?;
    if (users != null && users.isNotEmpty) {
      // 验证成功，保留 apiKey，并取第一个用户 ID
      _userId = users.first['Id'] as String?;
    }
  }

  Future<void> _authenticateByPassword(String username, String password) async {
    final authHeader =
        'MediaBrowser Client="$_clientName", Device="Flutter", '
        'DeviceId="shelf_device", Version="$_clientVersion"';

    final resp = await _dio.post(
      '$_serverUrl$apiBasePath/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      options: Options(headers: {'Authorization': authHeader}),
    );

    final data = resp.data as Map<String, dynamic>?;
    if (data == null) throw Exception('认证响应为空');

    _accessToken = data['AccessToken'] as String?;
    _userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;

    if (_accessToken == null) {
      throw Exception('认证失败，无法获取访问令牌');
    }
    _dio.options.headers['X-Emby-Token'] = _accessToken;
  }

  // ── HTTP 辅助 ──

  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    final resp = await _dio.get(
      '$_serverUrl$apiBasePath$path',
      queryParameters: query,
    );
    return resp.data;
  }

  // ── CloudStorage 实现 ──

  @override
  Future<bool> connect(Map<String, String> credentials) async {
    try {
      await _authenticate(credentials);
      return true;
    } catch (e) {
      debugPrint('$name 连接失败: $e');
      _serverUrl = null;
      _apiKey = null;
      _accessToken = null;
      _userId = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _serverUrl = null;
    _apiKey = null;
    _accessToken = null;
    _userId = null;
    _dio.options.headers.remove('X-Emby-Token');
  }

  @override
  Future<bool> testConnection() async {
    if (!isConnected) return false;
    try {
      await _get('/System/Info');
      return true;
    } catch (e) {
      debugPrint('$name 连接测试失败: $e');
      return false;
    }
  }

  @override
  Future<List<CloudFile>> listDirectory(String path) async {
    if (!isConnected) throw StateError('未连接');

    // 空路径 = 媒体库根列表
    if (path.isEmpty || path == '/' || path == 'root') {
      final data = await _get('/Library/MediaFolders');
      final items = data['Items'] as List<dynamic>? ?? [];
      return items.map((item) {
        final id = item['Id'] as String? ?? '';
        final name = item['Name'] as String? ?? 'Unknown';
        return CloudFile(name: name, path: id, isDirectory: true);
      }).toList();
    }

    // 列出指定目录下的项目
    final query = <String, dynamic>{
      'ParentId': path,
      'Fields': 'BasicFields,Path,MediaSources',
      'Recursive': 'false',
      'IncludeItemTypes': 'Folder,Video,Movie,Episode,Series,Season',
    };
    if (_userId != null) {
      query['UserId'] = _userId;
    }
    final data = await _get('/Items', query: query);

    final items = data['Items'] as List<dynamic>? ?? [];
    return items.map((item) {
      final id = item['Id'] as String? ?? '';
      final name = item['Name'] as String? ?? 'Unknown';
      final isFolder = item['IsFolder'] as bool? ?? false;
      return CloudFile(
        name: name,
        path: id,
        isDirectory: isFolder,
        size: _extractSize(item),
      );
    }).toList();
  }

  int? _extractSize(Map<String, dynamic> item) {
    final sources = item['MediaSources'] as List<dynamic>?;
    if (sources != null && sources.isNotEmpty) {
      final size = sources.first['Size'] as num?;
      if (size != null) return size.toInt();
    }
    return null;
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    DownloadProgressCallback? onProgress,
    CloudCancelToken? cancelToken,
  }) async {
    if (!isConnected) throw StateError('未连接');

    final url = getStreamUrl(remotePath);
    if (url == null) throw Exception('无法获取下载链接');

    await Directory(File(localPath).parent.path).create(recursive: true);

    await _dio.download(
      url,
      localPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received.toInt(), total.toInt());
        }
      },
    );
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    throw UnsupportedError('媒体服务器不支持上传');
  }

  @override
  Future<void> delete(String remotePath) async {
    throw UnsupportedError('媒体服务器不支持删除');
  }

  @override
  Future<void> createDirectory(String remotePath) async {
    throw UnsupportedError('媒体服务器不支持创建目录');
  }

  @override
  String? getStreamUrl(String remotePath) {
    if (_serverUrl == null) return null;
    final token = _apiKey ?? _accessToken;
    if (token == null) return null;
    return '$_serverUrl$apiBasePath/Items/$remotePath/Download?api_key=$token';
  }

  // ── 媒体库元数据同步（用于 CloudMediaSyncService）──

  /// 获取服务器上所有电影和剧集的元数据
  ///
  /// 返回扁平化的媒体条目列表，每个条目包含播放所需的所有信息。
  Future<List<CloudMediaItem>> getMediaLibraryItems() async {
    if (!isConnected) throw StateError('未连接');

    final items = <CloudMediaItem>[];

    // 1. 获取电影
    final moviesQuery = <String, dynamic>{
      'IncludeItemTypes': 'Movie',
      'Fields': 'Overview,ProviderIds,MediaSources,DateCreated,ProductionYear',
      'Recursive': 'true',
      if (_userId != null) 'UserId': _userId,
    };
    final moviesData = await _get('/Items', query: moviesQuery);
    final movies = moviesData['Items'] as List<dynamic>? ?? [];
    for (final item in movies) {
      final mediaItem = _parseMediaItem(item, 'Movie');
      if (mediaItem != null) items.add(mediaItem);
    }

    // 2. 获取剧集（Episode 级别）
    final episodesQuery = <String, dynamic>{
      'IncludeItemTypes': 'Episode',
      'Fields': 'Overview,ProviderIds,MediaSources,DateCreated,SeasonName,SeriesName,IndexNumber,ParentIndexNumber',
      'Recursive': 'true',
      if (_userId != null) 'UserId': _userId,
    };
    final episodesData = await _get('/Items', query: episodesQuery);
    final episodes = episodesData['Items'] as List<dynamic>? ?? [];
    for (final item in episodes) {
      final mediaItem = _parseMediaItem(item, 'Episode');
      if (mediaItem != null) items.add(mediaItem);
    }

    return items;
  }

  CloudMediaItem? _parseMediaItem(Map<String, dynamic> item, String type) {
    final id = item['Id'] as String?;
    final name = item['Name'] as String?;
    if (id == null || name == null) return null;

    final overview = item['Overview'] as String?;
    final year = item['ProductionYear'] as int?;
    final seriesName = item['SeriesName'] as String?;
    final seasonNumber = item['ParentIndexNumber'] as int?;
    final episodeNumber = item['IndexNumber'] as int?;

    // 封面图
    String? posterUrl;
    final primaryTag = item['ImageTags']?['Primary'] as String?;
    if (primaryTag != null) {
      posterUrl = '$_serverUrl$apiBasePath/Items/$id/Images/Primary?tag=$primaryTag';
    }

    // Backdrop
    String? backdropUrl;
    final backdropTags = item['BackdropImageTags'] as List<dynamic>?;
    if (backdropTags != null && backdropTags.isNotEmpty) {
      backdropUrl = '$_serverUrl$apiBasePath/Items/$id/Images/Backdrop?tag=${backdropTags.first}';
    }

    // 播放流地址
    final token = _apiKey ?? _accessToken;
    final streamUrl = token != null
        ? '$_serverUrl$apiBasePath/Items/$id/Download?api_key=$token'
        : null;

    // 文件大小
    int? fileSize;
    final sources = item['MediaSources'] as List<dynamic>?;
    if (sources != null && sources.isNotEmpty) {
      fileSize = (sources.first['Size'] as num?)?.toInt();
    }

    // 时长（分钟 -> 秒）
    int? runtimeSeconds;
    final runTimeTicks = item['RunTimeTicks'] as int?;
    if (runTimeTicks != null) {
      runtimeSeconds = (runTimeTicks / 10000000).toInt();
    }

    return CloudMediaItem(
      remoteId: id,
      title: name,
      type: type,
      overview: overview,
      year: year,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      streamUrl: streamUrl,
      fileSize: fileSize,
      runtimeSeconds: runtimeSeconds,
    );
  }

  String? get serverUrl => _serverUrl;
  String? get accessToken => _apiKey ?? _accessToken;
}

/// Jellyfin/Emby 媒体库条目（用于同步到本地数据库）
class CloudMediaItem {
  final String remoteId;
  final String title;
  final String type; // 'Movie' | 'Episode'
  final String? overview;
  final int? year;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? posterUrl;
  final String? backdropUrl;
  final String? streamUrl;
  final int? fileSize;
  final int? runtimeSeconds;

  CloudMediaItem({
    required this.remoteId,
    required this.title,
    required this.type,
    this.overview,
    this.year,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.posterUrl,
    this.backdropUrl,
    this.streamUrl,
    this.fileSize,
    this.runtimeSeconds,
  });

  /// 是否为电影
  bool get isMovie => type == 'Movie';

  /// 是否为剧集分集
  bool get isEpisode => type == 'Episode';

  /// 完整的系列名（剧集包含系列名 + 季集信息）
  String get displayTitle {
    if (isEpisode && seriesName != null) {
      final epLabel = seasonNumber != null && episodeNumber != null
          ? 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}'
          : '';
      return '$seriesName $epLabel';
    }
    return title;
  }
}
