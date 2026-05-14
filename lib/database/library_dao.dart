import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import '../models/bookmark.dart';
import 'database_helper.dart';

class LibraryDao {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<LibraryItem> insertItem(LibraryItem item) async {
    final db = await _db.database;
    final id = await db.insert('library_items', item.toMap());
    return item.copyWith(id: id);
  }

  static const String _excludeInSeries =
      'NOT EXISTS (SELECT 1 FROM comic_chapters cc WHERE cc.filePath = li.filePath)';

  static const String _excludeDeleted = 'li.deletedAt IS NULL';

  // 私密内容不再默认排除，由 UI 层通过 isPrivate 字段和角标自行处理
  static const String _excludePrivate = '1 = 1';

  Future<List<LibraryItem>> getAllItems() async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT li.* FROM library_items li WHERE $_excludeDeleted AND $_excludeInSeries AND $_excludePrivate ORDER BY li.lastOpenedDate DESC',
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  Future<List<LibraryItem>> getItemsByType(MediaType type) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT li.* FROM library_items li WHERE li.mediaType = ? AND $_excludeDeleted AND $_excludeInSeries AND $_excludePrivate ORDER BY li.lastOpenedDate DESC',
      [type.index],
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 获取指定云端账户的所有同步条目
  Future<List<LibraryItem>> getItemsBySourceAccount(String accountId) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'sourceAccountId = ? AND deletedAt IS NULL',
      whereArgs: [accountId],
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 获取所有云端来源的条目（用于 UI 筛选"云端"标签）
  Future<List<LibraryItem>> getCloudItemsByType(MediaType type) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT li.* FROM library_items li
      WHERE li.mediaType = ?
        AND li.sourceType IS NOT NULL
        AND li.sourceType != 'local'
        AND $_excludeDeleted
        AND $_excludePrivate
      ORDER BY li.lastOpenedDate DESC
      ''',
      [type.index],
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  Future<List<LibraryItem>> getFavoriteItems() async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT li.* FROM library_items li WHERE li.isFavorite = 1 AND $_excludeDeleted AND $_excludeInSeries AND $_excludePrivate ORDER BY li.lastOpenedDate DESC',
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  Future<List<LibraryItem>> getRecentItems({int limit = 20}) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT li.* FROM library_items li WHERE li.lastOpenedDate IS NOT NULL AND $_excludeDeleted AND $_excludeInSeries AND $_excludePrivate ORDER BY li.lastOpenedDate DESC LIMIT ?',
      [limit],
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 获取"继续阅读/播放"列表：进度在 5%~99% 之间的内容
  Future<List<LibraryItem>> getContinueReading(MediaType type, {int limit = 10}) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT li.* FROM library_items li
      INNER JOIN reading_progress rp ON li.id = rp.itemId
      WHERE li.mediaType = ?
        AND $_excludeDeleted
        AND $_excludeInSeries
        AND rp.percentage > 0.05
        AND rp.percentage < 0.99
      ORDER BY rp.lastReadAt DESC
      LIMIT ?
      ''',
      [type.index, limit],
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 获取"继续观看"视频列表：观看进度在 5%~95% 之间的视频
  Future<List<LibraryItem>> getUpNextVideos({int limit = 20}) async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      '''
      SELECT li.* FROM library_items li
      INNER JOIN reading_progress rp ON li.id = rp.itemId
      WHERE li.mediaType = ?
        AND $_excludeDeleted
        AND $_excludePrivate
        AND rp.percentage > 0.05
        AND rp.percentage < 0.95
      ORDER BY rp.lastReadAt DESC
      LIMIT ?
      ''',
      [2, limit], // MediaType.video.index = 2
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  Future<LibraryItem?> getItemById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'id = ? AND deletedAt IS NULL',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return LibraryItem.fromMap(maps.first);
    }
    return null;
  }

  Future<LibraryItem?> getRawItemById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return LibraryItem.fromMap(maps.first);
    }
    return null;
  }

  Future<LibraryItem?> getItemByPath(String path) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'filePath = ? AND deletedAt IS NULL AND isPrivate = 0',
      whereArgs: [path],
    );
    if (maps.isNotEmpty) {
      return LibraryItem.fromMap(maps.first);
    }
    return null;
  }

  /// 按文件名+文件大小检查是否已存在（用于去重）
  Future<LibraryItem?> getItemByFileNameAndSize(String fileName, int fileSize) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'fileSize = ?',
      whereArgs: [fileSize],
    );
    for (final map in maps) {
      final item = LibraryItem.fromMap(map);
      // 比较文件名（忽略路径），兼容大小写差异
      if (p.basename(item.filePath).toLowerCase() == fileName.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  Future<int> updateItemTotalProgress(int itemId, int totalProgress) async {
    final db = await _db.database;
    return await db.update(
      'library_items',
      {'totalProgress': totalProgress},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<int> updateItem(LibraryItem item) async {
    final db = await _db.database;
    return await db.update(
      'library_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> toggleFavorite(int itemId) async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      columns: ['isFavorite'],
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (maps.isEmpty) return;
    final current = (maps.first['isFavorite'] as int? ?? 0) == 1;
    await db.update(
      'library_items',
      {'isFavorite': current ? 0 : 1},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  // ===================== 逻辑删除 / 回收站 =====================

  /// 逻辑删除：标记 deletedAt，不删物理文件
  Future<int> deleteItem(int id) async {
    final db = await _db.database;
    return await db.update(
      'library_items',
      {'deletedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 查询回收站内容（回收站也过滤私密资源）
  Future<List<LibraryItem>> getDeletedItems() async {
    final db = await _db.database;
    final maps = await db.query(
      'library_items',
      where: 'deletedAt IS NOT NULL AND isPrivate = 0',
      orderBy: 'deletedAt DESC',
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 获取所有私密资源（不分类型）
  Future<List<LibraryItem>> getPrivateItems() async {
    final db = await _db.database;
    final maps = await db.rawQuery(
      'SELECT li.* FROM library_items li WHERE li.deletedAt IS NULL AND li.isPrivate = 1 ORDER BY li.lastOpenedDate DESC',
    );
    return maps.map((e) => LibraryItem.fromMap(e)).toList();
  }

  /// 恢复：清空 deletedAt
  Future<int> restoreItem(int id) async {
    final db = await _db.database;
    return await db.update(
      'library_items',
      {'deletedAt': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 彻底删除：删除数据库记录 + 物理文件
  Future<void> permanentlyDeleteItem(int id) async {
    final db = await _db.database;
    // 用 id 直接查询（不限制 deletedAt），确保回收站里的记录也能查到
    final maps = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    final item = maps.isNotEmpty ? LibraryItem.fromMap(maps.first) : null;
    if (item != null) {
      // 删除物理文件
      try {
        final file = File(item.filePath);
        if (await file.exists()) await file.delete();
        if (item.coverPath != null) {
          final coverFile = File(item.coverPath!);
          if (await coverFile.exists()) await coverFile.delete();
        }
      } catch (e) {
        // 忽略物理文件删除错误
      }
    }
    await db.delete(
      'library_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllItems() async {
    final db = await _db.database;
    return await db.delete('library_items');
  }

  /// 清空所有数据但保留表结构
  Future<void> clearAllData() async {
    final db = await _db.database;
    await db.delete('library_items');
    await db.delete('reading_progress');
    await db.delete('bookmarks');
    // 重置自增ID
    await db.execute("DELETE FROM sqlite_sequence WHERE name='library_items'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='reading_progress'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='bookmarks'");
  }

  // ===================== 阅读进度 =====================

  Future<ReadingProgress> saveProgress(ReadingProgress progress) async {
    final db = await _db.database;
    final existing = await getProgress(progress.itemId);
    if (existing != null) {
      await db.update(
        'reading_progress',
        progress.toMap(),
        where: 'itemId = ?',
        whereArgs: [progress.itemId],
      );
      return progress.copyWith(id: existing.id);
    } else {
      final id = await db.insert('reading_progress', progress.toMap());
      return progress.copyWith(id: id);
    }
  }

  Future<ReadingProgress?> getProgress(int itemId) async {
    final db = await _db.database;
    final maps = await db.query(
      'reading_progress',
      where: 'itemId = ?',
      whereArgs: [itemId],
    );
    if (maps.isNotEmpty) {
      return ReadingProgress.fromMap(maps.first);
    }
    return null;
  }

  Future<List<ReadingProgress>> getAllProgress() async {
    final db = await _db.database;
    final maps = await db.query('reading_progress');
    return maps.map((e) => ReadingProgress.fromMap(e)).toList();
  }

  Future<List<ReadingProgress>> getProgressByItemIds(List<int> itemIds) async {
    if (itemIds.isEmpty) return [];
    final db = await _db.database;
    final placeholders = List.filled(itemIds.length, '?').join(',');
    final maps = await db.rawQuery(
      'SELECT * FROM reading_progress WHERE itemId IN ($placeholders)',
      itemIds.map((id) => id.toString()).toList(),
    );
    return maps.map((e) => ReadingProgress.fromMap(e)).toList();
  }

  Future<Map<ReadingProgress, List<Bookmark>>> getAllProgressWithBookmarks() async {
    final progressList = await getAllProgress();
    final result = <ReadingProgress, List<Bookmark>>{};
    for (final progress in progressList) {
      final bookmarks = await getBookmarksByItem(progress.itemId);
      result[progress] = bookmarks;
    }
    return result;
  }

  Future<int> deleteProgress(int itemId) async {
    final db = await _db.database;
    return await db.delete(
      'reading_progress',
      where: 'itemId = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateLastOpened(int itemId) async {
    final db = await _db.database;
    await db.update(
      'library_items',
      {'lastOpenedDate': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  // ===================== 书签 =====================

  Future<Bookmark> insertBookmark(Bookmark bookmark) async {
    final db = await _db.database;
    final id = await db.insert('bookmarks', bookmark.toMap());
    return bookmark.copyWith(id: id);
  }

  Future<List<Bookmark>> getBookmarksByItem(int itemId) async {
    final db = await _db.database;
    final maps = await db.query(
      'bookmarks',
      where: 'itemId = ?',
      whereArgs: [itemId],
      orderBy: 'position ASC',
    );
    return maps.map((e) => Bookmark.fromMap(e)).toList();
  }

  Future<int> deleteBookmark(int bookmarkId) async {
    final db = await _db.database;
    return await db.delete(
      'bookmarks',
      where: 'id = ?',
      whereArgs: [bookmarkId],
    );
  }

  Future<int> deleteBookmarksByItem(int itemId) async {
    final db = await _db.database;
    return await db.delete(
      'bookmarks',
      where: 'itemId = ?',
      whereArgs: [itemId],
    );
  }
}
