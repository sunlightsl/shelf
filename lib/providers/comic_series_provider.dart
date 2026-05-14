import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../database/comic_series_dao.dart';
import '../database/library_dao.dart';
import '../models/comic_chapter.dart';
import '../models/comic_reading_progress.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';
import '../services/app_directories.dart';
import '../services/comic_scan_service.dart';
import '../services/offline_cache_service.dart';
import '../services/privacy_service.dart';

class ComicSeriesProvider extends ChangeNotifier {
  final ComicSeriesDao _dao = ComicSeriesDao();

  List<ComicSeries> _series = [];
  List<ComicSeries> get series => _series;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  ComicSeries? _selectedSeries;
  ComicSeries? get selectedSeries => _selectedSeries;

  List<ComicChapter> _chapters = [];
  List<ComicChapter> get chapters => _chapters;

  ComicReadingProgress? _progress;
  ComicReadingProgress? get progress => _progress;

  ComicSeriesProvider() {
    PrivacyService.instance.addListener(_onPrivacyChanged);
  }

  void _onPrivacyChanged() {
    if (!PrivacyService.instance.isUnlocked) {
      loadSeries();
    }
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyChanged);
    super.dispose();
  }

  Future<void> loadSeries() async {
    _isLoading = true;
    notifyListeners();

    // 每次加载都尝试从 library_items 表迁移未归类的漫画数据
    // （包括从其他分类批量移动过来的漫画）
    await _migrateOldComics();
    _series = await _dao.getAllSeries();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _migrateOldComics() async {
    final libraryDao = LibraryDao();
    List<LibraryItem> oldComics;
    try {
      oldComics = await libraryDao.getItemsByType(MediaType.comic);
    } catch (e) {
      // library_items 表可能不存在（全新安装或数据库损坏），无需迁移
      return;
    }
    if (oldComics.isEmpty) return;

    // 按系列名分组
    final groups = <String, List<LibraryItem>>{};
    for (final item in oldComics) {
      final seriesName = ComicScanService.extractSeriesName(p.basename(item.filePath));
      groups.putIfAbsent(seriesName, () => []).add(item);
    }

    for (final entry in groups.entries) {
      final seriesName = entry.key;
      final items = entry.value;

      // 如果组内只有一个文件，且文件名和系列名几乎一样，当作单文件系列
      if (items.length == 1 && ComicScanService.extractSeriesName(p.basename(items.first.filePath)) == seriesName) {
        final item = items.first;
        final existing = await _dao.getSeriesByFolderPath(item.filePath);
        if (existing != null) continue;

        final parsed = ComicScanService.parseFilename(p.basename(item.filePath));
        await _dao.insertSeriesWithChapters(
          ComicSeries(
            title: seriesName,
            folderPath: item.filePath,
            coverPath: item.coverPath,
            author: item.author,
            description: item.description,
            tags: item.tags,
            sourceType: ComicSourceType.singleFile,
            lastReadAt: item.lastOpenedDate,
          ),
          [
            ComicChapter(
              seriesId: 0,
              title: parsed.title,
              chapterNumber: parsed.chapterNumber,
              volumeNumber: parsed.volumeNumber,
              filePath: item.filePath,
              format: item.format,
              fileSize: item.fileSize,
              sortOrder: 0,
              coverPath: item.coverPath,
            ),
          ],
        );
      } else {
        // 多文件 → 合并为一个系列
        final first = items.first;
        final chapters = <ComicChapter>[];

        for (int i = 0; i < items.length; i++) {
          final item = items[i];
          final parsed = ComicScanService.parseFilename(p.basename(item.filePath));
          chapters.add(ComicChapter(
            seriesId: 0,
            title: parsed.title,
            chapterNumber: parsed.chapterNumber,
            volumeNumber: parsed.volumeNumber,
            filePath: item.filePath,
            format: item.format,
            fileSize: item.fileSize,
            sortOrder: i,
            coverPath: item.coverPath,
          ));
        }

        await _dao.insertSeriesWithChapters(
          ComicSeries(
            title: seriesName,
            folderPath: p.dirname(first.filePath),
            coverPath: first.coverPath,
            author: first.author,
            description: first.description,
            tags: first.tags,
            sourceType: ComicSourceType.folderSeries,
            lastReadAt: first.lastOpenedDate,
          ),
          chapters,
        );
      }
    }
  }

  Future<void> scanAndImportDirectory(String dirPath) async {
    _isLoading = true;
    notifyListeners();

    final results = await ComicScanService.scanDirectory(dirPath);
    for (final result in results) {
      final existing = await _dao.getSeriesByFolderPath(result.series.folderPath ?? '');
      if (existing != null) {
        // 更新已有系列的章节列表
        final existingChapters = await _dao.getChaptersBySeries(existing.id!);
        final existingPaths = existingChapters.map((c) => c.filePath).toSet();
        final newChapters = result.chapters
            .where((c) => !existingPaths.contains(c.filePath))
            .toList();
        if (newChapters.isNotEmpty) {
          for (final chapter in newChapters) {
            await _dao.insertChapter(chapter.copyWith(
              seriesId: existing.id!,
              sortOrder: existingChapters.length + newChapters.indexOf(chapter),
            ));
          }
          await _dao.updateSeriesChapterCount(existing.id!);
        }
      } else {
        await _dao.insertSeriesWithChapters(result.series, result.chapters);
      }
    }

    await loadSeries();
  }

  Future<void> selectSeries(ComicSeries series) async {
    _selectedSeries = series;
    _chapters = await _dao.getChaptersBySeries(series.id!);
    _progress = await _dao.getProgressBySeries(series.id!);
    notifyListeners();
  }

  Future<void> markChapterRead(int chapterId, bool isRead) async {
    await _dao.markChapterRead(chapterId, isRead);
    if (_selectedSeries != null) {
      await _dao.updateSeriesChapterCount(_selectedSeries!.id!);
      _chapters = await _dao.getChaptersBySeries(_selectedSeries!.id!);
      _selectedSeries = await _dao.getSeriesById(_selectedSeries!.id!);
    }
    notifyListeners();
  }

  Future<void> saveProgress(int seriesId, int? chapterId, int currentPage, int totalPages) async {
    final percentage = totalPages > 0 ? currentPage / totalPages : 0.0;
    await _dao.saveProgress(ComicReadingProgress(
      seriesId: seriesId,
      chapterId: chapterId,
      currentPage: currentPage,
      totalPages: totalPages,
      percentage: percentage,
    ));
    final series = await _dao.getSeriesById(seriesId);
    if (series != null) {
      await _dao.updateSeries(
        series.copyWith(lastReadAt: DateTime.now()),
      );
      // 更新离线缓存访问时间
      if (series.folderPath != null) {
        await OfflineCacheService.instance.touchAccess(series.folderPath!);
      }
    }
    _progress = await _dao.getProgressBySeries(seriesId);
    notifyListeners();
  }

  // ===================== 删除 / 回收站 =====================

  /// 逻辑删除系列（不删物理文件）
  Future<void> deleteSeries(int seriesId) async {
    await _dao.deleteSeries(seriesId);
    _series.removeWhere((s) => s.id == seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = null;
      _chapters = [];
      _progress = null;
    }
    notifyListeners();
  }

  /// 彻底删除系列（物理删除数据库记录 + 文件）
  Future<void> permanentlyDeleteSeries(int seriesId) async {
    final chapters = await _dao.getChaptersBySeries(seriesId);
    for (final chapter in chapters) {
      try {
        final file = File(chapter.filePath);
        if (await file.exists()) await file.delete();
        if (chapter.coverPath != null) {
          final coverFile = File(chapter.coverPath!);
          if (await coverFile.exists()) await coverFile.delete();
        }
      } catch (e) {
        // 忽略
      }
    }
    await _dao.permanentlyDeleteSeries(seriesId);
    _series.removeWhere((s) => s.id == seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = null;
      _chapters = [];
      _progress = null;
    }
    notifyListeners();
  }

  /// 恢复逻辑删除的系列
  Future<void> restoreSeries(int seriesId) async {
    await _dao.restoreSeries(seriesId);
    await loadSeries();
  }

  /// 加载回收站内容
  Future<List<ComicSeries>> loadDeletedSeries() async {
    return await _dao.getDeletedSeries();
  }

  // ===================== 合并 =====================

  Future<void> mergeSeries(List<int> seriesIds, String newTitle) async {
    if (seriesIds.length < 2) return;

    _isLoading = true;
    notifyListeners();

    // 获取所有要合并的系列和章节
    final allChapters = <ComicChapter>[];
    ComicSeries? firstSeries;

    for (final id in seriesIds) {
      final series = await _dao.getSeriesById(id);
      if (series == null) continue;
      firstSeries ??= series;

      final chapters = await _dao.getChaptersBySeries(id);
      allChapters.addAll(chapters);

      // 物理删除旧系列（合并后不需要保留在回收站）
      await _dao.permanentlyDeleteSeries(id);
    }

    // 按文件名排序
    allChapters.sort((a, b) => p.basename(a.filePath).compareTo(p.basename(b.filePath)));

    // 重新分配 sortOrder，并清除旧 id 避免覆盖已有记录
    final reorderedChapters = <ComicChapter>[];
    for (int i = 0; i < allChapters.length; i++) {
      reorderedChapters.add(allChapters[i].copyWith(
        id: null,
        seriesId: 0,
        sortOrder: i,
      ));
    }

    // 创建新系列
    await _dao.insertSeriesWithChapters(
      ComicSeries(
        title: newTitle.isEmpty ? (firstSeries?.title ?? '合并系列') : newTitle,
        folderPath: firstSeries?.folderPath,
        coverPath: firstSeries?.coverPath,
        author: firstSeries?.author,
        description: firstSeries?.description,
        tags: firstSeries?.tags ?? [],
        sourceType: ComicSourceType.folderSeries,
      ),
      reorderedChapters,
    );

    await loadSeries();
  }

  // ===================== 信息更新 =====================

  Future<void> updateSeriesInfo(int seriesId, {String? title, String? author, String? description}) async {
    final series = await _dao.getSeriesById(seriesId);
    if (series == null) return;
    await _dao.updateSeries(series.copyWith(
      title: title,
      author: author,
      description: description,
    ));
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = await _dao.getSeriesById(seriesId);
    }
    final index = _series.indexWhere((s) => s.id == seriesId);
    if (index != -1) {
      _series[index] = await _dao.getSeriesById(seriesId) ?? _series[index];
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(int seriesId) async {
    final series = await _dao.getSeriesById(seriesId);
    if (series == null) return;
    await _dao.toggleFavorite(seriesId, !series.isFavorite);
    final updated = await _dao.getSeriesById(seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = updated;
    }
    final index = _series.indexWhere((s) => s.id == seriesId);
    if (index != -1 && updated != null) {
      _series[index] = updated;
    }
    notifyListeners();
  }

  Future<void> setSeriesPrivate(int seriesId, bool isPrivate) async {
    final series = await _dao.getSeriesById(seriesId);
    if (series == null || series.isPrivate == isPrivate) return;
    await _dao.updateSeries(series.copyWith(isPrivate: isPrivate));
    final updated = await _dao.getSeriesById(seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = updated;
    }
    final index = _series.indexWhere((s) => s.id == seriesId);
    if (index != -1) {
      if (isPrivate) {
        // 标记为私密后从当前列表移除，避免用户以为没生效
        _series.removeAt(index);
      } else if (updated != null) {
        _series[index] = updated;
      }
    }
    notifyListeners();
  }

  Future<void> setSeriesGroup(int seriesId, String? group) async {
    final series = await _dao.getSeriesById(seriesId);
    if (series == null) return;
    final tags = List<String>.from(series.tags);
    tags.removeWhere((t) => t.startsWith('分组:'));
    if (group != null && group.isNotEmpty) {
      tags.add('分组:$group');
    }
    await _dao.updateSeries(series.copyWith(tags: tags));
    final updated = await _dao.getSeriesById(seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = updated;
    }
    final index = _series.indexWhere((s) => s.id == seriesId);
    if (index != -1 && updated != null) {
      _series[index] = updated;
    }
    notifyListeners();
  }

  /// 将漫画系列移动到其他媒体类型
  Future<void> moveSeriesToType(int seriesId, MediaType newType) async {
    final series = await _dao.getSeriesById(seriesId);
    if (series == null) return;

    final sourcePath = series.folderPath;
    if (sourcePath == null) return;

    final newDir = Directory(p.join(AppDirectories.mediaRootDir, newType.name));
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    final destPath = p.join(newDir.path, p.basename(sourcePath));
    final sourceStat = await FileStat.stat(sourcePath);

    // 移动文件/文件夹
    if (sourceStat.type == FileSystemEntityType.directory) {
      await _moveDirectory(Directory(sourcePath), Directory(destPath));
    } else if (sourceStat.type == FileSystemEntityType.file) {
      final sourceFile = File(sourcePath);
      try {
        await sourceFile.rename(destPath);
      } catch (_) {
        await sourceFile.copy(destPath);
        await sourceFile.delete();
      }
    }

    // 移动封面
    String? newCoverPath;
    if (series.coverPath != null) {
      final coverFile = File(series.coverPath!);
      if (await coverFile.exists()) {
        newCoverPath = p.join(newDir.path, p.basename(series.coverPath!));
        try {
          await coverFile.rename(newCoverPath);
        } catch (_) {
          await coverFile.copy(newCoverPath);
          await coverFile.delete();
        }
      }
    }

    // 在 library_items 中创建新记录
    final libraryDao = LibraryDao();
    final chapters = await _dao.getChaptersBySeries(seriesId);
    final firstChapter = chapters.isNotEmpty ? chapters.first : null;
    await libraryDao.insertItem(LibraryItem(
      title: series.title,
      mediaType: newType,
      format: firstChapter?.format ?? FileFormat.unknown,
      filePath: destPath,
      coverPath: newCoverPath,
      author: series.author,
      description: series.description,
      tags: series.tags,
      addedDate: DateTime.now(),
    ));

    // 删除漫画系列
    await _dao.permanentlyDeleteSeries(seriesId);
    _series.removeWhere((s) => s.id == seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = null;
      _chapters = [];
      _progress = null;
    }
    notifyListeners();
  }

  Future<void> _moveDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    await for (final entity in source.list()) {
      final newPath = p.join(target.path, p.basename(entity.path));
      if (entity is File) {
        try {
          await entity.rename(newPath);
        } catch (_) {
          await entity.copy(newPath);
          await entity.delete();
        }
      } else if (entity is Directory) {
        await _moveDirectory(entity, Directory(newPath));
      }
    }
    await source.delete(recursive: true);
  }

  Future<void> changeCover(int seriesId, String coverPath) async {
    await _dao.updateSeriesCover(seriesId, coverPath);
    final updated = await _dao.getSeriesById(seriesId);
    if (_selectedSeries?.id == seriesId) {
      _selectedSeries = updated;
    }
    final index = _series.indexWhere((s) => s.id == seriesId);
    if (index != -1 && updated != null) {
      _series[index] = updated;
    }
    notifyListeners();
  }

  // ===================== 章节操作 =====================

  Future<void> updateChapterTitle(int chapterId, String? title) async {
    await _dao.updateChapterTitle(chapterId, title);
    if (_selectedSeries != null) {
      _chapters = await _dao.getChaptersBySeries(_selectedSeries!.id!);
    }
    notifyListeners();
  }

  Future<void> moveChapterOrder(int chapterId, int newSortOrder) async {
    await _dao.updateChapterSortOrder(chapterId, newSortOrder);
    if (_selectedSeries != null) {
      _chapters = await _dao.getChaptersBySeries(_selectedSeries!.id!);
    }
    notifyListeners();
  }

  Future<void> changeChapterCover(int chapterId, String coverPath) async {
    await _dao.updateChapterCover(chapterId, coverPath);
    if (_selectedSeries != null) {
      _chapters = await _dao.getChaptersBySeries(_selectedSeries!.id!);
    }
    notifyListeners();
  }

  Future<void> deleteChapter(int chapterId) async {
    await _dao.deleteChapter(chapterId);
    if (_selectedSeries != null) {
      await _dao.updateSeriesChapterCount(_selectedSeries!.id!);
      _chapters = await _dao.getChaptersBySeries(_selectedSeries!.id!);
      _selectedSeries = await _dao.getSeriesById(_selectedSeries!.id!);
    }
    notifyListeners();
  }

  /// 清空所有漫画数据（保留表结构），并删除导入的物理文件
  Future<void> clearAllData() async {
    _isLoading = true;
    notifyListeners();
    await _dao.clearAllData();
    _series = [];
    _selectedSeries = null;
    _chapters = [];
    _progress = null;
    _isLoading = false;
    notifyListeners();
  }
}
