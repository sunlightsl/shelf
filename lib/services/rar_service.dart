import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'app_directories.dart';

class RarService {
  /// 从 RAR/CBR 文件中提取所有图片，返回文件路径列表（按需读取）
  static Future<List<String>> extractImages(String rarFilePath) async {
    final rarHash = rarFilePath.hashCode.toString();
    final extractDir = Directory(path.join(AppDirectories.rarCacheDir, rarHash));

    // 如果已缓存且包含图片，直接复用
    if (await extractDir.exists()) {
      final files = await extractDir.list(recursive: true).where((e) => e is File).cast<File>().toList();
      final imageFiles = files.where((f) {
        final ext = path.extension(f.path).toLowerCase();
        return const ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext);
      }).toList();
      imageFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
      if (imageFiles.isNotEmpty) {
        return imageFiles.map((f) => f.path).toList();
      }
    }

    await extractDir.create(recursive: true);
    await _extractRar(rarFilePath, extractDir.path);

    final files = await extractDir.list(recursive: true).where((e) => e is File).cast<File>().toList();
    final imageFiles = files.where((f) {
      final ext = path.extension(f.path).toLowerCase();
      return const ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext);
    }).toList();
    imageFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    return imageFiles.map((f) => f.path).toList();
  }

  /// 从 RAR/CBR 中提取第一张图片作为封面
  static Future<Uint8List?> extractFirstImage(String rarFilePath) async {
    final extractDir = Directory(
      path.join(AppDirectories.rarCacheDir, 'rar_cover_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await extractDir.create(recursive: true);

    try {
      await _extractRar(rarFilePath, extractDir.path);

      final files =
          await extractDir.list(recursive: true).where((e) => e is File).cast<File>().toList();

      final imageFiles =
          files.where((f) {
            final ext = path.extension(f.path).toLowerCase();
            return const ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext);
          }).toList();

      imageFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

      if (imageFiles.isNotEmpty) {
        return await imageFiles.first.readAsBytes();
      }
      return null;
    } finally {
      try {
        if (await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('RAR 临时目录清理失败: $e');
      }
    }
  }

  static Future<void> _extractRar(String rarPath, String destPath) async {
    // Windows
    if (Platform.isWindows) {
      final results = await Future.wait([
        _trySystemCommand('7z', ['x', rarPath, '-o$destPath', '-y']),
        _trySystemCommand('unrar', ['x', rarPath, destPath]),
      ]);
      if (results.any((r) => r)) return;
    }
    // macOS / Linux
    else if (Platform.isMacOS || Platform.isLinux) {
      final results = await Future.wait([
        _trySystemCommand('unrar', ['x', rarPath, destPath]),
        _trySystemCommand('unar', [rarPath, '-o', destPath]),
        _trySystemCommand('7z', ['x', rarPath, '-o$destPath', '-y']),
      ]);
      if (results.any((r) => r)) return;
    }
    // Android / iOS：尝试系统命令（部分定制 ROM / 越狱设备可能有）
    else if (Platform.isAndroid || Platform.isIOS) {
      final results = await Future.wait([
        _trySystemCommand('unrar', ['x', rarPath, destPath]),
        _trySystemCommand('7z', ['x', rarPath, '-o$destPath', '-y']),
      ]);
      if (results.any((r) => r)) return;
    }

    throw UnsupportedError(
      'RAR/CBR 解压失败。\n\n'
      '建议：将 .rar/.cbr 文件重命名为 .zip/.cbz 后重新导入，\n'
      '或在电脑上先用 7-Zip / WinRAR 解压后打包成 ZIP 格式。',
    );
  }

  static const Set<String> _allowedCommands = {'7z', 'unrar', 'unar'};

  static Future<bool> _trySystemCommand(String command, List<String> args) async {
    if (!_allowedCommands.contains(command)) {
      debugPrint('RAR: 命令 "$command" 不在白名单中，拒绝执行');
      return false;
    }
    try {
      final result = await Process.run(command, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
