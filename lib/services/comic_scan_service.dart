import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/comic_chapter.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';

class ChapterParseResult {
  final String title;
  final double? chapterNumber;
  final int? volumeNumber;

  ChapterParseResult({
    required this.title,
    this.chapterNumber,
    this.volumeNumber,
  });
}

class ComicScanService {
  static final List<String> _comicExts = ['.zip', '.cbz', '.rar', '.cbr', '.pdf', '.mobi', '.azw3'];
  static final List<String> _imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

  static bool isComicFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _comicExts.contains(ext);
  }

  static bool isImageFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return _imageExts.contains(ext);
  }

  /// 扫描一个目录，返回检测到的系列列表
  static Future<List<ComicScanResult>> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final results = <ComicScanResult>[];
    final entities = await dir.list().toList();

    for (final entity in entities) {
      if (entity is Directory) {
        final result = await scanFolder(entity);
        if (result != null) results.add(result);
      } else if (entity is File && isComicFile(entity.path)) {
        final result = await scanSingleFile(entity);
        results.add(result);
      }
    }

    return results;
  }

  /// 扫描文件夹，递归收集所有子文件夹中的漫画文件
  ///
  /// 顶层文件夹 = ComicSeries，子文件夹内容统一归属该系列。
  /// 子文件夹名解析为 volumeName/volumeNumber，但数据库层面不拆分为子系列。
  static Future<ComicScanResult?> scanFolder(Directory dir) async {
    final allComicFiles = <_ComicFileWithVolume>[];
    final imageFiles = <File>[];

    await _collectFilesRecursive(dir, dir, allComicFiles, imageFiles);

    if (allComicFiles.isNotEmpty) {
      // folderSeries: 文件夹 = 系列，内部所有文件（含嵌套）= 章节
      allComicFiles.sort((a, b) => p.basename(a.file.path).compareTo(p.basename(b.file.path)));

      final chapters = <ComicChapter>[];
      for (int i = 0; i < allComicFiles.length; i++) {
        final entry = allComicFiles[i];
        final parsed = parseFilename(p.basename(entry.file.path));
        final format = getFormatFromPath(entry.file.path);

        // 子文件夹名解析为卷号（兜底）
        int? volumeNum = parsed.volumeNumber ?? entry.volumeNumber;

        chapters.add(ComicChapter(
          seriesId: 0,
          title: parsed.title,
          chapterNumber: parsed.chapterNumber,
          volumeNumber: volumeNum,
          filePath: entry.file.path,
          format: format,
          fileSize: await entry.file.length(),
          sortOrder: i,
        ));
      }

      return ComicScanResult(
        series: ComicSeries(
          title: p.basename(dir.path),
          folderPath: dir.path,
          sourceType: ComicSourceType.folderSeries,
        ),
        chapters: chapters,
      );
    } else if (imageFiles.isNotEmpty) {
      // looseImages: 文件夹 = 系列，文件夹本身 = 一个章节
      return ComicScanResult(
        series: ComicSeries(
          title: p.basename(dir.path),
          folderPath: dir.path,
          sourceType: ComicSourceType.looseImages,
        ),
        chapters: [
          ComicChapter(
            seriesId: 0,
            title: p.basename(dir.path),
            filePath: dir.path,
            format: FileFormat.unknown,
            sortOrder: 0,
          ),
        ],
      );
    }

    return null;
  }

  /// 递归收集目录中的所有漫画文件和图片文件
  static Future<void> _collectFilesRecursive(
    Directory rootDir,
    Directory currentDir,
    List<_ComicFileWithVolume> comicFiles,
    List<File> imageFiles,
  ) async {
    final relativeDir = p.relative(currentDir.path, from: rootDir.path);
    final volumeNum = relativeDir != '.' ? _parseVolumeFromFolderName(relativeDir) : null;

    await for (final entity in currentDir.list()) {
      if (entity is Directory) {
        await _collectFilesRecursive(rootDir, entity, comicFiles, imageFiles);
      } else if (entity is File) {
        if (isComicFile(entity.path)) {
          comicFiles.add(_ComicFileWithVolume(entity, volumeNum));
        } else if (isImageFile(entity.path)) {
          imageFiles.add(entity);
        }
      }
    }
  }

  /// 从文件夹名尝试提取卷号（如 "第1卷" "Vol.2"）
  static int? _parseVolumeFromFolderName(String folderName) {
    final name = p.basename(folderName);
    final patterns = [
      RegExp(r'第\s*(\d+)\s*[卷冊]'),
      RegExp(r'[Vv]ol(?:ume)?[\.\s]*(\d+)'),
      RegExp(r'[Vv][\.\s]*(\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  /// 扫描单个文件
  static Future<ComicScanResult> scanSingleFile(File file) async {
    final parsed = parseFilename(p.basename(file.path));
    final format = getFormatFromPath(file.path);

    return ComicScanResult(
      series: ComicSeries(
        title: parsed.title,
        folderPath: file.path,
        sourceType: ComicSourceType.singleFile,
      ),
      chapters: [
        ComicChapter(
          seriesId: 0,
          title: parsed.title,
          chapterNumber: parsed.chapterNumber,
          volumeNumber: parsed.volumeNumber,
          filePath: file.path,
          format: format,
          fileSize: await file.length(),
          sortOrder: 0,
        ),
      ],
    );
  }

  /// 从文件名提取系列名（去掉章节号/卷号后的前缀）
  static String extractSeriesName(String filename) {
    final name = filename.replaceAll(
      RegExp(r'\.(zip|cbz|rar|cbr|pdf|mobi|azw3)$', caseSensitive: false),
      '',
    );

    // 按优先级去掉末尾的章节号/卷号模式
    final patterns = [
      RegExp(r'\s*[_\-–—]?\s*第\s*\d+(?:\.\d+)?\s*[话話章].*$'),
      RegExp(r'\s*[_\-–—]?\s*[Cc]h(?:apter)?[\.\s]*\d+(?:\.\d+)?.*$'),
      RegExp(r'\s*[_\-–—]?\s*[Ee]p(?:isode)?[\.\s]*\d+(?:\.\d+)?.*$'),
      RegExp(r'\s*[_\-–—]?\s*[Vv]ol(?:ume)?[\.\s]*\d+.*$'),
      RegExp(r'\s*[_\-–—]?\s*\d{2,4}(?:\.\d+)?\s*$'),
      RegExp(r'\s*[_\-–—]?\s*\d+\s*$'),
    ];

    for (final pattern in patterns) {
      final result = name.replaceAll(pattern, '').trim();
      if (result.isNotEmpty) return result;
    }

    return name.trim();
  }

  /// 从文件名解析章节号和卷号
  static ChapterParseResult parseFilename(String filename) {
    final name = filename.replaceAll(
      RegExp(r'\.(zip|cbz|rar|cbr|pdf|mobi|azw3)$', caseSensitive: false),
      '',
    );

    // 匹配卷号
    final volMatch = RegExp(r'[Vv]ol(?:ume)?[\.\s]*(\d+)').firstMatch(name);
    final volume = volMatch != null ? int.parse(volMatch.group(1)!) : null;

    // 匹配章节号（多种格式）
    final patterns = [
      RegExp(r'第\s*(\d+(?:\.\d+)?)\s*[话話章]'),
      RegExp(r'[Cc]h(?:apter)?[\.\s]*(\d+(?:\.\d+)?)'),
      RegExp(r'[Ee]p(?:isode)?[\.\s]*(\d+(?:\.\d+)?)'),
      RegExp(r'(?<!\d)(\d{2,4})(?!\d)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(name);
      if (match != null) {
        final num = double.tryParse(match.group(1)!);
        if (num != null) {
          return ChapterParseResult(
            title: name.trim(),
            chapterNumber: num,
            volumeNumber: volume,
          );
        }
      }
    }

    return ChapterParseResult(title: name.trim(), volumeNumber: volume);
  }
}

class ComicScanResult {
  final ComicSeries series;
  final List<ComicChapter> chapters;

  ComicScanResult({required this.series, required this.chapters});
}

/// 带卷号信息的漫画文件
class _ComicFileWithVolume {
  final File file;
  final int? volumeNumber;

  _ComicFileWithVolume(this.file, this.volumeNumber);
}
