import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../models/library_item.dart';
import 'database_helper.dart';

/// 离线缓存记录
class OfflineCacheEntry {
  final int? id;
  final String filePath;
  final MediaType mediaType;
  final int fileSize;
  final DateTime downloadedAt;
  final DateTime lastAccessedAt;
  final bool keepOffline;
  final String? accountId;

  OfflineCacheEntry({
    this.id,
    required this.filePath,
    required this.mediaType,
    this.fileSize = 0,
    required this.downloadedAt,
    required this.lastAccessedAt,
    this.keepOffline = false,
    this.accountId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'mediaType': mediaType.index,
      'fileSize': fileSize,
      'downloadedAt': downloadedAt.millisecondsSinceEpoch ~/ 1000,
      'lastAccessedAt': lastAccessedAt.millisecondsSinceEpoch ~/ 1000,
      'keepOffline': keepOffline ? 1 : 0,
      'accountId': accountId,
    };
  }

  factory OfflineCacheEntry.fromMap(Map<String, dynamic> map) {
    return OfflineCacheEntry(
      id: map['id'] as int?,
      filePath: map['filePath'] as String,
      mediaType: MediaType.values[map['mediaType'] as int],
      fileSize: map['fileSize'] as int? ?? 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['downloadedAt'] as int) * 1000,
      ),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['lastAccessedAt'] as int) * 1000,
      ),
      keepOffline: (map['keepOffline'] as int? ?? 0) == 1,
      accountId: map['accountId'] as String?,
    );
  }

  OfflineCacheEntry copyWith({
    int? id,
    String? filePath,
    MediaType? mediaType,
    int? fileSize,
    DateTime? downloadedAt,
    DateTime? lastAccessedAt,
    bool? keepOffline,
    String? accountId,
  }) {
    return OfflineCacheEntry(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      mediaType: mediaType ?? this.mediaType,
      fileSize: fileSize ?? this.fileSize,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      keepOffline: keepOffline ?? this.keepOffline,
      accountId: accountId ?? this.accountId,
    );
  }
}

class OfflineCacheDao {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<OfflineCacheEntry> insert(OfflineCacheEntry entry) async {
    final db = await _db.database;
    final id = await db.insert(
      'offline_cache',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return entry.copyWith(id: id);
  }

  Future<int> update(OfflineCacheEntry entry) async {
    final db = await _db.database;
    return await db.update(
      'offline_cache',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return await db.delete(
      'offline_cache',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteByPath(String filePath) async {
    final db = await _db.database;
    return await db.delete(
      'offline_cache',
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  Future<int> deleteByType(MediaType type) async {
    final db = await _db.database;
    return await db.delete(
      'offline_cache',
      where: 'mediaType = ?',
      whereArgs: [type.index],
    );
  }

  Future<int> deleteAll() async {
    final db = await _db.database;
    return await db.delete('offline_cache');
  }

  Future<OfflineCacheEntry?> getByPath(String filePath) async {
    final db = await _db.database;
    final maps = await db.query(
      'offline_cache',
      where: 'filePath = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    if (maps.isNotEmpty) return OfflineCacheEntry.fromMap(maps.first);
    return null;
  }

  Future<List<OfflineCacheEntry>> getAll() async {
    final db = await _db.database;
    final maps = await db.query('offline_cache');
    return maps.map((e) => OfflineCacheEntry.fromMap(e)).toList();
  }

  Future<List<OfflineCacheEntry>> getByType(MediaType type) async {
    final db = await _db.database;
    final maps = await db.query(
      'offline_cache',
      where: 'mediaType = ?',
      whereArgs: [type.index],
    );
    return maps.map((e) => OfflineCacheEntry.fromMap(e)).toList();
  }

  /// 获取可淘汰的条目（未固定，按最后访问时间升序）
  Future<List<OfflineCacheEntry>> getEvictableEntries() async {
    final db = await _db.database;
    final maps = await db.query(
      'offline_cache',
      where: 'keepOffline = 0',
      orderBy: 'lastAccessedAt ASC',
    );
    return maps.map((e) => OfflineCacheEntry.fromMap(e)).toList();
  }

  Future<int> getTotalSize() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT SUM(fileSize) as total FROM offline_cache',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getSizeByType(MediaType type) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT SUM(fileSize) as total FROM offline_cache WHERE mediaType = ?',
      [type.index],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> getCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM offline_cache');
    return (result.first['count'] as int?) ?? 0;
  }

  /// 获取所有缓存的 filePath 集合（用于快速判断是否为云端下载资源）
  Future<Set<String>> getAllFilePaths() async {
    final db = await _db.database;
    final maps = await db.query('offline_cache', columns: ['filePath']);
    return maps.map((e) => e['filePath'] as String).toSet();
  }

  Future<int> touchAccess(String filePath) async {
    final db = await _db.database;
    return await db.update(
      'offline_cache',
      {'lastAccessedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  Future<int> setKeepOffline(String filePath, bool keep) async {
    final db = await _db.database;
    return await db.update(
      'offline_cache',
      {'keepOffline': keep ? 1 : 0},
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  /// 清理已经不存在的文件记录
  Future<int> cleanupStaleEntries() async {
    final all = await getAll();
    int removed = 0;
    for (final entry in all) {
      final exists = await File(entry.filePath).exists() ||
          await Directory(entry.filePath).exists();
      if (!exists) {
        removed += await delete(entry.id!);
      }
    }
    return removed;
  }
}
