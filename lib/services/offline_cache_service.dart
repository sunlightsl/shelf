import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/offline_cache_dao.dart';
import '../database/library_dao.dart';
import '../database/comic_series_dao.dart';
import '../database/song_dao.dart';
import '../models/library_item.dart';
import '../models/comic_series.dart';
import '../models/comic_chapter.dart';
import 'app_directories.dart';

/// 离线缓存智能管理服务
///
/// 职责：
/// 1. 记录从云端下载的文件
/// 2. 计算总缓存占用
/// 3. 超出限额时按 LRU 淘汰（保留 keepOffline 标记的项）
/// 4. 提供清理、固定等管理操作
class OfflineCacheService {
  static final OfflineCacheService instance = OfflineCacheService._internal();
  OfflineCacheService._internal();

  final OfflineCacheDao _dao = OfflineCacheDao();
  final LibraryDao _libraryDao = LibraryDao();
  final ComicSeriesDao _comicDao = ComicSeriesDao();
  final SongDao _songDao = SongDao();

  static const _cacheLimitKey = 'offline_cache_limit_mb';
  static const _defaultLimitMB = 5120; // 5 GB

  /// 启动时初始化：清理失效记录
  Future<void> init() async {
    try {
      final cleaned = await _dao.cleanupStaleEntries();
      if (cleaned > 0) {
        debugPrint('[OfflineCache] 清理 $cleaned 条失效缓存记录');
      }
    } catch (e) {
      debugPrint('[OfflineCache] 初始化失败: $e');
    }
  }

  // ===================== 配额管理 =====================

  /// 获取缓存上限（MB），0 表示无限制
  Future<int> getCacheLimitMB() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cacheLimitKey) ?? _defaultLimitMB;
  }

  Future<void> setCacheLimitMB(int mb) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cacheLimitKey, mb);
  }

  // ===================== 下载记录 =====================

  /// 记录一次云端下载
  Future<void> recordDownload(
    String filePath,
    MediaType mediaType, {
    String? accountId,
  }) async {
    try {
      final size = await _calculateSize(filePath);
      final now = DateTime.now();
      await _dao.insert(OfflineCacheEntry(
        filePath: filePath,
        mediaType: mediaType,
        fileSize: size,
        downloadedAt: now,
        lastAccessedAt: now,
        accountId: accountId,
      ));
      await _evictIfNeeded();
    } catch (e) {
      debugPrint('[OfflineCache] 记录下载失败: $e');
    }
  }

  /// 更新文件访问时间（LRU 排序依据）
  Future<void> touchAccess(String filePath) async {
    try {
      await _dao.touchAccess(filePath);
    } catch (e) {
      debugPrint('[OfflineCache] touchAccess 失败: $e');
    }
  }

  /// 计算路径总大小（文件或目录）
  Future<int> _calculateSize(String path) async {
    final file = File(path);
    final dir = Directory(path);
    if (await file.exists()) {
      try {
        return (await file.stat()).size;
      } catch (_) {
        return 0;
      }
    }
    if (await dir.exists()) {
      int total = 0;
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            total += (await entity.stat()).size;
          }
        }
      } catch (_) {}
      return total;
    }
    return 0;
  }

  // ===================== 淘汰逻辑 =====================

  /// 检查总缓存是否超出限额，若超出则淘汰最久未访问的非固定项
  Future<void> _evictIfNeeded() async {
    final limitMB = await getCacheLimitMB();
    if (limitMB <= 0) return; // 无限制

    final limitBytes = limitMB * 1024 * 1024;
    final currentBytes = await _dao.getTotalSize();
    if (currentBytes <= limitBytes) return;

    final toFree = currentBytes - limitBytes;
    final evictable = await _dao.getEvictableEntries();

    int freed = 0;
    for (final entry in evictable) {
      if (freed >= toFree) break;
      final deletedSize = await _deleteEntry(entry);
      freed += deletedSize;
    }

    debugPrint('[OfflineCache] 淘汰完成，释放 ${(freed / 1024 / 1024).toStringAsFixed(1)} MB');
  }

  /// 删除单个缓存条目及其关联的物理文件和数据库记录
  /// 返回实际释放的字节数
  Future<int> _deleteEntry(OfflineCacheEntry entry) async {
    try {
      if (entry.mediaType == MediaType.comic) {
        return await _deleteComicEntry(entry);
      }

      // 查找对应的 library_item
      final item = await _libraryDao.getItemByPath(entry.filePath);
      if (item != null) {
        if (item.mediaType == MediaType.music) {
          await _songDao.deleteSongsByPaths([item.filePath]);
        }
        await _libraryDao.permanentlyDeleteItem(item.id!);
      } else {
        // 没有对应数据库记录，直接删文件
        await _deletePhysical(entry.filePath);
      }

      await _dao.deleteByPath(entry.filePath);
      return entry.fileSize;
    } catch (e) {
      debugPrint('[OfflineCache] 删除缓存条目失败: ${entry.filePath}, 错误: $e');
      return 0;
    }
  }

  Future<int> _deleteComicEntry(OfflineCacheEntry entry) async {
    try {
      final series = await _comicDao.getSeriesByFolderPath(entry.filePath);
      if (series != null) {
        // 删除系列下的所有章节文件和封面
        final chapters = await _comicDao.getChaptersBySeries(series.id!);
        for (final chapter in chapters) {
          await _deletePhysical(chapter.filePath);
          if (chapter.coverPath != null) {
            await _deletePhysical(chapter.coverPath!);
          }
        }
        if (series.coverPath != null) {
          await _deletePhysical(series.coverPath!);
        }
        await _comicDao.permanentlyDeleteSeries(series.id!);
        await _comicDao.deleteChaptersBySeries(series.id!);
        await _comicDao.deleteProgressBySeries(series.id!);
      }
      // 删除系列文件夹本身
      await _deletePhysical(entry.filePath);
      await _dao.deleteByPath(entry.filePath);
      return entry.fileSize;
    } catch (e) {
      debugPrint('[OfflineCache] 删除漫画缓存失败: ${entry.filePath}, 错误: $e');
      return 0;
    }
  }

  Future<void> _deletePhysical(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return;
      }
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  // ===================== 公共管理 API =====================

  /// 获取当前缓存总大小（字节）
  Future<int> getTotalSizeBytes() async => _dao.getTotalSize();

  /// 获取当前缓存总大小（字节，按类型）
  Future<int> getSizeByTypeBytes(MediaType type) async => _dao.getSizeByType(type);

  /// 获取缓存条目数量
  Future<int> getCount() async => _dao.getCount();

  /// 获取所有缓存条目
  Future<List<OfflineCacheEntry>> getAllEntries() async => _dao.getAll();

  /// 固定/取消固定某个缓存项
  Future<void> setKeepOffline(String filePath, bool keep) async {
    await _dao.setKeepOffline(filePath, keep);
  }

  /// 清理全部缓存（忽略 keepOffline）
  Future<int> clearAllCache() async {
    final entries = await _dao.getAll();
    int freed = 0;
    for (final entry in entries) {
      freed += await _deleteEntry(entry);
    }
    return freed;
  }

  /// 按类型清理缓存
  Future<int> clearCacheByType(MediaType type) async {
    final entries = await _dao.getByType(type);
    int freed = 0;
    for (final entry in entries) {
      freed += await _deleteEntry(entry);
    }
    return freed;
  }

  /// 手动触发淘汰检查（供设置页调用）
  Future<void> runEviction() async => _evictIfNeeded();
}
