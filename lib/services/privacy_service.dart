import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 私密会话管理服务
///
/// 安全策略：纯系统认证（local_auth + 设备密码兜底），不自存任何密码。
/// isUnlocked 仅存内存，杀进程后自动重置。
/// isPrivacyModeEnabled / lockMode 持久化到 SharedPreferences。
class PrivacyService extends ChangeNotifier {
  static final PrivacyService instance = PrivacyService._internal();
  PrivacyService._internal();

  static const String _kPrivacyModeEnabled = 'privacy_mode_enabled';
  static const String _kLockMode = 'privacy_lock_mode';
  static const String _kShowPrivateSpaceInSettings = 'show_private_space_in_settings';

  bool _isUnlocked = false;
  bool _isPrivacyModeEnabled = false;
  int _lockMode = 1; // 0=屏幕关闭后, 1=离开应用5分钟后, 2=离开应用后立即锁定
  bool _showPrivateSpaceInSettings = false;
  DateTime? _lastBackgroundTime;
  Timer? _lockTimer;

  bool get isUnlocked => _isUnlocked;
  bool get isPrivacyModeEnabled => _isPrivacyModeEnabled;
  int get lockMode => _lockMode;
  bool get showPrivateSpaceInSettings => _showPrivateSpaceInSettings;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isUnlocked = false;
    _isPrivacyModeEnabled = prefs.getBool(_kPrivacyModeEnabled) ?? false;
    _lockMode = prefs.getInt(_kLockMode) ?? 1;
    _showPrivateSpaceInSettings = prefs.getBool(_kShowPrivateSpaceInSettings) ?? false;
    _lastBackgroundTime = null;
    _lockTimer?.cancel();
    notifyListeners();
  }

  Future<void> setPrivacyModeEnabled(bool value) async {
    if (_isPrivacyModeEnabled == value) return;
    _isPrivacyModeEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrivacyModeEnabled, value);
    notifyListeners();
  }

  Future<void> setLockMode(int mode) async {
    if (_lockMode == mode) return;
    _lockMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockMode, mode);
    notifyListeners();
  }

  Future<void> setShowPrivateSpaceInSettings(bool value) async {
    if (_showPrivateSpaceInSettings == value) return;
    _showPrivateSpaceInSettings = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowPrivateSpaceInSettings, value);
    notifyListeners();
  }

  /// 调起系统生物认证，失败自动降级到设备密码
  Future<bool> unlock() async {
    final localAuth = LocalAuthentication();
    try {
      final didAuthenticate = await localAuth.authenticate(
        localizedReason: '验证身份以查看私密内容',
        options: const AuthenticationOptions(
          useErrorDialogs: false,
          stickyAuth: true,
          sensitiveTransaction: true,
          biometricOnly: false,
        ),
      );
      if (didAuthenticate) {
        _isUnlocked = true;
        notifyListeners();
      }
      return didAuthenticate;
    } catch (e) {
      debugPrint('local_auth 异常: $e');
      return false;
    }
  }

  /// 手动/自动锁定
  void lock() {
    _isUnlocked = false;
    _lockTimer?.cancel();
    notifyListeners();
  }

  /// App 切后台
  void onBackground() {
    if (_lockMode == 2) {
      // 离开应用后立即锁定
      lock();
      return;
    }
    _lastBackgroundTime = DateTime.now();
    _lockTimer?.cancel();
    _lockTimer = Timer(const Duration(minutes: 5), () {
      if (!_isUnlocked) return;
      lock();
    });
  }

  /// App 切前台
  Future<void> onForeground() async {
    _lockTimer?.cancel();
    _lockTimer = null;
    if (_lastBackgroundTime != null) {
      final timeout = _lockMode == 0
          ? const Duration(seconds: 0)
          : const Duration(minutes: 5);
      if (DateTime.now().difference(_lastBackgroundTime!) > timeout) {
        lock();
      }
    }
    _lastBackgroundTime = null;
  }
}
