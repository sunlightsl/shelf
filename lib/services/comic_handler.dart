import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/comic_series.dart';
import '../models/comic_chapter.dart';
import '../database/comic_series_dao.dart';
import 'comic_scan_service.dart';
import 'cover_service.dart';
import 'app_directories.dart';

/// 漫画专用导入处理器
///
/// 职责：
/// 1. 调用 ComicScanService 扫描识别系列结构
/// 2. 复制文件到沙盒
/// 3. 提取封面
/// 4. 写入 comic_series / comic_chapters 表
///
/// ComicScanService 只做扫描识别，其他逻辑由本类补充。
class ComicHandler {
  static final ComicSeriesDao _dao = ComicSeriesDao();
  static final CoverService _coverService = CoverService.instance;

  /// 导入单个漫画文件
  static Future<ComicSeries?> importSingleComicFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    if (!ComicScanService.isComicFile(filePath)) return null;

    final result = await ComicScanService.scanSingleFile(file);
    final seriesName = _sanitizeName(result.series.title);
    final destDir = p.join(AppDirectories.comicDir, seriesName);
    await Directory(destDir).create(recursive: true);

    final destPath = await _resolveConflict(p.join(destDir, p.basename(filePath)));
    await file.copy(destPath);

    final chapter = result.chapters.first.copyWith(filePath: destPath);
    final coverPath = await _extractCover(result.series, [chapter]);

    final series = result.series.copyWith(
      folderPath: destDir,
      coverPath: coverPath,
      totalChapters: 1,
    );

    return await _dao.insertSeriesWithChaptersReturnSeries(series, [chapter]);
  }

  /// 导入一个漫画文件夹
  static Future<List<ComicSeries>> importComicFolder(String sourcePath) async {
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) return [];

    final scanResults = await ComicScanService.scanDirectory(sourcePath);
    final imported = <ComicSeries>[];

    for (final result in scanResults) {
      final series = await _importScanResult(result, sourcePath);
      if (series != null) imported.add(series);
    }

    return imported;
  }

  static Future<ComicSeries?> _importScanResult(ComicScanResult result, String sourcePath) async {
    final seriesName = _sanitizeName(result.series.title);
    final destDir = p.join(AppDirectories.comicDir, seriesName);
    await Directory(destDir).create(recursive: true);

    // 复制文件到沙盒
    final copiedChapters = <ComicChapter>[];
    for (final chapter in result.chapters) {
      final destPath = await _copyChapter(chapter, destDir, sourcePath);
      if (destPath != null) {
        copiedChapters.add(chapter.copyWith(filePath: destPath));
      }
    }

    if (copiedChapters.isEmpty) return null;

    // 提取封面：从第一个章节文件提取
    final coverPath = await _extractCover(result.series, copiedChapters);

    // 写入数据库
    final series = result.series.copyWith(
      folderPath: destDir,
      coverPath: coverPath,
      totalChapters: copiedChapters.length,
    );

    return await _dao.insertSeriesWithChaptersReturnSeries(series, copiedChapters);
  }

  /// 复制章节文件到目标目录
  static Future<String?> _copyChapter(ComicChapter chapter, String destDir, String sourcePath) async {
    final srcFile = File(chapter.filePath);
    if (!await srcFile.exists()) return null;

    String destPath;
    if (chapter.format == FileFormat.unknown && !ComicScanService.isComicFile(chapter.filePath)) {
      // looseImages：文件夹整体复制
      final folderName = p.basename(chapter.filePath);
      final destFolder = p.join(destDir, folderName);
      await _copyDirectory(Directory(chapter.filePath), Directory(destFolder));
      destPath = destFolder;
    } else {
      // 单文件复制
      final fileName = p.basename(chapter.filePath);
      destPath = p.join(destDir, fileName);
      destPath = await _resolveConflict(destPath);
      await srcFile.copy(destPath);
    }

    return destPath;
  }

  /// 提取系列封面
  static Future<String?> _extractCover(ComicSeries series, List<ComicChapter> chapters) async {
    if (chapters.isEmpty) return null;

    final firstChapter = chapters.first;
    final filePath = firstChapter.filePath;
    final fileName = series.title;

    try {
      switch (firstChapter.format) {
        case FileFormat.zip:
        case FileFormat.cbz:
          return await _coverService.extractArchiveCover(filePath, fileName);
        case FileFormat.rar:
        case FileFormat.cbr:
          return await _coverService.extractRarCover(filePath, fileName);
        case FileFormat.pdf:
          return await _coverService.extractPdfCover(filePath, fileName);
        default:
          // looseImages 或未知格式，尝试从文件夹内第一张图片提取
          if (firstChapter.format == FileFormat.unknown) {
            final dir = Directory(filePath);
            if (await dir.exists()) {
              final images = await dir
                  .list()
                  .where((e) => e is File && ComicScanService.isImageFile(e.path))
                  .cast<File>()
                  .toList();
              images.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
              if (images.isNotEmpty) {
                final first = images.first;
                final coverDir = await _coverService.getCoverDir();
                final ext = p.extension(first.path);
                final coverPath = p.join(coverDir, '${fileName.hashCode}_cover$ext');
                await first.copy(coverPath);
                return coverPath;
              }
            }
          }
          return await _coverService.generateTextCover(fileName, author: series.author);
      }
    } catch (e) {
      debugPrint('漫画封面提取失败: ${series.title}, 错误: $e');
      return null;
    }
  }

  /// 目标路径冲突时自动重命名
  static Future<String> _resolveConflict(String targetPath) async {
    if (!await File(targetPath).exists()) return targetPath;

    final dir = p.dirname(targetPath);
    final name = p.basenameWithoutExtension(targetPath);
    final ext = p.extension(targetPath);

    int suffix = 1;
    String newPath;
    do {
      newPath = p.join(dir, '${name}_($suffix)$ext');
      suffix++;
    } while (await File(newPath).exists());

    return newPath;
  }

  /// 递归复制目录
  static Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final destPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  /// 清理非法文件名字符
  static String _sanitizeName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
  }
}
