import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_item.dart';
import '../database/library_dao.dart';
import 'app_directories.dart';
import 'import_pipeline.dart';

/// 文件系统扫描结果
class ScanResult {
  final List<String> addedPaths;
  final List<LibraryItem> orphanedItems;

  const ScanResult({
    this.addedPaths = const [],
    this.orphanedItems = const [],
  });

  static const empty = ScanResult();

  bool get hasChanges => addedPaths.isNotEmpty || orphanedItems.isNotEmpty;
}

/// 文件系统扫描引擎
///
/// 职责：
/// 1. 增量扫描：基于文件修改时间，只扫描变化文件
/// 2. 检测新增：文件系统存在但数据库中没有的文件 → 自动导入
/// 3. 检测缺失：数据库中有但文件系统不存在的记录 → 标记为缺失
class FilesystemScanner {
  static const _lastScanPrefix = 'last_scan_';

  final LibraryDao _dao = LibraryDao();

  /// 增量扫描指定类型的媒体文件
  ///
  /// [checkOrphaned] 是否检测缺失文件（数据库有但文件不存在）。
  /// 建议非每次启动都执行，可设为每周一次或手动触发。
  Future<ScanResult> incrementalScan(
    MediaType type, {
    bool checkOrphaned = false,
  }) async {
    final typeDir = Directory(p.join(AppDirectories.mediaRootDir, type.name));
    if (!await typeDir.exists()) return ScanResult.empty;

    final prefs = await SharedPreferences.getInstance();
    final lastScanKey = '$_lastScanPrefix${type.name}';
    final lastScanMs = prefs.getInt(lastScanKey);
    final lastScan = lastScanMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastScanMs)
        : null;

    final dbItems = await _dao.getItemsByType(type);
    final dbPaths = dbItems.map((i) => i.filePath).toSet();

    final addedPaths = <String>[];

    // 1. 扫描文件系统，发现新增/修改文件
    await for (final entity in typeDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!ImportPipeline.isSupportedExtension(entity.path)) continue;

      // 增量过滤：只检查修改时间 > 上次扫描时间的文件
      if (lastScan != null) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(lastScan) && stat.changed.isBefore(lastScan)) {
            // 文件未变化，跳过
            if (dbPaths.contains(entity.path)) continue;
            // 但如果数据库中也没有（从未导入过），仍然需要处理
          }
        } catch (_) {
          // stat 失败，继续处理
        }
      }

      if (!dbPaths.contains(entity.path)) {
        addedPaths.add(entity.path);
      }
    }

    // 2. 检测缺失文件（可选）
    List<LibraryItem> orphaned = [];
    if (checkOrphaned) {
      final fsPaths = <String>{};
      await for (final entity in typeDir.list(recursive: true)) {
        if (entity is File) fsPaths.add(entity.path);
      }

      for (final item in dbItems) {
        if (!fsPaths.contains(item.filePath)) {
          orphaned.add(item);
        }
      }
    }

    // 3. 更新扫描时间戳
    await prefs.setInt(lastScanKey, DateTime.now().millisecondsSinceEpoch);

    return ScanResult(addedPaths: addedPaths, orphanedItems: orphaned);
  }

  /// 全量扫描（用于首次安装、手动触发、数据库升级后）
  Future<ScanResult> fullScan(MediaType type) async {
    // 清除上次扫描时间戳，强制全量
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_lastScanPrefix${type.name}');
    return incrementalScan(type, checkOrphaned: true);
  }

  /// 自动导入新增文件
  ///
  /// 返回成功导入的项数
  Future<int> autoImportAdded(ScanResult result, MediaType type) async {
    var imported = 0;
    for (final path in result.addedPaths) {
      try {
        final r = await ImportPipeline.instance.importSingleFile(path, forceType: type);
        if (r.isSuccess) imported++;
      } catch (e) {
        debugPrint('自动导入失败: $path, 错误: $e');
      }
    }
    return imported;
  }

  /// 标记缺失文件（逻辑删除）
  ///
  /// 保留数据库记录和阅读进度，只是标记 deletedAt，用户可在回收站恢复
  Future<int> markOrphanedAsDeleted(List<LibraryItem> orphaned) async {
    var marked = 0;
    for (final item in orphaned) {
      try {
        if (item.id != null) {
          await _dao.deleteItem(item.id!);
          marked++;
        }
      } catch (e) {
        debugPrint('标记缺失文件失败: ${item.filePath}, 错误: $e');
      }
    }
    return marked;
  }
}
