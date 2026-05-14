import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 从 MOBI / AZW / AZW3 文件中提取图片
///
/// 基于 PalmDB 记录结构扫描，识别图片记录并提取。
class MobiService {
  /// 提取 MOBI 文件中的图片，返回临时文件路径列表
  static Future<List<String>> extractImages(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    if (bytes.length < 78) return [];

    // 读取 PalmDB 记录数量 (大端序，偏移 76)
    final recordCount = (bytes[76] << 8) | bytes[77];
    if (recordCount <= 0 || recordCount > 10000) return [];

    // 读取每个记录的偏移量 (从偏移 78 开始，每个记录 8 bytes，前 4 bytes 是偏移)
    final recordOffsets = <int>[];
    int headerOffset = 78;
    for (int i = 0; i < recordCount && headerOffset + 4 <= bytes.length; i++) {
      final offset = (bytes[headerOffset] << 24) |
          (bytes[headerOffset + 1] << 16) |
          (bytes[headerOffset + 2] << 8) |
          bytes[headerOffset + 3];
      recordOffsets.add(offset);
      headerOffset += 8;
    }

    // 提取图片数据
    final images = <Uint8List>[];
    for (int i = 0; i < recordOffsets.length; i++) {
      final start = recordOffsets[i];
      final end = (i + 1 < recordOffsets.length)
          ? recordOffsets[i + 1]
          : bytes.length;

      if (start >= bytes.length ||
          end > bytes.length ||
          end <= start ||
          end - start < 100) {
        continue;
      }

      final recordData = bytes.sublist(start, end);
      if (_isImageByMagicBytes(recordData)) {
        images.add(Uint8List.fromList(recordData));
      }
    }

    if (images.isEmpty) return [];

    // 保存到临时目录
    final tempDir = await getTemporaryDirectory();
    final baseName = path.basenameWithoutExtension(filePath);
    final targetDir = Directory(path.join(tempDir.path, 'mobi_extract', baseName));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final paths = <String>[];
    for (int i = 0; i < images.length; i++) {
      final ext = _guessExtension(images[i]);
      final targetPath = path.join(targetDir.path, 'page_${i.toString().padLeft(4, '0')}.$ext');
      await File(targetPath).writeAsBytes(images[i]);
      paths.add(targetPath);
    }

    return paths;
  }

  /// 清理指定 MOBI 文件提取出的临时图片
  static Future<void> clearExtractedImages(String filePath) async {
    final tempDir = await getTemporaryDirectory();
    final baseName = path.basenameWithoutExtension(filePath);
    final targetDir = Directory(path.join(tempDir.path, 'mobi_extract', baseName));
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
  }

  static bool _isImageByMagicBytes(List<int> data) {
    if (data.length < 4) return false;
    // JPEG: FF D8 FF
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
    // PNG: 89 50 4E 47
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true;
    }
    // GIF: 47 49 46 38
    if (data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x38) {
      return true;
    }
    // BMP: 42 4D
    if (data[0] == 0x42 && data[1] == 0x4D) return true;
    // WEBP: RIFF....WEBP
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

  static String _guessExtension(Uint8List data) {
    if (data.length < 4) return 'bin';
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return 'jpg';
    if (data[0] == 0x89 && data[1] == 0x50) return 'png';
    if (data[0] == 0x47 && data[1] == 0x49) return 'gif';
    if (data[0] == 0x42 && data[1] == 0x4D) return 'bmp';
    if (data.length >= 12 && data[8] == 0x57 && data[9] == 0x45) return 'webp';
    return 'bin';
  }
}
