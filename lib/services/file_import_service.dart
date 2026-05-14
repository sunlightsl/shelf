import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/library_item.dart';
import '../models/comic_series.dart';
import 'import_pipeline.dart';
import 'comic_handler.dart';

class FileImportService {
  static final FileImportService instance = FileImportService._init();
  FileImportService._init();

  final ImportPipeline _pipeline = ImportPipeline.instance;

  // ===================== 通用导入 =====================

  Future<List<LibraryItem>> pickAndImportFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'txt', 'epub', 'pdf', 'mobi', 'azw3',
        'zip', 'cbz', 'rar', 'cbr',
        'mp4', 'mkv', 'avi',
        'mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a',
      ],
    );

    if (result == null || result.files.isEmpty) return [];

    final items = <LibraryItem>[];
    for (final file in result.files) {
      if (file.path != null) {
        final mediaType = _detectTypeFromPath(file.path!);
        if (mediaType == MediaType.comic) {
          await ComicHandler.importSingleComicFile(file.path!);
        } else {
          final r = await _pipeline.importSingleFile(file.path!, displayName: file.name);
          if (r.isSuccess && r.item != null) items.add(r.item!);
        }
      }
    }
    return items;
  }

  Future<List<LibraryItem>> pickAndImportFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    if (selectedPath == null) return [];

    final type = _detectTypeFromFolder(selectedPath);
    if (type == MediaType.comic) {
      await ComicHandler.importComicFolder(selectedPath);
      return [];
    }

    final results = await _pipeline.importFolder(selectedPath);
    return results.where((r) => r.isSuccess).map((r) => r.item!).toList();
  }

  Future<List<LibraryItem>> pickAndImportFilesWithType(MediaType mediaType) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _extensionsForType(mediaType),
    );

    if (result == null || result.files.isEmpty) return [];

    if (mediaType == MediaType.comic) {
      for (final file in result.files) {
        if (file.path != null) {
          await ComicHandler.importSingleComicFile(file.path!);
        }
      }
      return [];
    }

    final items = <LibraryItem>[];
    for (final file in result.files) {
      if (file.path != null) {
        final r = await _pipeline.importSingleFile(
          file.path!,
          forceType: mediaType,
          displayName: file.name,
        );
        if (r.isSuccess && r.item != null) items.add(r.item!);
      }
    }
    return items;
  }

  Future<LibraryItem?> importFromWifi(String filePath) async {
    final mediaType = _detectTypeFromPath(filePath);
    if (mediaType == MediaType.comic) {
      await ComicHandler.importSingleComicFile(filePath);
      return null;
    }
    final result = await _pipeline.importSingleFile(filePath);
    return result.isSuccess ? result.item : null;
  }

  Future<LibraryItem?> importFromWifiWithType(String filePath, MediaType mediaType) async {
    if (mediaType == MediaType.comic) {
      await ComicHandler.importSingleComicFile(filePath);
      return null;
    }
    final result = await _pipeline.importSingleFile(filePath, forceType: mediaType);
    return result.isSuccess ? result.item : null;
  }

  // ===================== 辅助方法 =====================

  MediaType _detectTypeFromPath(String filePath) {
    final ext = path.extension(filePath).toLowerCase().replaceAll('.', '');
    return switch (ext) {
      'txt' || 'epub' || 'pdf' || 'mobi' || 'azw3' => MediaType.novel,
      'zip' || 'cbz' || 'rar' || 'cbr' => MediaType.comic,
      'mp4' || 'mkv' || 'avi' => MediaType.video,
      'mp3' || 'flac' || 'wav' || 'aac' || 'ogg' || 'm4a' => MediaType.music,
      _ => MediaType.novel,
    };
  }

  MediaType _detectTypeFromFolder(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return MediaType.novel;

    final types = <MediaType>{};
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        types.add(_detectTypeFromPath(entity.path));
      }
    }
    if (types.length == 1) return types.first;
    if (types.contains(MediaType.comic)) return MediaType.comic;
    if (types.contains(MediaType.novel)) return MediaType.novel;
    if (types.contains(MediaType.video)) return MediaType.video;
    return MediaType.music;
  }

  List<String> _extensionsForType(MediaType type) {
    return switch (type) {
      MediaType.novel => ['txt', 'epub', 'pdf', 'mobi', 'azw3'],
      MediaType.comic => ['zip', 'cbz', 'rar', 'cbr', 'pdf'],
      MediaType.video => ['mp4', 'mkv', 'avi'],
      MediaType.music => ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'],
    };
  }
}
