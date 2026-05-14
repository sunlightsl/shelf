import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:epubx/epubx.dart';
import '../models/library_item.dart';
import '../database/library_dao.dart';
import 'app_directories.dart';
import 'cover_service.dart';
import 'tmdb_service.dart';

/// 导入阶段结果
enum ImportStage {
  discovery,
  deduplication,
  metadata,
  database,
  copy,
  complete,
  failed,
}

/// 单个文件的导入结果
class ImportFileResult {
  final String sourcePath;
  final LibraryItem? item;
  final ImportStage stage;
  final String? error;

  ImportFileResult({
    required this.sourcePath,
    this.item,
    required this.stage,
    this.error,
  });

  bool get isSuccess => item != null && stage == ImportStage.complete;
}

/// 统一导入管道
///
/// 修复的核心问题：
/// 1. BUG-2: 先写数据库再复制文件，避免幽灵文件
/// 2. BUG-3: 导入前检测重复（filePath + fileSize）
/// 3. BUG-3: 目标路径冲突时自动重命名
/// 4. BUG-11: 统一扩展名过滤
/// 5. BUG-14: 元数据提取失败记录日志而非吞掉
class ImportPipeline {
  static final ImportPipeline instance = ImportPipeline._internal();
  ImportPipeline._internal();

  final LibraryDao _dao = LibraryDao();
  final CoverService _coverService = CoverService.instance;

  // 导入队列：防止并发导入导致重复导入或路径冲突
  Future<void>? _importQueue;

  Future<T> _enqueue<T>(Future<T> Function() task) async {
    final previous = _importQueue;
    final completer = Completer<void>();
    _importQueue = completer.future;
    try {
      await previous;
      return await task();
    } finally {
      completer.complete();
    }
  }

  // ===================== 公共 API =====================

  /// 导入单个文件（WiFi、选择文件等场景）
  Future<ImportFileResult> importSingleFile(
    String sourcePath, {
    MediaType? forceType,
    String? displayName,
  }) async {
    return _enqueue(() => _processFile(
      sourcePath: sourcePath,
      forceType: forceType,
      displayName: displayName,
    ));
  }

  /// 批量导入文件列表
  Future<List<ImportFileResult>> importFiles(
    List<String> filePaths, {
    MediaType? forceType,
  }) async {
    return _enqueue(() async {
      final results = <ImportFileResult>[];
      for (final path in filePaths) {
        results.add(await _processFile(sourcePath: path, forceType: forceType));
      }
      return results;
    });
  }

