import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'metadata_service.dart';
import 'lyrics_parser.dart';

class LyricsService {
  static final LyricsService instance = LyricsService._internal();
  LyricsService._internal();

  /// 查找歌词内容：优先同目录 .lrc 文件，其次内嵌歌词
  Future<String?> findLyrics(String filePath) async {
    // 1. 查找同目录同名 .lrc 文件
    final lrcPath = '${p.withoutExtension(filePath)}.lrc';
    final lrcFile = File(lrcPath);
    if (await lrcFile.exists()) {
      try {
        return await lrcFile.readAsString();
      } catch (e) {
        debugPrint('读取 LRC 文件失败: $e');
      }
    }

    // 2. 尝试读取内嵌歌词（audio_metadata_reader 现在支持）
    try {
      final meta = await MetadataService.instance.readMetadata(filePath);
      if (meta.lyrics != null && meta.lyrics!.trim().isNotEmpty) {
        return meta.lyrics;
      }
    } catch (e) {
      debugPrint('读取内嵌歌词失败: $e');
    }

    return null;
  }

  /// 解析歌词文件
  Future<List<LyricLine>?> parseLyrics(String filePath) async {
    final content = await findLyrics(filePath);
    if (content == null || content.trim().isEmpty) return null;
    return LyricsParser.parse(content);
  }
}
