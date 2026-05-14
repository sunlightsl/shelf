import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 统一的路径管理类
///
/// 设计原则：
/// 1. 所有路径构造集中在此类，禁止在其他文件中直接调用 path_provider
/// 2. 按用途分类，而非按平台分类
/// 3. 启动时自动迁移旧路径数据
class AppDirectories {
  static String? _supportDir;
  static String? _documentsDir;
  static String? _tempDir;
  static String? _windowsUserDocumentsDir;
  static String? _androidExternalFilesDir;

  /// 初始化所有路径（在 App 启动时调用一次）
  static Future<void> init() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    _documentsDir = (await getApplicationDocumentsDirectory()).path;
    _tempDir = (await getTemporaryDirectory()).path;
    if (Platform.isAndroid) {
      await _resolveAndroidExternalFilesDir();
    }
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final oldDir = p.join(userProfile, 'Documents', '本地图书馆');
        final newDir = p.join(userProfile, 'Documents', 'Shelf');
        // 品牌迁移：旧目录重命名
        if (await Directory(oldDir).exists() && !await Directory(newDir).exists()) {
          try {
            await Directory(oldDir).rename(newDir);
          } catch (_) {
            // 重命名失败时回退到旧目录
            _windowsUserDocumentsDir = oldDir;
          }
        }
        _windowsUserDocumentsDir ??= newDir;
      }
    }
    await _migrateLegacyData();
    await _cleanupStaleStaging();
  }

  /// 启动时清理超过 1 小时的 staging 文件（上次崩溃残留）
  static Future<void> _cleanupStaleStaging() async {
    final stagingDirectory = Directory(stagingDir);
    if (!await stagingDirectory.exists()) return;

    final now = DateTime.now();
    final threshold = const Duration(hours: 1);

    try {
      await for (final entity in stagingDirectory.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (now.difference(stat.modified) > threshold) {
              await entity.delete();
            }
          } catch (_) {
            // 单个文件删除失败不影响整体清理
          }
        }
      }
    } catch (e) {
      debugPrint('清理陈旧 staging 文件失败: $e');
    }
  }

  // ========== Android 外部存储路径解析 ==========

  static Future<void> _resolveAndroidExternalFilesDir() async {
    const key = 'android_external_files_dir';
    final prefs = await SharedPreferences.getInstance();

    // 1. 先尝试读取之前持久化成功的路径
    final savedPath = prefs.getString(key);
    if (savedPath != null && await Directory(savedPath).exists()) {
      // 检查是否是旧版本遗留的重复路径（包含 .../files/Android/data/...）
      final parts = savedPath.split(Platform.pathSeparator);
      final filesIndex = parts.lastIndexOf('files');
      final hasDuplicate = filesIndex > 0 &&
          parts.sublist(0, filesIndex).contains('files');
      if (!hasDuplicate) {
        _androidExternalFilesDir = savedPath;
        return;
      }
      // 路径重复，清除旧记录重新获取
      await prefs.remove(key);
    }

    // 2. 没有持久化记录，尝试从系统获取
    try {
      final externalStorage = await getExternalStorageDirectory();
      if (externalStorage != null) {
        // getExternalStorageDirectory() 返回的已经是 Android/data/<package>/files/
        final resolved = externalStorage.path;
        // 确保目录存在后再持久化
        final dir = Directory(resolved);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _androidExternalFilesDir = resolved;
        await prefs.setString(key, resolved);
      }
    } catch (e) {
      debugPrint('获取 Android 外部存储路径失败: $e');
    }
  }

  // ========== 内部数据（用户不可见）==========

  /// 数据库路径
  /// 所有平台统一使用 Application Support
  static String get databasePath {
    assert(_supportDir != null, 'AppDirectories.init() must be called first');
    return p.join(_supportDir!, 'local_library.db');
  }

  static String get settingsDir {
    assert(_supportDir != null, 'AppDirectories.init() must be called first');
    return _supportDir!;
  }

  // ========== 媒体文件（用户可见）==========

  /// 媒体文件根目录
  /// Android: ExternalFilesDir（卸载时删除）
  /// iOS / macOS: Documents/Media（开启文件共享后用户可见）
  /// Windows: %USERPROFILE%\Documents\Shelf
  static String get mediaRootDir {
    assert(_documentsDir != null, 'AppDirectories.init() must be called first');
    if (Platform.isAndroid && _androidExternalFilesDir != null) {
      return _androidExternalFilesDir!;
    }
    if (Platform.isWindows && _windowsUserDocumentsDir != null) {
      return _windowsUserDocumentsDir!;
    }
    // iOS / macOS / Linux
    return p.join(_documentsDir!, 'Media');
  }

  static String get novelDir => p.join(mediaRootDir, 'novel');
  static String get comicDir => p.join(mediaRootDir, 'comic');
  static String get videoDir => p.join(mediaRootDir, 'video');
  static String get musicDir => p.join(mediaRootDir, 'music');

  // ========== 备份文件（用户可见）==========

  static String get backupDir {
    assert(_documentsDir != null, 'AppDirectories.init() must be called first');
    if (Platform.isAndroid && _androidExternalFilesDir != null) {
      return p.join(_androidExternalFilesDir!, 'Backups');
    }
    return p.join(_documentsDir!, 'Backups');
  }

  // ========== 缓存（可重建，系统可清理）==========

  /// 封面目录（持久化，非临时目录）
  static String get coversCacheDir => p.join(mediaRootDir, '.covers');
  static String get musicCoversCacheDir => p.join(mediaRootDir, '.music_covers');
  static String get wifiUploadDir => p.join(_tempDir!, 'wifi_uploads');
  static String get stagingDir => p.join(_tempDir!, 'staging');
  static String get rarCacheDir => p.join(_tempDir!, 'rar_cache');

  // ========== 兼容：旧路径常量（迁移用）==========

  static String? get _legacyDocumentsDir => _documentsDir;

  // ========== 数据迁移 ==========

  static Future<void> _migrateLegacyData() async {
    final docDir = _legacyDocumentsDir!;
    final legacyDbPath = p.join(docDir, 'local_library.db');
    final legacyLibraryDir = p.join(docDir, 'library');
    final legacyCoversDir = p.join(docDir, 'covers');
    final legacyMusicCoversDir = p.join(docDir, 'music_covers');
    final legacyBackupDir = p.join(docDir, 'backups');

    bool dbMigrated = false;

    // 迁移数据库
    // 安全：如果 legacyDbPath == databasePath（某些 Android 设备 supportDir == documentsDir），
    // 跳过 copy+delete，避免误删数据库。
    if (legacyDbPath != databasePath && await File(legacyDbPath).exists()) {
      try {
        final dbFile = File(legacyDbPath);
        final targetFile = File(databasePath);
        final targetDir = targetFile.parent;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        await dbFile.copy(databasePath);
        await dbFile.delete();
        dbMigrated = true;
      } catch (e) {
        debugPrint('数据库迁移失败: $e');
      }
    }

    // 迁移媒体文件
    if (await Directory(legacyLibraryDir).exists()) {
      await _moveDirectory(Directory(legacyLibraryDir), Directory(mediaRootDir));
    }

    // 迁移备份文件
    if (await Directory(legacyBackupDir).exists()) {
      await _moveDirectory(Directory(legacyBackupDir), Directory(backupDir));
    }

    // 迁移封面缓存（可重建，但保留以提升体验）
    final oldTempCoversDir = p.join(_tempDir!, 'covers_cache');
    final oldTempMusicCoversDir = p.join(_tempDir!, 'music_covers_cache');
    if (await Directory(legacyCoversDir).exists()) {
      await _moveDirectory(Directory(legacyCoversDir), Directory(coversCacheDir));
    }
    if (await Directory(oldTempCoversDir).exists() && oldTempCoversDir != coversCacheDir) {
      await _moveDirectory(Directory(oldTempCoversDir), Directory(coversCacheDir));
    }
    if (await Directory(legacyMusicCoversDir).exists()) {
      await _moveDirectory(Directory(legacyMusicCoversDir), Directory(musicCoversCacheDir));
    }
    if (await Directory(oldTempMusicCoversDir).exists() && oldTempMusicCoversDir != musicCoversCacheDir) {
      await _moveDirectory(Directory(oldTempMusicCoversDir), Directory(musicCoversCacheDir));
    }

    // 更新数据库中记录的旧路径
    if (dbMigrated) {
      await _updateDatabasePaths(
        oldLibraryDir: legacyLibraryDir,
        newLibraryDir: mediaRootDir,
        oldCoversDir: legacyCoversDir,
        newCoversDir: coversCacheDir,
        oldMusicCoversDir: legacyMusicCoversDir,
        newMusicCoversDir: musicCoversCacheDir,
      );
    }

    // 封面路径从旧临时目录迁移到持久化目录（不依赖 dbMigrated，每次启动都检查）
    await _updateDatabasePaths(
      oldLibraryDir: '',
      newLibraryDir: '',
      oldCoversDir: oldTempCoversDir,
      newCoversDir: coversCacheDir,
      oldMusicCoversDir: oldTempMusicCoversDir,
      newMusicCoversDir: musicCoversCacheDir,
    );
  }

  static Future<void> _moveDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    await for (final entity in source.list()) {
      final newPath = p.join(target.path, p.basename(entity.path));
      if (entity is File) {
        try {
          await entity.rename(newPath);
        } catch (_) {
          // 跨文件系统时 rename 会失败，fallback 到 copy+delete
          await entity.copy(newPath);
          await entity.delete();
        }
      } else if (entity is Directory) {
        await _moveDirectory(entity, Directory(newPath));
      }
    }
    await source.delete(recursive: true);
  }

  static Future<void> _updateDatabasePaths({
    required String oldLibraryDir,
    required String newLibraryDir,
    required String oldCoversDir,
    required String newCoversDir,
    required String oldMusicCoversDir,
    required String newMusicCoversDir,
  }) async {
    try {
      // 使用 singleInstance: false 打开独立连接，避免关闭 DatabaseHelper 共享实例
      final db = await openDatabase(databasePath, singleInstance: false);

      // 媒体文件路径替换：library/ → mediaRootDir/
      final mediaPathUpdates = [
        ['library_items', 'filePath'],
        ['comic_chapters', 'filePath'],
        ['comic_series', 'folderPath'],
        ['songs', 'file_path'],
        ['songs', 'folder_path'],
      ];
      if (oldLibraryDir.isNotEmpty) {
        for (final update in mediaPathUpdates) {
          final table = update[0];
          final column = update[1];
          await db.rawUpdate(
            'UPDATE $table SET $column = REPLACE($column, ?, ?) WHERE $column LIKE ?',
            [oldLibraryDir, newLibraryDir, '$oldLibraryDir%'],
          );
        }
      }

      // 通用封面路径替换：covers/ → coversCacheDir/
      if (oldCoversDir.isNotEmpty) {
        final coverPathUpdates = [
          ['library_items', 'coverPath'],
          ['comic_chapters', 'coverPath'],
          ['comic_series', 'coverPath'],
          ['songs', 'cover_path'],
          ['artists', 'cover_path'],
          ['albums', 'cover_path'],
          ['playlists', 'cover_path'],
        ];
        for (final update in coverPathUpdates) {
          final table = update[0];
          final column = update[1];
          await db.rawUpdate(
            'UPDATE $table SET $column = REPLACE($column, ?, ?) WHERE $column LIKE ?',
            [oldCoversDir, newCoversDir, '$oldCoversDir%'],
          );
        }
      }

      // 音乐封面路径替换：music_covers/ → musicCoversCacheDir/
      if (oldMusicCoversDir.isNotEmpty) {
        final musicCoverUpdates = [
          ['songs', 'cover_path'],
          ['artists', 'cover_path'],
          ['albums', 'cover_path'],
          ['playlists', 'cover_path'],
        ];
        for (final update in musicCoverUpdates) {
          final table = update[0];
          final column = update[1];
          await db.rawUpdate(
            'UPDATE $table SET $column = REPLACE($column, ?, ?) WHERE $column LIKE ?',
            [oldMusicCoversDir, newMusicCoversDir, '$oldMusicCoversDir%'],
          );
        }
      }

      await db.close();
    } catch (e) {
      debugPrint('数据库路径更新失败: $e');
    }
  }
}
