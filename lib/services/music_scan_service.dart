import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/library_item.dart';
import '../models/song.dart';
import '../database/song_dao.dart';
import '../database/library_dao.dart';
import 'metadata_service.dart';
import 'folder_settings_service.dart';

class MusicScanService {
  static final MusicScanService instance = MusicScanService._internal();
  MusicScanService._internal();

  final SongDao _songDao = SongDao();
  final LibraryDao _libraryDao = LibraryDao();
  final FolderSettingsService _folderSettings = FolderSettingsService.instance;

  Future<void>? _syncInProgress;

  /// 将 library_items 中的音乐同步到 songs 表，并提取 ID3 标签
  Future<int> syncFromLibrary() async {
    // 防止并发执行：如果已有同步在进行，等待它完成并复用结果
    if (_syncInProgress != null) {
      await _syncInProgress;
      return _songDao.getAllSongs().then((s) => s.length);
    }

    final completer = Completer<void>();
    _syncInProgress = completer.future;

    try {
      final count = await _doSync();
      return count;
    } finally {
      completer.complete();
      _syncInProgress = null;
    }
  }

  Future<int> _doSync() async {
    final items = await _libraryDao.getItemsByType(MediaType.music);

    if (items.isEmpty) return 0;

    final allSongs = await _songDao.getAllSongs();

    // 快速路径：没有文件增删时跳过元数据重新读取
    final currentPaths = items.map((i) => i.filePath).toSet();
    final existingPaths = allSongs.map((s) => s.filePath).toSet();
    if (currentPaths.length == existingPaths.length &&
        currentPaths.every(existingPaths.contains)) {
      return allSongs.length;
    }

    // 建立已有 song 的查找表，增量同步时复用已有元数据
    final existingSongsMap = <String, Song>{};
    for (final s in allSongs) {
      existingSongsMap[s.filePath] = s;
    }

    final songs = <Song>[];
    for (final item in items) {
      final existing = existingSongsMap[item.filePath];

      // 如果已有记录且文件大小未变，直接复用，避免重复读取元数据
      if (existing != null && existing.fileSize == item.fileSize) {
        songs.add(existing);
        continue;
      }

      var song = Song(
        filePath: item.filePath,
        folderPath: p.dirname(item.filePath),
        title: item.title,
        artist: item.author,
        coverPath: item.coverPath,
        fileSize: item.fileSize,
        duration: item.totalProgress,
      );

      // 尝试读取 ID3 标签和封面（单文件失败不应影响整体同步）
      try {
        final meta = await MetadataService.instance
            .readMetadata(item.filePath)
            .timeout(const Duration(seconds: 5));
        String? coverPath = item.coverPath;
        if (meta.coverBytes != null) {
          coverPath = await MetadataService.instance.saveCoverImage(
            meta.coverBytes!,
            item.filePath,
          );
        }
        song = song.copyWith(
          title: meta.title?.trim().isNotEmpty == true ? meta.title : song.title,
          artist: meta.artist?.trim().isNotEmpty == true ? meta.artist : song.artist,
          album: meta.album?.trim().isNotEmpty == true ? meta.album : null,
          duration: meta.durationMs ?? song.duration,
          coverPath: coverPath,
        );
      } on TimeoutException {
        debugPrint('读取音乐元数据超时: ${item.filePath}');
      } catch (e) {
        debugPrint('读取音乐元数据失败: ${item.filePath}, 错误: $e');
      }

      songs.add(song);
    }

    await _songDao.insertSongs(songs);

    return songs.length;
  }

  /// 从指定目录扫描音乐文件
  Future<List<Song>> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final blacklist = await _folderSettings.getBlacklist(MediaType.music);
    final lowerBlacklist = blacklist.map((f) => f.toLowerCase()).toList();

    bool isBlacklisted(String path) {
      final lowerPath = path.toLowerCase();
      for (final folder in lowerBlacklist) {
        if (lowerPath == folder || lowerPath.startsWith('$folder\\') || lowerPath.startsWith('$folder/')) {
          return true;
        }
      }
      return false;
    }

    final songs = <Song>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        if (isBlacklisted(entity.path)) continue;
        final ext = entity.path.split('.').last.toLowerCase();
        if (['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'].contains(ext)) {
          final stat = await entity.stat();
          songs.add(Song(
            filePath: entity.path,
            folderPath: p.dirname(entity.path),
            title: _fileNameWithoutExt(entity.path),
            fileSize: stat.size,
          ));
        }
      }
    }
    return songs;
  }

  String _fileNameWithoutExt(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
