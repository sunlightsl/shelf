import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../models/cloud_file.dart';
import '../../models/library_item.dart';
import '../../database/library_dao.dart';
import '../../services/import_pipeline.dart';
import '../app_directories.dart';
import '../comic_handler.dart';
import '../reading_progress_sync_service.dart';
import '../offline_cache_service.dart';
import 'cloud_account.dart';
import 'cloud_account_manager.dart';
import 'cloud_storage.dart';
import 'cloud_storage_factory.dart';

/// 云同步服务
///
/// 职责：
/// 1. 管理云存储连接生命周期
/// 2. 扫描云端目录，对比本地，生成下载列表
/// 3. 执行下载并入库
/// 4. 上传本地进度/书签到云端
class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._internal();
  CloudSyncService._internal();

  final LibraryDao _dao = LibraryDao();
  final Map<String, CloudStorage> _connections = {};

  /// 获取或创建云存储连接
  Future<CloudStorage> _getConnection(String accountId) async {
    if (_connections.containsKey(accountId)) {
      return _connections[accountId]!;
    }

    final (account, credentials) =
        await CloudAccountManager.instance.getAccountWithCredentials(accountId);
    if (account == null) throw Exception('账户不存在');

    final storage = CloudStorageFactory.create(account.protocol);
    final ok = await storage.connect({...account.config, ...credentials});
    if (!ok) throw Exception('连接失败');

    _connections[accountId] = storage;
    return storage;
  }

  /// 断开指定账户的连接
  Future<void> disconnect(String accountId) async {
    final conn = _connections.remove(accountId);
    await conn?.disconnect();
  }

  /// 断开所有连接
  Future<void> disconnectAll() async {
    for (final conn in _connections.values) {
      await conn.disconnect();
    }
    _connections.clear();
  }

  /// 浏览云端目录
  Future<List<CloudFile>> browseDirectory(
    String accountId,
    String remotePath,
  ) async {
    final storage = await _getConnection(accountId);
    return await storage.listDirectory(remotePath);
  }

  /// 扫描云端目录，生成需要下载的文件列表
  ///
  /// 规则：
  /// 1. 云端存在但本地不存在 → 下载
  /// 2. 云端修改时间晚于本地添加时间 → 重新下载
  Future<List<CloudFile>> scanForDownloads(
    String accountId,
    String remotePath,
    MediaType mediaType,
  ) async {
    final storage = await _getConnection(accountId);
    final account = (await CloudAccountManager.instance.getAccounts())
        .firstWhere((a) => a.id == accountId);

    // 递归列出云端所有文件
    final remoteFiles = await _listAllFiles(storage, remotePath);

    // 获取本地已有记录
    final localItems = await _dao.getItemsByType(mediaType);
    final localPaths = localItems.map((i) => i.filePath).toSet();
    final localPathMap = {for (var i in localItems) i.filePath: i};

    final toDownload = <CloudFile>[];
    for (final remote in remoteFiles) {
      if (remote.isDirectory) continue;
      if (!ImportPipeline.isSupportedExtension(remote.path)) continue;

      final localPath = _mapRemoteToLocal(
        remote.path,
        account.rootPath,
        mediaType,
      );

      final local = localPathMap[localPath];
      if (local == null) {
        // 本地没有，需要下载
        toDownload.add(remote);
      } else if (remote.modifiedDate != null &&
          local.addedDate.isBefore(remote.modifiedDate!)) {
        // 云端更新过，需要重新下载
        toDownload.add(remote);
      }
    }

    return toDownload;
  }

  /// 下载单个文件到本地并入库
  Future<LibraryItem?> downloadFile(
    String accountId,
    CloudFile remoteFile,
    MediaType mediaType, {
    DownloadProgressCallback? onProgress,
    CloudCancelToken? cancelToken,
  }) async {
    final storage = await _getConnection(accountId);
    final account = (await CloudAccountManager.instance.getAccounts())
        .firstWhere((a) => a.id == accountId);

    final localPath = _mapRemoteToLocal(
      remoteFile.path,
      account.rootPath,
      mediaType,
    );

    // 下载到 staging，完成后由 ImportPipeline 处理入库
    final stagingPath = p.join(
      AppDirectories.stagingDir,
      '${remoteFile.path.hashCode}_${p.basename(remoteFile.path)}',
    );

    try {
      await storage.download(remoteFile.path, stagingPath, onProgress: onProgress, cancelToken: cancelToken);

      if (mediaType == MediaType.comic) {
        // 漫画走 ComicHandler，生成 comic_series / comic_chapters
        final series = await ComicHandler.importSingleComicFile(stagingPath);
        try {
          final stagingFile = File(stagingPath);
          if (await stagingFile.exists()) await stagingFile.delete();
        } catch (_) {}
        // 记录缓存
        if (series?.folderPath != null) {
          await OfflineCacheService.instance.recordDownload(
            series!.folderPath!,
            MediaType.comic,
            accountId: accountId,
          );
        }
        // 漫画不走 library_items，返回 null
        return null;
      }

      // 其他类型使用 ImportPipeline 统一入库
      final result = await ImportPipeline.instance.importSingleFile(
        stagingPath,
        forceType: mediaType,
      );

      // 清理 staging
      try {
        final stagingFile = File(stagingPath);
        if (await stagingFile.exists()) await stagingFile.delete();
      } catch (_) {}

      // 记录缓存
      if (result.isSuccess && result.item != null) {
        await OfflineCacheService.instance.recordDownload(
          result.item!.filePath,
          mediaType,
          accountId: accountId,
        );
      }

      return result.isSuccess ? result.item : null;
    } catch (e) {
      debugPrint('云端文件下载失败: ${remoteFile.path}, 错误: $e');
      // 清理 staging
      try {
        final stagingFile = File(stagingPath);
        if (await stagingFile.exists()) await stagingFile.delete();
      } catch (_) {}
      return null;
    }
  }

  /// 递归列出云端所有文件
  Future<List<CloudFile>> _listAllFiles(
    CloudStorage storage,
    String path,
  ) async {
    final result = <CloudFile>[];
    final items = await storage.listDirectory(path);

    for (final item in items) {
      if (item.isDirectory) {
        // 跳过 . 和 ..
        if (item.name == '.' || item.name == '..') continue;
        result.addAll(await _listAllFiles(storage, item.path));
      } else {
        result.add(item);
      }
    }

    return result;
  }

  // ===================== 阅读进度同步 =====================

  static const _progressRemotePath = '.shelf/reading_progress.json';

  /// 上传本地阅读进度到云端
  Future<bool> uploadReadingProgress(String accountId) async {
    try {
      final storage = await _getConnection(accountId);
      final json = await ReadingProgressSyncService.instance.exportProgressJson();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(json);

      // 写入临时文件后上传
      final tempPath = p.join(AppDirectories.stagingDir, 'progress_upload_${DateTime.now().millisecondsSinceEpoch}.json');
      await Directory(p.dirname(tempPath)).create(recursive: true);
      await File(tempPath).writeAsString(jsonStr);

      try {
        await storage.upload(tempPath, _progressRemotePath);
        return true;
      } finally {
        try { await File(tempPath).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CloudSync] 上传阅读进度失败: $e');
      return false;
    }
  }

  /// 从云端下载阅读进度并合并到本地
  Future<SyncResult?> downloadReadingProgress(String accountId) async {
    try {
      final storage = await _getConnection(accountId);
      final tempPath = p.join(AppDirectories.stagingDir, 'progress_download_${DateTime.now().millisecondsSinceEpoch}.json');
      await Directory(p.dirname(tempPath)).create(recursive: true);

      try {
        await storage.download(_progressRemotePath, tempPath);
      } catch (e) {
        // 云端没有进度文件，不算错误
        debugPrint('[CloudSync] 云端无阅读进度文件');
        return null;
      }

      try {
        final jsonStr = await File(tempPath).readAsString();
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return await ReadingProgressSyncService.instance.importProgressJson(json);
      } finally {
        try { await File(tempPath).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CloudSync] 下载阅读进度失败: $e');
      return null;
    }
  }

  /// 将云端路径映射到本地路径
  String _mapRemoteToLocal(
    String remotePath,
    String rootPath,
    MediaType mediaType,
  ) {
    // 去掉 rootPath 前缀，得到相对路径
    var relativePath = remotePath;
    if (rootPath != '/' && remotePath.startsWith(rootPath)) {
      relativePath = remotePath.substring(rootPath.length);
    }
    if (relativePath.startsWith('/')) {
      relativePath = relativePath.substring(1);
    }

    final typeDir = p.join(AppDirectories.mediaRootDir, mediaType.name);
    return p.join(typeDir, relativePath);
  }
}
