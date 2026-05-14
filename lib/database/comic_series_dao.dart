import 'package:sqflite/sqflite.dart';
import '../models/comic_chapter.dart';
import '../models/comic_reading_progress.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';
import 'database_helper.dart';

class ComicSeriesDao {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ===================== ComicSeries CRUD =====================

  Future<ComicSeries> insertSeries(ComicSeries series) async {
    final db = await _db.database;
    final id = await db.insert('comic_series', series.toMap());
    return series.copyWith(id: id);
  }

  Future<List<ComicSeries>> getAllSeries() async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_series',
      where: 'deletedAt IS NULL',
      orderBy: 'lastReadAt DESC, updatedAt DESC',
    );
    return maps.map((e) => ComicSeries.fromMap(e)).toList();
  }

  Future<ComicSeries?> getSeriesById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_series',
      where: 'id = ? AND deletedAt IS NULL',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return ComicSeries.fromMap(maps.first);
    return null;
  }

  Future<ComicSeries?> getSeriesByFolderPath(String folderPath) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_series',
      where: 'folderPath = ? AND deletedAt IS NULL',
      whereArgs: [folderPath],
    );
    if (maps.isNotEmpty) return ComicSeries.fromMap(maps.first);
    return null;
  }

  Future<int> updateSeries(ComicSeries series) async {
    final db = await _db.database;
    return await db.update(
      'comic_series',
      series.toMap(),
      where: 'id = ?',
      whereArgs: [series.id],
    );
  }

  Future<void> toggleFavorite(int seriesId, bool isFavorite) async {
    final db = await _db.database;
    await db.update(
      'comic_series',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> updateSeriesCover(int seriesId, String? coverPath) async {
    final db = await _db.database;
    await db.update(
      'comic_series',
      {'coverPath': coverPath},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  // 逻辑删除：标记 deletedAt
  Future<int> deleteSeries(int id) async {
    final db = await _db.database;
    return await db.update(
      'comic_series',
      {'deletedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 彻底删除
  Future<int> permanentlyDeleteSeries(int id) async {
    final db = await _db.database;
    return await db.delete(
      'comic_series',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 恢复
  Future<int> restoreSeries(int id) async {
    final db = await _db.database;
    return await db.update(
      'comic_series',
      {'deletedAt': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 回收站查询
  Future<List<ComicSeries>> getDeletedSeries() async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_series',
      where: 'deletedAt IS NOT NULL',
      orderBy: 'deletedAt DESC',
    );
    return maps.map((e) => ComicSeries.fromMap(e)).toList();
  }

  /// 获取所有私密漫画系列
  Future<List<ComicSeries>> getPrivateSeries() async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_series',
      where: 'deletedAt IS NULL AND isPrivate = 1',
      orderBy: 'lastReadAt DESC, updatedAt DESC',
    );
    return maps.map((e) => ComicSeries.fromMap(e)).toList();
  }

  Future<void> setSeriesPrivate(int seriesId, bool isPrivate) async {
    final db = await _db.database;
    await db.update(
      'comic_series',
      {'isPrivate': isPrivate ? 1 : 0},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> updateSeriesChapterCount(int seriesId) async {
    final db = await _db.database;
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM comic_chapters WHERE seriesId = ?',
      [seriesId],
    );
    final readResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM comic_chapters WHERE seriesId = ? AND isRead = 1',
      [seriesId],
    );
    final total = (totalResult.first['count'] as int? ?? 0);
    final read = (readResult.first['count'] as int? ?? 0);
    await db.update(
      'comic_series',
      {'totalChapters': total, 'readChapters': read},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  // ===================== ComicChapter CRUD =====================

  Future<ComicChapter> insertChapter(ComicChapter chapter) async {
    final db = await _db.database;
    final id = await db.insert('comic_chapters', chapter.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return chapter.copyWith(id: id);
  }

  Future<List<ComicChapter>> getChaptersBySeries(int seriesId) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_chapters',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
      orderBy: 'sortOrder ASC, chapterNumber ASC, title ASC',
    );
    return maps.map((e) => ComicChapter.fromMap(e)).toList();
  }

  Future<ComicChapter?> getChapterById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_chapters',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return ComicChapter.fromMap(maps.first);
    return null;
  }

  Future<ComicChapter?> getChapterByFilePath(String filePath) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_chapters',
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (maps.isNotEmpty) return ComicChapter.fromMap(maps.first);
    return null;
  }

  Future<ComicChapter?> getNextChapter(int seriesId, int currentSortOrder) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_chapters',
      where: 'seriesId = ? AND sortOrder > ?',
      whereArgs: [seriesId, currentSortOrder],
      orderBy: 'sortOrder ASC',
      limit: 1,
    );
    if (maps.isNotEmpty) return ComicChapter.fromMap(maps.first);
    return null;
  }

  Future<int> updateChapter(ComicChapter chapter) async {
    final db = await _db.database;
    return await db.update(
      'comic_chapters',
      chapter.toMap(),
      where: 'id = ?',
      whereArgs: [chapter.id],
    );
  }

  Future<void> updateChapterTitle(int chapterId, String? title) async {
    final db = await _db.database;
    await db.update(
      'comic_chapters',
      {'title': title},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
  }

  Future<void> updateChapterSortOrder(int chapterId, int sortOrder) async {
    final db = await _db.database;
    await db.update(
      'comic_chapters',
      {'sortOrder': sortOrder},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
  }

  Future<void> updateChapterCover(int chapterId, String? coverPath) async {
    final db = await _db.database;
    await db.update(
      'comic_chapters',
      {'coverPath': coverPath},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
  }

  Future<int> markChapterRead(int chapterId, bool isRead) async {
    final db = await _db.database;
    return await db.update(
      'comic_chapters',
      {'isRead': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
  }

  Future<int> deleteChapter(int id) async {
    final db = await _db.database;
    return await db.delete(
      'comic_chapters',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteChaptersBySeries(int seriesId) async {
    final db = await _db.database;
    return await db.delete(
      'comic_chapters',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
    );
  }

  // ===================== ComicReadingProgress CRUD =====================

  Future<ComicReadingProgress> saveProgress(ComicReadingProgress progress) async {
    final db = await _db.database;
    final existing = await getProgressBySeries(progress.seriesId);
    if (existing != null) {
      await db.update(
        'comic_reading_progress',
        progress.toMap(),
        where: 'seriesId = ?',
        whereArgs: [progress.seriesId],
      );
      return progress.copyWith(id: existing.id);
    } else {
      final id = await db.insert('comic_reading_progress', progress.toMap());
      return progress.copyWith(id: id);
    }
  }

  Future<ComicReadingProgress?> getProgressBySeries(int seriesId) async {
    final db = await _db.database;
    final maps = await db.query(
      'comic_reading_progress',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
    );
    if (maps.isNotEmpty) return ComicReadingProgress.fromMap(maps.first);
    return null;
  }

  Future<List<ComicReadingProgress>> getAllProgress() async {
    final db = await _db.database;
    final maps = await db.query('comic_reading_progress');
    return maps.map((e) => ComicReadingProgress.fromMap(e)).toList();
  }

  Future<int> deleteProgressBySeries(int seriesId) async {
    final db = await _db.database;
    return await db.delete(
      'comic_reading_progress',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
    );
  }

  // ===================== 批量操作 =====================

  /// 插入系列及章节，返回带 id 的系列对象
  Future<ComicSeries> insertSeriesWithChaptersReturnSeries(ComicSeries series, List<ComicChapter> chapters) async {
    final db = await _db.database;
    return await db.transaction<ComicSeries>((txn) async {
      final seriesId = await txn.insert('comic_series', series.toMap());
      for (final chapter in chapters) {
        await txn.insert('comic_chapters', chapter.copyWith(seriesId: seriesId).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
        'comic_series',
        {'totalChapters': chapters.length},
        where: 'id = ?',
        whereArgs: [seriesId],
      );
      return series.copyWith(id: seriesId);
    });
  }

  Future<void> insertSeriesWithChapters(ComicSeries series, List<ComicChapter> chapters) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final seriesId = await txn.insert('comic_series', series.toMap());
      for (final chapter in chapters) {
        await txn.insert('comic_chapters', chapter.copyWith(seriesId: seriesId).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update(
        'comic_series',
        {'totalChapters': chapters.length},
        where: 'id = ?',
        whereArgs: [seriesId],
      );
    });
  }

  // ===================== 旧数据迁移 =====================

  Future<void> migrateFromLibraryItems(List<LibraryItem> comicItems) async {
    final db = await _db.database;
    for (final item in comicItems) {
      final existing = await getSeriesByFolderPath(item.filePath);
      if (existing != null) continue;

      final series = ComicSeries(
        title: item.title,
        folderPath: item.filePath,
        coverPath: item.coverPath,
        author: item.author,
        description: item.description,
        tags: item.tags,
        sourceType: ComicSourceType.singleFile,
        lastReadAt: item.lastOpenedDate,
      );

      final chapter = ComicChapter(
        seriesId: 0,
        title: item.title,
        filePath: item.filePath,
        format: item.format,
        fileSize: item.fileSize,
      );

      await db.transaction((txn) async {
        final seriesId = await txn.insert('comic_series', series.toMap());
        await txn.insert('comic_chapters', chapter.copyWith(seriesId: seriesId).toMap());
      });
    }
  }

  /// 清空所有漫画数据但保留表结构
  Future<void> clearAllData() async {
    final db = await _db.database;
    await db.delete('comic_reading_progress');
    await db.delete('comic_chapters');
    await db.delete('comic_series');
    // 重置自增ID
    await db.execute("DELETE FROM sqlite_sequence WHERE name='comic_reading_progress'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='comic_chapters'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='comic_series'");
  }
}
