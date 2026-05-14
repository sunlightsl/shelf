import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../database/library_dao.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import 'app_directories.dart';

class BackupService {
  static final BackupService instance = BackupService._init();
  BackupService._init();

  final LibraryDao _dao = LibraryDao();

  Future<String?> createBackup() async {
    try {
      final items = await _dao.getAllItems();
      final progressList = await _dao.getAllProgress();

      final backupData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'items': items.map((e) => e.toMap()).toList(),
        'progress': progressList.map((e) => e.toMap()).toList(),
      };

      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      final backupDir = Directory(AppDirectories.backupDir);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupPath = path.join(backupDir.path, 'library_backup_$timestamp.zip');

      final encoder = ZipFileEncoder();
      try {
        encoder.create(backupPath);

        // 添加元数据 JSON
        encoder.addArchiveFile(
          ArchiveFile('metadata.json', bytes.length, bytes),
        );

        // 添加封面文件
        for (final item in items) {
          if (item.coverPath != null) {
            final coverFile = File(item.coverPath!);
            if (await coverFile.exists()) {
              final coverName = 'covers/${path.basename(item.coverPath!)}';
              encoder.addFile(coverFile, coverName);
            }
          }
        }

        encoder.close();
        return backupPath;
      } catch (e) {
        try { encoder.close(); } catch (_) {}
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<bool> restoreBackup(String backupPath) async {
    try {
      final file = File(backupPath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 读取元数据
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile == null) return false;

      final jsonString = utf8.decode(metadataFile.content);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      final coverDir = Directory(AppDirectories.coversCacheDir);
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      // 恢复封面
      for (final file in archive) {
        if (file.isFile && file.name.startsWith('covers/')) {
          final coverPath = path.join(coverDir.path, path.basename(file.name));
          final outFile = File(coverPath);
          await outFile.writeAsBytes(file.content);
        }
      }

      // 在数据库事务中恢复数据，确保原子性
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        // 清空现有数据
        await txn.delete('library_items');
        await txn.delete('reading_progress');
        await txn.delete('bookmarks');

        // 恢复书库项目
        final items = (backupData['items'] as List).cast<Map<String, dynamic>>();
        for (final itemMap in items) {
          final item = LibraryItem.fromMap(itemMap);
          await txn.insert('library_items', item.toMap());
        }

        // 恢复阅读进度
        final progressList = (backupData['progress'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final progressMap in progressList) {
          final progress = ReadingProgress.fromMap(progressMap);
          await txn.insert('reading_progress', progress.toMap());
        }
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> shareBackup(String backupPath) async {
    await Share.shareXFiles([XFile(backupPath)],
        text: '拾光集备份 ${DateTime.now().toString()}');
  }

  Future<List<File>> getBackupFiles() async {
    final backupDir = Directory(AppDirectories.backupDir);
    if (!await backupDir.exists()) return [];

    final files = await backupDir
        .list()
        .where((e) => e is File && e.path.endsWith('.zip'))
        .cast<File>()
        .toList();

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> deleteBackup(String backupPath) async {
    final file = File(backupPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
