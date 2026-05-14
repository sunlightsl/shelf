import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as path;
import 'package:video_thumbnail/video_thumbnail.dart';
import '../design_tokens/app_colors.dart';
import 'package:epubx/epubx.dart';
import 'rar_service.dart';
import 'app_directories.dart';

class CoverService {
  static final CoverService instance = CoverService._init();
  CoverService._init();

  Future<String> getCoverDir() async {
    final coverDir = Directory(AppDirectories.coversCacheDir);
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }
    return coverDir.path;
  }

  Future<String?> extractEpubCover(String filePath, String fileName, {EpubBook? preloadedBook}) async {
    try {
      final EpubBook epub;
      if (preloadedBook != null) {
        epub = preloadedBook;
      } else {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        epub = await EpubReader.readBook(bytes);
      }

      if (epub.CoverImage != null) {
        final coverDir = await getCoverDir();
        final coverPath = path.join(coverDir, '${fileName}_cover.png');
        final coverFile = File(coverPath);
        await coverFile.writeAsBytes(epub.CoverImage!.getBytes());
        return coverPath;
      }
    } catch (e) {
      debugPrint('EPUB 封面提取失败: $filePath, 错误: $e');
    }
    return generateTextCover(fileName);
  }

  Future<String?> extractPdfCover(String filePath, String fileName) async {
    try {
      // 尝试用 flutter_pdfview 的底层方式提取第一页为图片（若平台支持）
      // 当前版本 flutter_pdfview 未暴露提取 API，先返回文字封面
      // 如需提取可用 pdf_image_renderer / pdfrx 等包扩展
      return generateTextCover(fileName);
    } catch (e) {
      return generateTextCover(fileName);
    }
  }

  Future<String?> extractArchiveCover(String filePath, String fileName) async {
    InputFileStream? inputStream;
    try {
      final file = File(filePath);
      inputStream = InputFileStream(file.path);
      final archive = ZipDecoder().decodeBuffer(inputStream);

      final imageFiles = <ArchiveFile>[];
      for (final entry in archive) {
        if (entry.isFile) {
          final name = entry.name.toLowerCase();
          if (name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.webp') ||
              name.endsWith('.gif') ||
              name.endsWith('.bmp')) {
            imageFiles.add(entry);
          }
        }
      }

      imageFiles.sort((a, b) => a.name.compareTo(b.name));

      if (imageFiles.isNotEmpty) {
        final first = imageFiles.first;
        final coverDir = await getCoverDir();
        final ext = path.extension(first.name);
        final coverPath = path.join(coverDir, '${fileName}_cover$ext');
        final coverFile = File(coverPath);
        await coverFile.writeAsBytes(first.content as List<int>);
        return coverPath;
      }
    } catch (e) {
      debugPrint('ZIP/CBZ 封面提取失败: $filePath, 错误: $e');
    } finally {
      try {
        inputStream?.closeSync();
      } catch (_) {
        // 忽略关闭错误，避免影响正常返回路径
      }
    }
    return generateTextCover(fileName);
  }

  static bool _isImageByMagicBytes(List<int> data) {
    if (data.length < 4) return false;
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
    if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
      return true;
    }
    if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) {
      return true;
    }
    if (data[0] == 0x42 && data[1] == 0x4D) return true;
    if (data.length >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return true;
    }
    return false;
  }

  Future<String?> extractRarCover(String filePath, String fileName) async {
    try {
      final imageBytes = await RarService.extractFirstImage(filePath);
      if (imageBytes != null) {
        final coverDir = await getCoverDir();
        final coverPath = path.join(coverDir, '${fileName}_cover.jpg');
        final coverFile = File(coverPath);
        await coverFile.writeAsBytes(imageBytes);
        return coverPath;
      }
    } catch (e) {
      debugPrint('RAR/CBR 封面提取失败: $filePath, 错误: $e');
    }
    return generateTextCover(fileName);
  }

  Future<String?> generateTextCover(String title, {String? author}) async {
    final coverDir = await getCoverDir();
    final coverPath = path.join(coverDir, '${(title + (author ?? '')).hashCode}_cover.png');

    if (await File(coverPath).exists()) {
      return coverPath;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(300, 400);

    // 背景渐变
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        NeutralColorsDark.divider,
        NeutralColorsDark.background,
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 文字
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.text = TextSpan(
      text: title.length > 12 ? '${title.substring(0, 12)}...' : title,
      style: const TextStyle(
        color: NeutralColorsDark.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout(maxWidth: size.width - 40);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );

    TextPainter? authorPainter;
    if (author != null && author.isNotEmpty) {
      authorPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      authorPainter.text = TextSpan(
        text: author,
        style: TextStyle(
          color: NeutralColorsDark.textSecondary,
          fontSize: 14,
        ),
      );
      authorPainter.layout(maxWidth: size.width - 40);
      authorPainter.paint(
        canvas,
        Offset(
          (size.width - authorPainter.width) / 2,
          (size.height + textPainter.height) / 2 + 10,
        ),
      );
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(coverPath);
        await file.writeAsBytes(buffer);
        return coverPath;
      }
    } finally {
      picture.dispose();
      image?.dispose();
      textPainter.dispose();
      authorPainter?.dispose();
    }

    return null;
  }

  Future<String?> generateVideoCover(String filePath, String fileName) async {
    try {
      final coverDir = await getCoverDir();
      final coverPath = path.join(coverDir, '${fileName.hashCode}_thumb.png');

      // 已存在则直接复用，避免重复调用 video_thumbnail（该插件有 FileInputStream 泄漏）
      if (await File(coverPath).exists()) {
        return coverPath;
      }

      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: filePath,
        thumbnailPath: coverPath,
        imageFormat: ImageFormat.PNG,
        maxWidth: 400,
        quality: 80,
      );
      if (thumbnailPath != null) {
        return thumbnailPath;
      }
    } catch (e) {
      debugPrint('视频缩略图提取失败: $filePath, 错误: $e');
    }
    // 降级为文字封面
    return generateTextCover(fileName);
  }

  Future<String?> generateMusicCover(String fileName) async {
    // 生成带音乐图标的默认封面
    final coverDir = await getCoverDir();
    final coverPath = path.join(coverDir, '${fileName.hashCode}_cover.png');

    if (await File(coverPath).exists()) {
      return coverPath;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(300, 400);

    // 背景渐变（紫色调，音乐感）
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF6B4EE6),
        const Color(0xFF4A3F9F),
      ],
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // 音乐符号
    final iconPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    iconPainter.text = const TextSpan(
      text: '♪',
      style: TextStyle(
        color: NeutralColorsDark.textSecondary,
        fontSize: 80,
      ),
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(
        (size.width - iconPainter.width) / 2,
        (size.height - iconPainter.height) / 2 - 30,
      ),
    );
    iconPainter.dispose();

    // 文字
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.text = TextSpan(
      text: fileName.length > 12 ? '${fileName.substring(0, 12)}...' : fileName,
      style: const TextStyle(
        color: NeutralColorsDark.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    );
    textPainter.layout(maxWidth: size.width - 40);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height) / 2 + 40,
      ),
    );
    textPainter.dispose();

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final file = File(coverPath);
        await file.writeAsBytes(buffer);
        return coverPath;
      }
    } finally {
      picture.dispose();
      image?.dispose();
    }

    return null;
  }

  Future<String?> saveCustomCover(Uint8List imageBytes, String fileName) async {
    final coverDir = await getCoverDir();
    final coverPath = path.join(coverDir, '${fileName}_custom_${DateTime.now().millisecondsSinceEpoch}.png');
    final file = File(coverPath);
    await file.writeAsBytes(imageBytes);
    return coverPath;
  }

  /// 下载网络图片作为封面
  Future<String?> downloadCover(String imageUrl, String fileName) async {
    try {
      final response = await Dio().get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200 && response.data != null) {
        final bytes = response.data as List<int>;
        final coverDir = await getCoverDir();
        final ext = path.extension(Uri.parse(imageUrl).path).isNotEmpty
            ? path.extension(Uri.parse(imageUrl).path)
            : '.jpg';
        final coverPath = path.join(coverDir, '${fileName}_tmdb$ext');
        final file = File(coverPath);
        await file.writeAsBytes(bytes);
        return coverPath;
      }
    } catch (e) {
      debugPrint('[CoverService] 下载封面失败: $imageUrl, 错误: $e');
    }
    return null;
  }
}
