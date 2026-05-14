import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/library_item.dart';

class FolderSettingsService {
  static final FolderSettingsService instance = FolderSettingsService._init();
  FolderSettingsService._init();

  static const String _prefix = 'scan_folders_';

  String _key(MediaType type) => '$_prefix${type.name}';
  String _blacklistKey(MediaType type) => '${_prefix}blacklist_${type.name}';

  Future<List<String>> getScanFolders(MediaType type) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key(type));
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> setScanFolders(MediaType type, List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(type), jsonEncode(folders));
  }

  Future<void> addScanFolder(MediaType type, String folder) async {
    final folders = await getScanFolders(type);
    if (!folders.contains(folder)) {
      folders.add(folder);
      await setScanFolders(type, folders);
    }
  }

  Future<void> removeScanFolder(MediaType type, String folder) async {
    final folders = await getScanFolders(type);
    folders.remove(folder);
    await setScanFolders(type, folders);
  }

  Future<void> clearScanFolders(MediaType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(type));
  }

  // ===================== 扫描黑名单 =====================

  Future<List<String>> getBlacklist(MediaType type) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_blacklistKey(type));
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> setBlacklist(MediaType type, List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_blacklistKey(type), jsonEncode(folders));
  }

  Future<void> addToBlacklist(MediaType type, String folder) async {
    final folders = await getBlacklist(type);
    final normalized = folder.toLowerCase();
    if (!folders.any((f) => f.toLowerCase() == normalized)) {
      folders.add(folder);
      await setBlacklist(type, folders);
    }
  }

  Future<void> removeFromBlacklist(MediaType type, String folder) async {
    final folders = await getBlacklist(type);
    folders.removeWhere((f) => f.toLowerCase() == folder.toLowerCase());
    await setBlacklist(type, folders);
  }

  /// 检查路径是否在黑名单中（支持子目录检测）
  Future<bool> isBlacklisted(MediaType type, String path) async {
    final blacklist = await getBlacklist(type);
    final lowerPath = path.toLowerCase();
    for (final folder in blacklist) {
      final lowerFolder = folder.toLowerCase();
      if (lowerPath == lowerFolder || lowerPath.startsWith('$lowerFolder\\') || lowerPath.startsWith('$lowerFolder/')) {
        return true;
      }
    }
    return false;
  }

  // ===================== 导入入口显示设置 =====================

  static const String _showImportEntryPrefix = 'show_import_entry_';

  String _showImportEntryKey(MediaType type) => '$_showImportEntryPrefix${type.name}';

  Future<bool> getShowImportEntry(MediaType type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showImportEntryKey(type)) ?? false;
  }

  Future<void> setShowImportEntry(MediaType type, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showImportEntryKey(type), value);
  }

  /// 获取所有类型已配置的扫描文件夹（去重）
  Future<List<String>> getAllScanFolders() async {
    final all = <String>{};
    for (final type in MediaType.values) {
      final folders = await getScanFolders(type);
      all.addAll(folders);
    }
    return all.toList();
  }
}
