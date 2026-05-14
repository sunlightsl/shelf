import 'package:path/path.dart' as p;

/// 视频文件名解析结果
class VideoParseResult {
  final String seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String episodeTitle;

  const VideoParseResult({
    required this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle = '',
  });

  bool get hasEpisodeInfo => seasonNumber != null || episodeNumber != null;

  String get displayLabel {
    if (seasonNumber != null && episodeNumber != null) {
      return 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
    }
    if (episodeNumber != null) {
      return '第 $episodeNumber 集';
    }
    return '';
  }
}

/// 视频文件名解析器
///
/// 支持从常见命名格式中提取剧集信息：
/// - 美剧: Game.of.Thrones.S01E05.mkv, 权力的游戏 S01E05.mp4
/// - 日漫: [SubGroup] Series - 01 [1080p].mkv
/// - 国产剧: 三体_第01集.mp4, 狂飙.E12.mkv
class VideoFilenameParser {
  /// 解析视频文件名
  static VideoParseResult parse(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);

    // 1. 尝试匹配 S01E05 / S1E5 / 第1季第5集 模式
    final seasonEpisode = _parseSeasonEpisode(fileName);

    // 2. 提取系列名（去掉季集信息后剩余的部分）
    final seriesName = _extractSeriesName(fileName, seasonEpisode);

    // 3. 尝试提取单集标题（如 S01E05_The.Title）
    final episodeTitle = _extractEpisodeTitle(fileName, seasonEpisode);

    return VideoParseResult(
      seriesName: seriesName.isNotEmpty ? seriesName : fileName,
      seasonNumber: seasonEpisode?['season'],
      episodeNumber: seasonEpisode?['episode'],
      episodeTitle: episodeTitle,
    );
  }

  /// 匹配季集模式，返回 {season, episode} 或 null
  static Map<String, int>? _parseSeasonEpisode(String name) {
    final patterns = [
      // S01E05, S1E5, s01e05
      RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})'),
      // 第1季第5集, 第一季第五集
      RegExp(r'第?\s*(\d{1,2})\s*季\s*第?\s*(\d{1,3})\s*集'),
      // 01x05 (美剧旧格式)
      RegExp(r'(\d{1,2})[xX](\d{1,3})'),
      // E05, EP05, e05, ep05 (无季号，只匹配集号)
      RegExp(r'[Ee][Pp]?(\d{1,3})'),
      // 第05集, 第五集
      RegExp(r'第\s*(\d{1,3})\s*集'),
      // - 05, _05 (空格/下划线/连字符后跟数字，可能是集号)
      RegExp(r'[-_\s]\s*(\d{1,3})\s*(?:[_\s]|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        final fullMatch = match.group(0)!;
        final group1 = match.group(1);
        final group2 = match.groupCount >= 2 ? match.group(2) : null;

        int? season;
        int? episode;

        if (group2 != null) {
          // S01E05 模式：两组数字
          season = int.tryParse(group1!);
          episode = int.tryParse(group2);
        } else if (group1 != null) {
          // 只匹配到一组数字
          final num = int.tryParse(group1);
          if (num != null) {
            // 如果数字在 1980-2030 之间，通常认为是年份，忽略
            if (num >= 1980 && num <= 2030) continue;
            episode = num;
          }
        }

        if (season != null || episode != null) {
          return {'season': season ?? 1, 'episode': episode ?? 0};
        }
      }
    }

    return null;
  }

  /// 从文件名中提取系列名（去掉季集号、分辨率、来源标记等）
  static String _extractSeriesName(String fileName, Map<String, int>? seasonEpisode) {
    var name = fileName;

    // 去掉季集标记
    if (seasonEpisode != null) {
      final patterns = [
        RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}', caseSensitive: false),
        RegExp(r'第?\s*\d{1,2}\s*季\s*第?\s*\d{1,3}\s*集'),
        RegExp(r'\d{1,2}[xX]\d{1,3}'),
        RegExp(r'[Ee][Pp]?\d{1,3}'),
        RegExp(r'第\s*\d{1,3}\s*集'),
      ];
      for (final pattern in patterns) {
        name = name.replaceAll(pattern, '');
      }
    }

    // 去掉常见后缀标记
    final cleanupPatterns = [
      RegExp(r'\d{4}'), // 年份
      RegExp(r'\d{3,4}[Pp]'), // 分辨率 1080p, 720P
      RegExp(r'[Bb]lu[-]?[Rr]ay'), // BluRay
      RegExp(r'[Ww][Ee][Bb]'), // WEB
      RegExp(r'[Hh][Dd][Tt][Vv]'), // HDTV
      RegExp(r'\[[^\]]*\]'), // [SubGroup] 等括号内容
      RegExp(r'\([^\)]*\)'), // (内容)
      RegExp(r'[_\-.]+$'), // 尾部多余的符号
      RegExp(r'^[_\-.]+'), // 头部多余的符号
    ];

    for (final pattern in cleanupPatterns) {
      name = name.replaceAll(pattern, '');
    }

    // 将点、下划线替换为空格
    name = name.replaceAll(RegExp(r'[._]'), ' ').trim();

    // 去掉多余的空格
    name = name.replaceAll(RegExp(r'\s+'), ' ');

    return name;
  }

  /// 提取单集标题
  static String _extractEpisodeTitle(String fileName, Map<String, int>? seasonEpisode) {
    if (seasonEpisode == null) return '';

    // 在季集标记之后的内容通常是集标题
    final match = RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}[_\s-]*(.+)', caseSensitive: false)
        .firstMatch(fileName);
    if (match != null) {
      var title = match.group(1)!;
      // 清理尾部扩展名和标记
      title = title.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      title = title.replaceAll(RegExp(r'[_\-.]+$'), '');
      title = title.replaceAll(RegExp(r'[._]'), ' ').trim();
      return title;
    }

    return '';
  }
}
