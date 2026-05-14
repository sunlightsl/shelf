import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_storage/cloud_account_manager.dart';
import 'cloud_storage/cloud_sync_service.dart';

/// 自动同步服务
///
/// 在应用生命周期切换时自动同步阅读进度：
/// - 前台恢复 → 从云端下载进度
/// - 进入后台 → 上传本地进度到云端
class AutoSyncService {
  static const _key = 'auto_sync_reading_progress';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// 应用恢复到前台时调用
  static Future<void> onResumed() async {
    if (!await isEnabled()) return;
    await _syncAllAccounts(download: true);
  }

  /// 应用进入后台时调用
  static Future<void> onPaused() async {
    if (!await isEnabled()) return;
    await _syncAllAccounts(download: false);
  }

  static Future<void> _syncAllAccounts({required bool download}) async {
    try {
      final accounts = await CloudAccountManager.instance.getAccounts();
      for (final account in accounts) {
        try {
          if (download) {
            await CloudSyncService.instance.downloadReadingProgress(account.id);
          } else {
            await CloudSyncService.instance.uploadReadingProgress(account.id);
          }
        } catch (e) {
          debugPrint('[AutoSync] 账户 ${account.displayName} 同步失败: $e');
        }
      }
    } catch (e) {
      debugPrint('[AutoSync] 获取账户列表失败: $e');
    }
  }
}
