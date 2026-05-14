import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;
import 'app_directories.dart';

class MetadataResult {
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final Uint8List? coverBytes;
  final String? lyrics;

  MetadataResult({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.coverBytes,
    this.lyrics,
  });
}

class MetadataService {
  static final MetadataService instance = MetadataService._internal();
  MetadataService._internal();

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    MetadataGod.initialize();
    _initialized = true;
  }

  Future<MetadataResult> readMetadata(String filePath) async {
    // 优先使用 audio_metadata_reader（纯 Dart，支持歌词+FLAC 封面）
    try {
      final metadata = await amr.readMetadata(File(filePath), getImage: true);
      if (metadata is! amr.InvalidTag) {
        Uint8List? coverBytes;
        if (metadata.pictures.isNotEmpty) {
          coverBytes = metadata.pictures.first.bytes;
        }
        return MetadataResult(
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          durationMs: metadata.duration?.inMilliseconds,
          coverBytes: coverBytes,
          lyrics: metadata.lyrics,
        );
      }
    } catch (e) {
      debugPrint('audio_metadata_reader 失败: $filePath, 错误: $e');
    }

    // 回退到 metadata_god
    await _ensureInitialized();
    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);
      return MetadataResult(
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        durationMs: metadata.duration?.inMilliseconds,
        coverBytes: metadata.picture?.data,
        lyrics: null,
      );
    } catch (e) {
      debugPrint('读取元数据失败: $filePath, 错误: $e');
      return MetadataResult();
    }
  }

  Future<String?> saveCoverImage(Uint8List bytes, String baseName) async {
    try {
      final coverDir = Directory(AppDirectories.musicCoversCacheDir);
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }
      final coverPath = p.join(coverDir.path, '${baseName.hashCode}_cover.jpg');
      final file = File(coverPath);

      Uint8List data = bytes;
      if (bytes.length > 200 * 1024) {
        data = await Isolate.run(() => _resizeCoverImage(bytes));
      }

      await file.writeAsBytes(data);
      return coverPath;
    } catch (e) {
      debugPrint('保存封面失败: $e');
      return null;
    }
  }

  Future<String?> extractAndSaveCover(String filePath) async {
    final result = await readMetadata(filePath);
    if (result.coverBytes != null) {
      final baseName = p.basenameWithoutExtension(filePath);
      return saveCoverImage(result.coverBytes!, baseName);
    }
    return null;
  }

  /// 写入音频文件的 ID3 标签
  Future<void> writeMetadata({
    required String filePath,
    String? title,
    String? artist,
    String? album,
    Uint8List? coverBytes,
  }) async {
    await _ensureInitialized();
    try {
      await MetadataGod.writeMetadata(
        file: filePath,
        metadata: Metadata(
          title: title,
          artist: artist,
          album: album,
          picture: coverBytes != null
              ? Picture(
                  data: coverBytes,
                  mimeType: 'image/jpeg',
                )
              : null,
        ),
      );
    } catch (e) {
      debugPrint('写入元数据失败: $filePath, 错误: $e');
      rethrow;
    }
  }

  static Uint8List _resizeCoverImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final resized = img.copyResize(decoded, width: 400);
      return img.encodeJpg(resized, quality: 85);
    }
    return bytes;
  }
}