  /// 导入文件夹（保留层级结构）
  ///
  /// 目标路径: mediaRootDir/<type>/<folderName>/<relativePath>
  Future<List<ImportFileResult>> importFolder(
    String sourceFolderPath, {
    MediaType? forceType,
  }) async {
    return _enqueue(() async {
      final sourceDir = Directory(sourceFolderPath);
      if (!await sourceDir.exists()) return [];

      // 发现所有支持文件
      final filePaths = <String>[];
      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File && _isSupportedExtension(entity.path)) {
          filePaths.add(entity.path);
        }
      }

      if (filePaths.isEmpty) return [];

      // 按类型分组
      final type = forceType ?? _detectTypeFromFiles(filePaths);
      if (type == null) return [];

      // 构建目标根目录名
      final folderName = p.basename(sourceFolderPath);
      final targetBaseDir = p.join(AppDirectories.mediaRootDir, type.name);

      final results = <ImportFileResult>[];
      for (final filePath in filePaths) {
        final relativePath = p.relative(filePath, from: sourceFolderPath);
        final targetRelativeFolder = p.dirname(relativePath);
        final finalRelativeFolder = targetRelativeFolder == '.'
            ? folderName
          : p.join(folderName, targetRelativeFolder);

      results.add(await _processFile(
        sourcePath: filePath,
        forceType: type,
        targetBaseDir: targetBaseDir,
        relativeFolderPath: finalRelativeFolder,
      ));
    }

      return results;
    });
  }

  // ===================== 核心处理流程 =====================

  Future<ImportFileResult> _processFile({
    required String sourcePath,
    MediaType? forceType,
    String? displayName,
    String? targetBaseDir,
    String? relativeFolderPath,
  }) async {
    // ─── Step 1: 验证文件存在 ───
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return ImportFileResult(
        sourcePath: sourcePath,
        stage: ImportStage.discovery,
        error: '源文件不存在',
      );
    }

    // ─── Step 2: 格式识别 ───
    final format = getFormatFromPath(sourcePath);
    if (format == FileFormat.unknown) {
      return ImportFileResult(
        sourcePath: sourcePath,
        stage: ImportStage.discovery,
        error: '不支持的文件格式',
      );
    }

    final mediaType = forceType ?? getMediaTypeFromFormat(format);
    final fileName = displayName != null && displayName.isNotEmpty
        ? p.basenameWithoutExtension(displayName)
        : p.basenameWithoutExtension(sourcePath);

    // ─── Step 3: 去重检查 ───
    final stat = await sourceFile.stat();
    final duplicate = await _checkDuplicate(sourcePath, stat.size);
    if (duplicate != null) {
      return ImportFileResult(
        sourcePath: sourcePath,
        item: duplicate,
        stage: ImportStage.deduplication,
        error: '文件已存在，跳过导入',
      );
    }

    // ─── Step 4: 元数据提取（封面、标题、作者等）───
    String? coverPath;
    String? author;
    String? description;
    String title = fileName;

    try {
      final meta = await _extractMetadata(sourcePath, format, mediaType, fileName);
      coverPath = meta.coverPath;
      author = meta.author;
      description = meta.description;
      if (meta.title != null && meta.title!.isNotEmpty) {
        title = meta.title!;
      }
    } catch (e, st) {
      debugPrint('[ImportPipeline] 元数据提取失败: $sourcePath, 错误: $e');
      debugPrint('[ImportPipeline] 堆栈: $st');
      // 元数据提取失败不影响导入，继续
    }

    // ─── Step 5: 构建目标路径 ───
    final baseDir = targetBaseDir ?? p.join(AppDirectories.mediaRootDir, mediaType.name);
    final destDir = relativeFolderPath != null
        ? p.join(baseDir, relativeFolderPath)
        : baseDir;

    await Directory(destDir).create(recursive: true);

    final originalDestPath = p.join(destDir, p.basename(sourcePath));
    final destPath = await _resolveConflict(originalDestPath);

    // ─── Step 5b: 快速路径 ───
    // 如果文件已经在目标媒体目录中，直接入库，不复制。
    // 这防止启动扫描把 mediaRootDir 中已存在的文件重复导入。
    final bool alreadyInTarget = targetBaseDir == null &&
        relativeFolderPath == null &&
        p.isWithin(baseDir, sourcePath);

    if (alreadyInTarget) {
      final existingByPath = await _dao.getItemByPath(sourcePath);
      if (existingByPath != null) {
        return ImportFileResult(
          sourcePath: sourcePath,
          item: existingByPath,
          stage: ImportStage.deduplication,
          error: '文件已在库中',
        );
      }
      final item = LibraryItem(
        title: title,
        mediaType: mediaType,
        format: format,
        filePath: sourcePath,
        relativeFolderPath: p.relative(p.dirname(sourcePath), from: baseDir),
        coverPath: coverPath,
        author: author,
        description: description,
        addedDate: DateTime.now(),
        fileSize: stat.size,
      );
      try {
        final insertedItem = await _dao.insertItem(item);
        return ImportFileResult(
          sourcePath: sourcePath,
          item: insertedItem,
          stage: ImportStage.complete,
        );
      } catch (e) {
        return ImportFileResult(
          sourcePath: sourcePath,
          stage: ImportStage.database,
          error: '数据库插入失败: $e',
        );
      }
    }

    // ─── Step 6: 复制到 staging ───
    final stagingDir = Directory(AppDirectories.stagingDir);
    await stagingDir.create(recursive: true);
    final stagingPath = p.join(stagingDir.path, '${sourcePath.hashCode}_${p.basename(sourcePath)}');
    try {
      await sourceFile.copy(stagingPath);
    } catch (e) {
      return ImportFileResult(
        sourcePath: sourcePath,
        stage: ImportStage.copy,
        error: '复制到 staging 失败: $e',
      );
    }

    // ─── Step 7: 数据库插入 ───
    final item = LibraryItem(
      title: title,
      mediaType: mediaType,
      format: format,
      filePath: destPath,
      relativeFolderPath: relativeFolderPath,
      coverPath: coverPath,
      author: author,
      description: description,
      addedDate: DateTime.now(),
      fileSize: stat.size,
    );

    LibraryItem? insertedItem;
    try {
      insertedItem = await _dao.insertItem(item);
    } catch (e) {
      // 数据库失败 → 清理 staging
      try { await File(stagingPath).delete(); } catch (cleanupErr) {
        debugPrint('[ImportPipeline] 清理 staging 失败: $cleanupErr');
      }
      return ImportFileResult(
        sourcePath: sourcePath,
        stage: ImportStage.database,
        error: '数据库插入失败: $e',
      );
    }

    // ─── Step 8: 从 staging 移动到最终位置 ───
    try {
      await File(stagingPath).rename(destPath);
    } catch (e) {
      // 跨文件系统时 rename 会失败，fallback 到 copy+delete
      try {
        await File(stagingPath).copy(destPath);
        await File(stagingPath).delete();
      } catch (copyErr) {
        // 移动失败 → 回滚数据库 + 清理 staging
        try { if (insertedItem.id != null) await _dao.permanentlyDeleteItem(insertedItem.id!); } catch (rollbackErr) {
          debugPrint('[ImportPipeline] 回滚数据库失败: $rollbackErr');
        }
        try { await File(stagingPath).delete(); } catch (cleanupErr) {
          debugPrint('[ImportPipeline] 清理 staging 失败: $cleanupErr');
        }
        return ImportFileResult(
          sourcePath: sourcePath,
          stage: ImportStage.copy,
          error: '移动到目标路径失败: $copyErr',
        );
      }
    }

    // ─── Step 9: 清理 WiFi 临时文件 ───
    await _cleanupWifiTempFile(sourcePath);

    final completedItem = insertedItem;

    return ImportFileResult(
      sourcePath: sourcePath,
      item: completedItem,
      stage: ImportStage.complete,
    );
  }

  // ===================== 辅助方法 =====================

  /// 检查文件是否已存在（filePath + fileSize 双重校验）
  Future<LibraryItem?> _checkDuplicate(String sourcePath, int fileSize) async {
    // 按文件名和大小判断重复
    final fileName = p.basename(sourcePath);
    final existing = await _dao.getItemByFileNameAndSize(fileName, fileSize);
    return existing;
  }

  /// 目标路径冲突时自动重命名
  Future<String> _resolveConflict(String targetPath) async {
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

  /// 提取元数据
  Future<_ExtractedMetadata> _extractMetadata(
    String filePath,
    FileFormat format,
    MediaType mediaType,
    String fileName,
  ) async {
    String? coverPath;
    String? author;
    String? description;

    if (format == FileFormat.epub) {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final epub = await EpubReader.readBook(bytes);
      author = epub.Author;
      description = epub.Schema?.Package?.Metadata?.Description;
      coverPath = await _coverService.extractEpubCover(filePath, fileName, preloadedBook: epub);
    } else if (format == FileFormat.pdf) {
      coverPath = await _coverService.extractPdfCover(filePath, fileName);
    } else if (format == FileFormat.zip || format == FileFormat.cbz) {
      coverPath = await _coverService.extractArchiveCover(filePath, fileName);
    } else if (format == FileFormat.rar || format == FileFormat.cbr) {
      coverPath = await _coverService.extractRarCover(filePath, fileName);
    } else if (format == FileFormat.txt) {
      coverPath = await _coverService.generateTextCover(fileName);
    } else if (format == FileFormat.mobi || format == FileFormat.azw3) {
      coverPath = await _coverService.generateTextCover(fileName);
    } else if (mediaType == MediaType.video) {
      coverPath = await _coverService.generateVideoCover(filePath, fileName);

      // 尝试 TMDB 刮削
      if (TMDBService.instance.hasApiKey) {
        try {
          final query = TMDBService.extractQuery(p.basename(filePath));
          final results = await TMDBService.instance.search(query);
          if (results.isNotEmpty) {
            final top = results.first;
            final details = await TMDBService.instance.getDetails(top.id, top.mediaType);
            if (details != null) {
              // 尝试下载 TMDB 海报替换本地视频帧缩略图
              String? finalCoverPath = coverPath;
              if (details.posterPath != null) {
                final posterUrl = TMDBService.posterUrl(details.posterPath!, size: 'w500');
                final tmdbCover = posterUrl != null
                    ? await _coverService.downloadCover(posterUrl, fileName)
                    : null;
                if (tmdbCover != null) {
                  finalCoverPath = tmdbCover;
                }
              }
              return _ExtractedMetadata(
                title: details.title,
                coverPath: finalCoverPath,
                description: details.overview,
              );
            }
          }
        } catch (e) {
          debugPrint('[ImportPipeline] TMDB 刮削失败: $filePath, 错误: $e');
        }
      }
    } else if (mediaType == MediaType.music) {
      coverPath = await _coverService.generateMusicCover(fileName);
    }

    return _ExtractedMetadata(
      coverPath: coverPath,
      author: author,
      description: description,
    );
  }

  /// 清理 WiFi 临时文件
  Future<void> _cleanupWifiTempFile(String filePath) async {
    try {
      final wifiDir = AppDirectories.wifiUploadDir;
      final normalizedFilePath = filePath.toLowerCase();
      final normalizedWifiDir = wifiDir.toLowerCase();
      if (normalizedFilePath.startsWith(normalizedWifiDir)) {
        await File(filePath).delete();
      }
    } catch (e) {
      debugPrint('[ImportPipeline] 清理 WiFi 临时文件失败: $e');
    }
  }

  /// 判断文件扩展名是否支持
  static bool isSupportedExtension(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return [
      'txt', 'epub', 'pdf', 'mobi', 'azw3',
      'zip', 'cbz', 'rar', 'cbr',
      'mp4', 'mkv', 'avi',
      'mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a',
    ].contains(ext);
  }

  bool _isSupportedExtension(String filePath) => isSupportedExtension(filePath);

  /// 从文件列表检测媒体类型
  MediaType? _detectTypeFromFiles(List<String> filePaths) {
    final formats = filePaths.map((p) => getFormatFromPath(p)).toList();
    final types = formats.map((f) => getMediaTypeFromFormat(f)).toSet();

    // 如果列表中有多种类型，取数量最多的那种
    if (types.length == 1) return types.first;

    final typeCounts = <MediaType, int>{};
    for (final type in types) {
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }

    return typeCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

/// 内部元数据结构
class _ExtractedMetadata {
  final String? title;
  final String? coverPath;
  final String? author;
  final String? description;

  _ExtractedMetadata({
    this.title,
    this.coverPath,
    this.author,
    this.description,
  });
}
