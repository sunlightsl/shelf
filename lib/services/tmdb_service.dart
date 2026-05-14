import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// TMDB 刮削结果
class TMDBSearchResult {
  final int id;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double voteAverage;
  final List<int> genreIds;
  final String mediaType; // 'movie' or 'tv'

  TMDBSearchResult({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage = 0.0,
    this.genreIds = const [],
    required this.mediaType,
  });
}

/// TMDB 详情
class TMDBDetails {
  final int id;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final int? runtime; // minutes
  final List<String> genres;
  final double voteAverage;
  final String? releaseDate;

  TMDBDetails({
    required this.id,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.runtime,
    this.genres = const [],
    this.voteAverage = 0.0,
    this.releaseDate,
  });
}

/// TMDB 演职人员
class TMDBCast {
  final int id;
  final String name;
  final String? character;
  final String? profilePath;
  final int? order;

  TMDBCast({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
    this.order,
  });
}

class TMDBCredits {
  final List<TMDBCast> cast;

  TMDBCredits({required this.cast});
}

/// TMDB 刮削服务
///
/// 使用前需设置 apiKey：
/// ```dart
/// TMDBService.instance.setApiKey('your_api_key');
/// ```
class TMDBService {
  static final TMDBService instance = TMDBService._internal();
  TMDBService._internal();

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _imageBaseUrl = 'https://image.tmdb.org/t/p';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  String? _apiKey;

  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  void setApiKey(String key) {
    _apiKey = key;
  }

  /// 搜索电影和剧集
  Future<List<TMDBSearchResult>> search(String query, {String language = 'zh-CN'}) async {
    if (!hasApiKey) return [];

    final results = <TMDBSearchResult>[];

    // 同时搜索电影和剧集
    await Future.wait([
      _searchMedia('movie', query, language).then((r) => results.addAll(r)),
      _searchMedia('tv', query, language).then((r) => results.addAll(r)),
    ]);

    // 按热度排序
    results.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    return results;
  }

  Future<List<TMDBSearchResult>> _searchMedia(String type, String query, String language) async {
    try {
      final resp = await _dio.get(
        '$_baseUrl/search/$type',
        queryParameters: {
          'api_key': _apiKey,
          'query': query,
          'language': language,
          'page': 1,
        },
      );

      final data = resp.data as Map<String, dynamic>?;
      final results = data?['results'] as List<dynamic>? ?? [];

      return results.map((item) {
        final map = item as Map<String, dynamic>;
        return TMDBSearchResult(
          id: map['id'] as int? ?? 0,
          title: map['title'] as String? ?? map['name'] as String? ?? '',
          originalTitle: map['original_title'] as String? ?? map['original_name'] as String?,
          overview: map['overview'] as String?,
          posterPath: map['poster_path'] as String?,
          backdropPath: map['backdrop_path'] as String?,
          releaseDate: map['release_date'] as String? ?? map['first_air_date'] as String?,
          voteAverage: (map['vote_average'] as num?)?.toDouble() ?? 0.0,
          genreIds: (map['genre_ids'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
          mediaType: type,
        );
      }).toList();
    } catch (e) {
      debugPrint('[TMDB] 搜索失败 ($type): $e');
      return [];
    }
  }

  /// 获取电影/剧集详情
  Future<TMDBDetails?> getDetails(int id, String mediaType, {String language = 'zh-CN'}) async {
    if (!hasApiKey) return null;

    try {
      final resp = await _dio.get(
        '$_baseUrl/$mediaType/$id',
        queryParameters: {
          'api_key': _apiKey,
          'language': language,
        },
      );

      final map = resp.data as Map<String, dynamic>;
      final genres = (map['genres'] as List<dynamic>?)?.map((g) => g['name'] as String).toList() ?? [];

      return TMDBDetails(
        id: map['id'] as int? ?? 0,
        title: map['title'] as String? ?? map['name'] as String? ?? '',
        overview: map['overview'] as String?,
        posterPath: map['poster_path'] as String?,
        backdropPath: map['backdrop_path'] as String?,
        runtime: map['runtime'] as int? ?? (map['episode_run_time'] as List<dynamic>?)?.firstOrNull as int?,
        genres: genres,
        voteAverage: (map['vote_average'] as num?)?.toDouble() ?? 0.0,
        releaseDate: map['release_date'] as String? ?? map['first_air_date'] as String?,
      );
    } catch (e) {
      debugPrint('[TMDB] 获取详情失败: $e');
      return null;
    }
  }

  /// 获取演职人员
  Future<TMDBCredits?> getCredits(int id, String mediaType, {String language = 'zh-CN'}) async {
    if (!hasApiKey) return null;

    try {
      final resp = await _dio.get(
        '$_baseUrl/$mediaType/$id/credits',
        queryParameters: {
          'api_key': _apiKey,
          'language': language,
        },
      );

      final map = resp.data as Map<String, dynamic>;
      final castList = (map['cast'] as List<dynamic>?) ?? [];

      final cast = castList.map((item) {
        final m = item as Map<String, dynamic>;
        return TMDBCast(
          id: m['id'] as int? ?? 0,
          name: m['name'] as String? ?? '',
          character: m['character'] as String?,
          profilePath: m['profile_path'] as String?,
          order: m['order'] as int?,
        );
      }).toList();

      // 按 order 排序，只取前 20 个
      cast.sort((a, b) => (a.order ?? 999).compareTo(b.order ?? 999));
      if (cast.length > 20) cast.removeRange(20, cast.length);

      return TMDBCredits(cast: cast);
    } catch (e) {
      debugPrint('[TMDB] 获取演职人员失败: $e');
      return null;
    }
  }

  /// 构建海报完整 URL
  static String? posterUrl(String? posterPath, {String size = 'w500'}) {
    if (posterPath == null || posterPath.isEmpty) return null;
    return '$_imageBaseUrl/$size$posterPath';
  }

  /// 从文件名提取搜索关键词
  ///
  /// 规则：
  /// 1. 去掉扩展名
  /// 2. 去掉常见的分辨率、编码、来源标记（如 1080p、BluRay、HDRip）
  /// 3. 去掉年份（如 (2023)）
  /// 4. 将点、下划线替换为空格
  static String extractQuery(String fileName) {
    var name = fileName;

    // 去掉扩展名
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) name = name.substring(0, dotIndex);

    // 去掉常见的标记
    final patterns = [
      RegExp(r'\d{3,4}[pP]|\dK', caseSensitive: false),
      RegExp(r'\d{3,4}x\d{3,4}'),
      RegExp(r'BluRay|BDRip|HDRip|WEB-DL|WEBRip|HDTV|DVDRip|CAM|TS|TC', caseSensitive: false),
      RegExp(r'H\.264|H\.265|HEVC|x264|x265|AVC', caseSensitive: false),
      RegExp(r'DD[Pp]?\d\.\d|AAC|DTS|AC3|FLAC', caseSensitive: false),
      RegExp(r'\(?\d{4}\)?'),
      RegExp(r'\[.*?\]'),
      RegExp(r'\{.*?\}'),
      RegExp(r'S\d{1,2}E\d{1,2}', caseSensitive: false),
      RegExp(r'第[一二三四五六七八九十\d]+季'),
      RegExp(r'第[一二三四五六七八九十\d]+集'),
    ];

    for (final pattern in patterns) {
      name = name.replaceAll(pattern, '');
    }

    // 将点、下划线替换为空格，去掉多余空格
    name = name.replaceAll(RegExp(r'[._\-]+'), ' ').trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ');

    return name;
  }
}
