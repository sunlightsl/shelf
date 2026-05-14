import 'package:shared_preferences/shared_preferences.dart';

enum EqPreset { off, pop, rock, classical, jazz, electronic, custom }

enum BackgroundMode { extreme, standard, minimal }

class MusicPlayerSettings {
  static const String _keyEqEnabled = 'music_eq_enabled';
  static const String _keyEqPreset = 'music_eq_preset';
  static const String _keyEqGains = 'music_eq_gains';
  static const String _keyVinylMode = 'player_vinyl_mode';
  static const String _keyShowVinylCenterDot = 'player_vinyl_center_dot';

  static const List<double> _defaultEqGains = [0, 0, 0, 0, 0];

  static const List<String> _eqBandLabels = ['60Hz', '250Hz', '1kHz', '4kHz', '12kHz'];
  static const List<double> _eqBandCenters = [60, 250, 1000, 4000, 12000];

  static List<String> get eqBandLabels => List.unmodifiable(_eqBandLabels);
  static List<double> get eqBandCenters => List.unmodifiable(_eqBandCenters);

  static Future<bool> getEqEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEqEnabled) ?? false;
  }

  static Future<void> setEqEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEqEnabled, value);
  }

  static Future<EqPreset> getEqPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyEqPreset);
    if (index == null || index < 0 || index >= EqPreset.values.length) {
      return EqPreset.off;
    }
    return EqPreset.values[index];
  }

  static Future<void> setEqPreset(EqPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyEqPreset, preset.index);
  }

  static Future<List<double>> getEqGains() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyEqGains);
    if (str == null || str.isEmpty) return List.from(_defaultEqGains);
    try {
      return str.split(',').map((s) => double.tryParse(s) ?? 0.0).toList();
    } catch (_) {
      return List.from(_defaultEqGains);
    }
  }

  static Future<void> setEqGains(List<double> gains) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEqGains, gains.map((g) => g.toStringAsFixed(1)).join(','));
  }

  static List<double> getPresetGains(EqPreset preset) {
    switch (preset) {
      case EqPreset.pop:
        return [1.5, 2.0, 3.5, 2.0, 1.0];
      case EqPreset.rock:
        return [3.5, 2.5, -1.0, 2.0, 3.5];
      case EqPreset.classical:
        return [2.0, 1.5, 0.5, 2.5, 2.0];
      case EqPreset.jazz:
        return [2.0, 1.0, 2.5, 1.5, 3.0];
      case EqPreset.electronic:
        return [4.0, 1.0, 0.0, 2.5, 4.5];
      case EqPreset.custom:
        return List.from(_defaultEqGains);
      case EqPreset.off:
        return [0, 0, 0, 0, 0];
    }
  }

  static Future<bool> getVinylMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVinylMode) ?? false;
  }

  static Future<void> setVinylMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVinylMode, value);
  }

  static Future<bool> getShowVinylCenterDot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowVinylCenterDot) ?? true;
  }

  static Future<void> setShowVinylCenterDot(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowVinylCenterDot, value);
  }

  static const String _keyBgMode = 'music_bg_mode';

  static Future<BackgroundMode> getBackgroundMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_keyBgMode);
    if (index == null || index < 0 || index >= BackgroundMode.values.length) {
      return BackgroundMode.extreme;
    }
    return BackgroundMode.values[index];
  }

  static Future<void> setBackgroundMode(BackgroundMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBgMode, mode.index);
  }

  static String backgroundModeLabel(BackgroundMode mode) {
    return switch (mode) {
      BackgroundMode.extreme => '极致',
      BackgroundMode.standard => '标准',
      BackgroundMode.minimal => '简约',
    };
  }

  static String presetLabel(EqPreset preset) {
    switch (preset) {
      case EqPreset.off:
        return '关闭';
      case EqPreset.pop:
        return '流行';
      case EqPreset.rock:
        return '摇滚';
      case EqPreset.classical:
        return '古典';
      case EqPreset.jazz:
        return '爵士';
      case EqPreset.electronic:
        return '电子';
      case EqPreset.custom:
        return '自定义';
    }
  }
}
