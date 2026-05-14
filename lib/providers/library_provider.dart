import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import '../database/library_dao.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import '../services/file_import_service.dart';
import '../services/cover_service.dart';
import '../services/music_scan_service.dart';
import '../services/folder_settings_service.dart';
import '../database/song_dao.dart';
import '../services/music_player_service.dart';
import '../services/app_directories.dart';
import '../services/privacy_service.dart';
import '../screens/media/music/music_library_view.dart';
import '../services/import_pipeline.dart';
import '../services/offline_cache_service.dart';

class LibraryProvider extends ChangeNotifier {
  final LibraryDao _dao = LibraryDao();
  final FileImportService _importService = FileImportService.instance;

  List<LibraryItem> _allItems = [];
  List<LibraryItem> _recentItems = [];
  bool _isLoading = false;
  String? _error;

  LibraryProvider() {
    PrivacyService.instance.addListener(_onPrivacyChanged);
  }

  void _onPrivacyChanged() {
    if (!PrivacyService.instance.isUnlocked) {
      loadLibrary();
    }
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyChanged);
    super.dispose();
  }

  List<LibraryItem> get allItems => List.unmodifiable(_allItems);
  List<LibraryItem> get recentItems => List.unmodifiable(_recentItems);
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<LibraryItem> get novels => _allItems.where((i) => i.mediaType == MediaType.novel).toList();
  List<LibraryItem> get comics => _allItems.where((i) => i.mediaType == MediaType.comic).toList();
  List<LibraryItem> get videos => _allItems.where((i) => i.mediaType == MediaType.video).toList();
  List<LibraryItem> get musics => _allItems.where((i) => i.mediaType == MediaType.music).toList();
  List<LibraryItem> get favorites => _allItems.where((i) => i.isFavorite).toList();

  Future<void> loadLibrary() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allItems = await _dao.getAllItems();
      _recentItems = await _dao.getRecentItems(limit: 10);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshRecentItems() async {
    try {
      _recentItems = await _dao.getRecentItems(limit: 10);
      notifyListeners();
    } catch (e) {
      debugPrint('刷新最近阅读失败: $e');
    }
  }

  Future<void> importFiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      final items = await _importService.pickAndImportFiles();
      if (items.any((i) => i.mediaType == MediaType.music)) {
        _syncMusicInBackground();
      }
      await loadLibrary();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importFolder() async {
    _isLoading = true;
    notifyListeners();

    try {
      final items = await _importService.pickAndImportFolder();
      if (items.any((i) => i.mediaType == MediaType.music)) {
        _syncMusicInBackground();
      }
      await loadLibrary();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<LibraryItem?> importFromWifi(String filePath) async {
    try {
      final item = await _importService.importFromWifi(filePath);
      if (item != null && item.mediaType == MediaType.music) {
        _syncMusicInBackground();
      }
      try {
        await loadLibrary();
      } catch (e) {
        debugPrint('加载书库失败: $e');
      }
      return item;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<LibraryItem?> importFromWifiWithType(String filePath, MediaType mediaType) async {
    try {
      final item = await _importService.importFromWifiWithType(filePath, mediaType);
      if (item != null && item.mediaType == MediaType.music) {
        _syncMusicInBackground();
      }
      try {
        await loadLibrary();
      } catch (e) {
        debugPrint('加载书库失败: $e');
      }
      return item;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> scanAndImportFromPaths(List<String> paths) async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = <ImportFileResult>[];
      for (final dirPath in paths) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase().replaceAll('.', '');
            if (_isSupportedExtension(ext)) {
              final result = await ImportPipeline.instance.importSingleFile(entity.path);
              results.add(result);
            }
          }
        }
      }
      if (results.any((r) => r.isSuccess && r.item?.mediaType == MediaType.music)) {
        _syncMusicInBackground();
      }
      await loadLibrary();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> scanAndImportFromPathsWithType(List<String> paths, MediaType mediaType) async {
    _isLoading = true;
    notifyListeners();

    try {
      final validExts = switch (mediaType) {
        MediaType.novel => ['txt', 'epub', 'pdf', 'mobi', 'azw3'],
        MediaType.comic => ['zip', 'cbz', 'rar', 'cbr', 'pdf', 'mobi', 'azw3'],
        MediaType.video => ['mp4', 'mkv', 'avi', 'mov', 'wmv'],
        MediaType.music => ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'],
      };

      final blacklist = await FolderSettingsService.instance.getBlacklist(mediaType);
      final lowerBlacklist = blacklist.map((f) => f.toLowerCase()).toList();

      bool isBlacklisted(String filePath) {
        final lowerPath = filePath.toLowerCase();
        for (final folder in lowerBlacklist) {
          if (lowerPath == folder || lowerPath.startsWith('$folder\\') || lowerPath.startsWith('$folder/')) {
            return true;
          }
        }
        return false;
      }

      final results = <ImportFileResult>[];
      for (final dirPath in paths) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            if (isBlacklisted(entity.path)) continue;
            final ext = path.extension(entity.path).toLowerCase().replaceAll('.', '');
            if (validExts.contains(ext)) {
              final result = await ImportPipeline.instance.importSingleFile(
                entity.path,
                forceType: mediaType,
              );
              results.add(result);
            }
          }
        }
      }
      if (mediaType == MediaType.music) {
        _syncMusicInBackground();
      }
      await loadLibrary();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> importFilesWithType(MediaType mediaType) async {
    _isLoading = true;
    notifyListeners();

    try {
      final items = await _importService.pickAndImportFilesWithType(mediaType);
      if (mediaType == MediaType.music) {
        _syncMusicInBackground();
      }
      await loadLibrary();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _syncMusicInBackground() {
    MusicScanService.instance.syncFromLibrary().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MusicLibraryView.globalKey.currentState?.refresh();
      });
    }).catchError((e) {
      debugPrint('音乐同步失败: $e');
    });
  }

  static bool _isSupportedExtension(String ext) {
    return [
      'txt', 'epub', 'pdf', 'mobi', 'azw3',
      'zip', 'cbz', 'rar', 'cbr',
      'mp4', 'mkv', 'avi',
      'mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a',
    ].contains(ext);
  }

  Future<void> moveItemToType(int itemId, MediaType newType) async {
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _allItems[index];
    if (item.mediaType == newType) return;

    final newDir = Directory(path.join(AppDirectories.mediaRootDir, newType.name));
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    final newFilePath = path.join(newDir.path, path.basename(item.filePath));
    final file = File(item.filePath);
    if (await file.exists()) {
      try {
        await file.rename(newFilePath);
      } catch (_) {
        // 跨文件系统时 rename 会失败，fallback 到 copy+delete
        await file.copy(newFilePath);
        await file.delete();
      }
    }

    String? newCoverPath;
    if (item.coverPath != null) {
      final coverFile = File(item.coverPath!);
      if (await coverFile.exists()) {
        newCoverPath = path.join(newDir.path, path.basename(item.coverPath!));
        try {
          await coverFile.rename(newCoverPath);
        } catch (_) {
          // 跨文件系统时 rename 会失败，fallback 到 copy+delete
          await coverFile.copy(newCoverPath);
          await coverFile.delete();
        }
      }
    }

    final updated = item.copyWith(
      mediaType: newType,
      filePath: newFilePath,
      coverPath: newCoverPath ?? item.coverPath,
    );

    await _dao.updateItem(updated);
    _allItems[index] = updated;
    notifyListeners();
  }

  Future<void> moveItemsToType(List<int> itemIds, MediaType newType) async {
    for (final id in itemIds) {
      await moveItemToType(id, newType);
    }
  }

  Future<void> changeCover(int itemId) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final index = _allItems.indexWhere((i) => i.id == itemId);
      if (index == -1) return;
      final item = _allItems[index];
      final coverPath = await CoverService.instance.saveCustomCover(
        bytes,
        item.title,
      );

      if (coverPath != null) {
        await updateCover(itemId, coverPath);
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateItemInfo(int itemId, {String? title, String? author, String? description}) async {
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _allItems[index];
    String? newFilePath = item.filePath;

    // 标题变更时同步重命名源文件
    if (title != null && title.isNotEmpty && title != item.title) {
      final file = File(item.filePath);
      if (await file.exists()) {
        final dir = path.dirname(item.filePath);
        final ext = path.extension(item.filePath);
        var newName = '$title$ext';
        var candidate = path.join(dir, newName);

        int suffix = 1;
        while (await File(candidate).exists()) {
          newName = '${title}_$suffix$ext';
          candidate = path.join(dir, newName);
          suffix++;
        }

        try {
          await file.rename(candidate);
          newFilePath = candidate;
        } catch (_) {
          // 重命名失败时保留原路径，继续更新数据库
        }
      }
    }

    // 如果是音乐文件，同步更新 songs 表中的路径
    if (newFilePath != item.filePath &&
        newFilePath != null &&
        item.mediaType == MediaType.music) {
      await SongDao().updateSongPath(
        item.filePath,
        newFilePath,
        path.dirname(newFilePath),
      );
    }

    final updated = item.copyWith(
      title: title,
      author: author,
      description: description,
      filePath: newFilePath,
    );

    await _dao.updateItem(updated);
    _allItems[index] = updated;
    notifyListeners();
  }

  Future<void> toggleFavorite(int itemId) async {
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _allItems[index];
    final updated = item.copyWith(isFavorite: !item.isFavorite);
    await _dao.updateItem(updated);
    _allItems[index] = updated;
    notifyListeners();
  }

  Future<void> updateCover(int itemId, String newCoverPath) async {
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _allItems[index];
    final updated = item.copyWith(coverPath: newCoverPath);
    await _dao.updateItem(updated);
    _allItems[index] = updated;
    notifyListeners();
  }

  // ===================== 删除 / 回收站 =====================

  /// 逻辑删除（不删物理文件）
  Future<void> deleteItem(int itemId) async {
    await _dao.deleteItem(itemId);
    _allItems.removeWhere((i) => i.id == itemId);
    _recentItems.removeWhere((i) => i.id == itemId);
    notifyListeners();
  }

  /// 批量逻辑删除
  Future<void> deleteItems(List<int> itemIds) async {
    for (final id in itemIds) {
      try {
        await _dao.deleteItem(id);
      } catch (e) {
        debugPrint('批量删除 item $id 失败: $e');
      }
    }
    _allItems.removeWhere((i) => itemIds.contains(i.id));
    _recentItems.removeWhere((i) => itemIds.contains(i.id));
    notifyListeners();
  }

  /// 彻底删除（物理删除数据库记录 + 文件 + songs 表记录）
  Future<void> permanentlyDeleteItem(int itemId) async {
    final item = await _dao.getRawItemById(itemId);
    if (item != null && item.mediaType == MediaType.music) {
      await SongDao().deleteSongsByPaths([item.filePath]);
    }
    await _dao.permanentlyDeleteItem(itemId);
    _allItems.removeWhere((i) => i.id == itemId);
    _recentItems.removeWhere((i) => i.id == itemId);
    notifyListeners();
  }

  /// 恢复逻辑删除的项
  Future<void> restoreItem(int itemId) async {
    await _dao.restoreItem(itemId);
    await loadLibrary();
  }

  /// 查询回收站内容
  Future<List<LibraryItem>> getDeletedItems() async {
    return await _dao.getDeletedItems();
  }

  Future<void> updateTags(int itemId, List<String> tags) async {
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    final item = _allItems[index];
    final updated = item.copyWith(tags: tags);
    await _dao.updateItem(updated);
    _allItems[index] = updated;
    notifyListeners();
  }

  Future<void> setItemsPrivate(List<int> itemIds, bool isPrivate) async {
    for (final id in itemIds) {
      final index = _allItems.indexWhere((i) => i.id == id);
      if (index == -1) continue;
      final item = _allItems[index];
      if (item.isPrivate == isPrivate) continue;
      final updated = item.copyWith(isPrivate: isPrivate);
      await _dao.updateItem(updated);
      if (isPrivate) {
        // 标记为私密后从当前列表移除，避免用户以为没生效
        _allItems.removeAt(index);
        _recentItems.removeWhere((i) => i.id == id);
      } else {
        _allItems[index] = updated;
      }
    }
    notifyListeners();
  }

  Future<void> setItemsFavorite(List<int> itemIds, bool favorite) async {
    for (final id in itemIds) {
      final index = _allItems.indexWhere((i) => i.id == id);
      if (index == -1) continue;
      final item = _allItems[index];
      if (item.isFavorite == favorite) continue;
      final updated = item.copyWith(isFavorite: favorite);
      await _dao.updateItem(updated);
      _allItems[index] = updated;
    }
    notifyListeners();
  }

  Future<void> setItemsGroup(List<int> itemIds, String? groupName) async {
    for (final id in itemIds) {
      final index = _allItems.indexWhere((i) => i.id == id);
      if (index == -1) continue;
      final item = _allItems[index];
      final newTags = List<String>.from(item.tags)
        ..removeWhere((t) => t.startsWith('group:'));
      if (groupName != null && groupName.isNotEmpty) {
        newTags.add('group:$groupName');
      }
      final updated = item.copyWith(tags: newTags);
      await _dao.updateItem(updated);
      _allItems[index] = updated;
    }
    notifyListeners();
  }

  Future<void> updateReadingProgress(int itemId, int position, String positionText, double percentage) async {
    final progress = ReadingProgress(
      itemId: itemId,
      position: position,
      positionText: positionText,
      percentage: percentage,
      lastReadAt: DateTime.now(),
      chapterIndex: -1,
      chapterOffset: percentage,
    );
    await _dao.saveProgress(progress);
    await _dao.updateLastOpened(itemId);

    // 更新离线缓存访问时间
    final idx = _allItems.indexWhere((i) => i.id == itemId);
    if (idx != -1) {
      await OfflineCacheService.instance.touchAccess(_allItems[idx].filePath);
    }

    // 更新本地列表中的 lastOpenedDate
    final index = _allItems.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      _allItems[index] = _allItems[index].copyWith(
        lastOpenedDate: DateTime.now(),
      );
      _allItems.sort((a, b) {
        if (a.lastOpenedDate == null && b.lastOpenedDate == null) return 0;
        if (a.lastOpenedDate == null) return 1;
        if (b.lastOpenedDate == null) return -1;
        return b.lastOpenedDate!.compareTo(a.lastOpenedDate!);
      });
      _recentItems = await _dao.getRecentItems(limit: 10);
      notifyListeners();
    }
  }

  Future<ReadingProgress?> getReadingProgress(int itemId) async {
    return await _dao.getProgress(itemId);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _refreshMusicLibraryIfNeeded(MediaType mediaType) {
    if (mediaType == MediaType.music) {
      // 延迟一帧，确保数据库事务已提交
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MusicLibraryView.globalKey.currentState?.refresh();
      });
    }
  }

  /// 清空所有数据（保留表结构），并删除导入的物理文件
  Future<void> clearAllData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 删除导入的物理文件
      final libraryDir = Directory(AppDirectories.mediaRootDir);
      if (await libraryDir.exists()) {
        await libraryDir.delete(recursive: true);
      }
      // 删除 WiFi 上传的临时文件
      final wifiDir = Directory(AppDirectories.wifiUploadDir);
      if (await wifiDir.exists()) {
        await wifiDir.delete(recursive: true);
      }
      // 删除封面缓存
      final coverDir = Directory(AppDirectories.coversCacheDir);
      if (await coverDir.exists()) {
        await coverDir.delete(recursive: true);
      }
      // 删除音乐元数据封面缓存
      final musicCoverDir = Directory(AppDirectories.musicCoversCacheDir);
      if (await musicCoverDir.exists()) {
        await musicCoverDir.delete(recursive: true);
      }

      // 清空数据库表
      await _dao.clearAllData();
      await SongDao().clearAllData();

      // 清空音乐播放器队列和状态
      await MusicPlayerService.instance.clearQueue();

      _allItems = [];
      _recentItems = [];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
