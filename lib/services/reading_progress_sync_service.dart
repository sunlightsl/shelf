import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../database/comic_series_dao.dart';
import '../database/library_dao.dart';
import '../models/bookmark.dart';
import '../models/comic_chapter.dart';
import '../models/comic_reading_progress.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import 'app_directories.dart';

/// 阅读进度同步服务
///
/// 职责：
/// 1. 将本地阅读进度导出为 JSON（以相对路径为标识，跨设备一致）
/// 2. 从 JSON 导入并合并到本地（lastReadAt 较新的覆盖）
/// 3. 书签作为阅读进度的子数据一起同步
class ReadingProgressSyncService {
  static final ReadingProgressSyncService instance = ReadingProgressSyncService._internal();
  ReadingProgressSyncService._internal();

  final LibraryDao _libraryDao = LibraryDao();
  final ComicSeriesDao _comicDao = ComicSeriesDao();

  // ===================== 导出 =====================

  Future<Map<String, dynamic>> exportProgressJson() async {
    final entries = <Map<String, dynamic>>[];

    // 1. 导出小说/视频/音乐的阅读进度 + 书签
    final progressMap = await _libraryDao.getAllProgressWithBookmarks();
    for (final entry in progressMap.entries) {
      final progress = entry.key;
      final bookmarks = entry.value;
      final item = await _libraryDao.getRawItemById(progress.itemId);
      if (item == null) continue;

      final relativePath = _toRelativePath(item.filePath);
      if (relativePath == null) continue;

      entries.add({
        'type': item.mediaType.name,
        'relativePath': relativePath,
        'position': progress.position,
        'positionText': progress.positionText,
        'percentage': progress.percentage,
        'lastReadAt': progress.lastReadAt.toIso8601String(),
        'chapterIndex': progress.chapterIndex,
        'chapterOffset': progress.chapterOffset,
        'bookmarks': bookmarks.map((b) => {
          'position': b.position,
          'positionText': b.positionText,
          'note': b.note,
          'createdAt': b.createdAt.toIso8601String(),
        }).toList(),
      });
    }

    // 2. 导出漫画阅读进度
    final comicProgressList = await _comicDao.getAllProgress();
    for (final progress in comicProgressList) {
      final series = await _comicDao.getSeriesById(progress.seriesId);
      if (series == null) continue;

      if (series.folderPath == null) continue;
      final relativePath = _toRelativePath(series.folderPath!);
      if (relativePath == null) continue;

      String? chapterFilePath;
      if (progress.chapterId != null) {
        final chapter = await _comicDao.getChapterById(progress.chapterId!);
        if (chapter != null) {
          chapterFilePath = _toRelativePath(chapter.filePath);
        }
      }

      entries.add({
        'type': 'comic',
        'relativePath': relativePath,
        'currentPage': progress.currentPage,
        'totalPages': progress.totalPages,
        'percentage': progress.percentage,
        'lastReadAt': progress.lastReadAt.toIso8601String(),
        'chapterFilePath': chapterFilePath,
      });
    }

    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries,
    };
  }

  // ===================== 导入 =====================

  Future<SyncResult> importProgressJson(Map<String, dynamic> json) async {
    final version = json['version'] as int? ?? 1;
    if (version != 1) {
      debugPrint('[ReadingProgressSync] 不支持的版本: $version');
      return SyncResult.skipped();
    }

    final entries = json['entries'] as List<dynamic>? ?? [];
    var updatedNovel = 0;
    var updatedComic = 0;
    var skipped = 0;

    for (final e in entries) {
      final map = e as Map<String, dynamic>;
      final type = map['type'] as String?;
      final relativePath = map['relativePath'] as String?;
      final lastReadAtStr = map['lastReadAt'] as String?;
      if (type == null || relativePath == null || lastReadAtStr == null) {
        skipped++;
        continue;
      }

      final cloudLastReadAt = DateTime.tryParse(lastReadAtStr);
      if (cloudLastReadAt == null) {
        skipped++;
        continue;
      }

      if (type == 'comic') {
        final result = await _importComicProgress(map, cloudLastReadAt);
        if (result) updatedComic++;
      } else {
        final result = await _importItemProgress(map, cloudLastReadAt);
        if (result) updatedNovel++;
      }
    }

    return SyncResult(
      updatedNovel: updatedNovel,
      updatedComic: updatedComic,
      skipped: skipped,
    );
  }

  Future<bool> _importItemProgress(Map<String, dynamic> map, DateTime cloudLastReadAt) async {
    final relativePath = map['relativePath'] as String;
    final localPath = p.join(AppDirectories.mediaRootDir, relativePath);
    final item = await _libraryDao.getItemByPath(localPath);
    if (item?.id == null) return false;

    // 比较本地和云端的 lastReadAt
    final localProgress = await _libraryDao.getProgress(item!.id!);
    if (localProgress != null && localProgress.lastReadAt.isAfter(cloudLastReadAt)) {
      return false; // 本地更新，跳过
    }

    // 覆盖本地进度
    await _libraryDao.saveProgress(ReadingProgress(
      itemId: item.id!,
      position: map['position'] as int? ?? 0,
      positionText: map['positionText'] as String? ?? '',
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: cloudLastReadAt,
      chapterIndex: (map['chapterIndex'] as num?)?.toInt() ?? -1,
      chapterOffset: (map['chapterOffset'] as num?)?.toDouble() ?? -1.0,
    ));

    // 同步书签（云端书签覆盖本地）
    final bookmarks = map['bookmarks'] as List<dynamic>?;
    if (bookmarks != null && bookmarks.isNotEmpty) {
      await _libraryDao.deleteBookmarksByItem(item.id!);
      for (final b in bookmarks) {
        final bm = b as Map<String, dynamic>;
        await _libraryDao.insertBookmark(Bookmark(
          itemId: item.id!,
          position: bm['position'] as int? ?? 0,
          positionText: bm['positionText'] as String? ?? '',
          note: bm['note'] as String?,
          createdAt: DateTime.tryParse(bm['createdAt'] as String? ?? '') ?? DateTime.now(),
        ));
      }
    }

    return true;
  }

  Future<bool> _importComicProgress(Map<String, dynamic> map, DateTime cloudLastReadAt) async {
    final relativePath = map['relativePath'] as String;
    final localPath = p.join(AppDirectories.mediaRootDir, relativePath);
    final series = await _comicDao.getSeriesByFolderPath(localPath);
    if (series?.id == null) return false;

    // 比较本地和云端的 lastReadAt
    final localProgress = await _comicDao.getProgressBySeries(series!.id!);
    if (localProgress != null && localProgress.lastReadAt.isAfter(cloudLastReadAt)) {
      return false; // 本地更新，跳过
    }

    // 解析 chapterFilePath → chapterId
    int? chapterId;
    final chapterFilePath = map['chapterFilePath'] as String?;
    if (chapterFilePath != null) {
      final fullPath = p.join(AppDirectories.mediaRootDir, chapterFilePath);
      final chapter = await _comicDao.getChapterByFilePath(fullPath);
      chapterId = chapter?.id;
    }

    await _comicDao.saveProgress(ComicReadingProgress(
      seriesId: series.id!,
      chapterId: chapterId,
      currentPage: (map['currentPage'] as num?)?.toInt() ?? 0,
      totalPages: (map['totalPages'] as num?)?.toInt() ?? 0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: cloudLastReadAt,
    ));

    return true;
  }

  // ===================== 辅助方法 =====================

  String? _toRelativePath(String fullPath) {
    final root = AppDirectories.mediaRootDir;
    if (fullPath.startsWith(root)) {
      var rel = fullPath.substring(root.length);
      if (rel.startsWith(Platform.pathSeparator)) {
        rel = rel.substring(1);
      }
      return rel;
    }
    return null;
  }
}

/// 同步结果统计
class SyncResult {
  final int updatedNovel;
  final int updatedComic;
  final int skipped;

  SyncResult({
    this.updatedNovel = 0,
    this.updatedComic = 0,
    this.skipped = 0,
  });

  SyncResult.skipped()
      : updatedNovel = 0,
        updatedComic = 0,
        skipped = 0;

  int get totalUpdated => updatedNovel + updatedComic;
}
