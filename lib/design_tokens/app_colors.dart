import 'package:flutter/material.dart';

/// 主题配置 — 支持运行时切换主色调
///
/// 后续增加主题时，只需新增 ThemeConfig 常量，页面代码无需改动。
class ThemeConfig {
  final String id;
  final String name;
  final Color primary;
  final Color? primaryLight;
  final Color? primaryDark;

  const ThemeConfig({
    required this.id,
    required this.name,
    required this.primary,
    this.primaryLight,
    this.primaryDark,
  });

  // 自动派生 — 从主色 HSL 计算
  HSLColor get _hslPrimary => HSLColor.fromColor(primary);

  Color get hover => _hslPrimary.withLightness(
    (_hslPrimary.lightness + 0.08).clamp(0.0, 1.0),
  ).toColor();

  Color get pressed => _hslPrimary.withLightness(
    (_hslPrimary.lightness - 0.08).clamp(0.0, 1.0),
  ).toColor();

  Color get subtleBg => primary.withOpacity(0.1);

  Color get light => primaryLight ?? _hslPrimary.withLightness(
    (_hslPrimary.lightness + 0.15).clamp(0.0, 1.0),
  ).toColor();

  Color get dark => primaryDark ?? _hslPrimary.withLightness(
    (_hslPrimary.lightness - 0.15).clamp(0.0, 1.0),
  ).toColor();
}

/// 预设主题库
abstract class ThemePresets {
  static const amber = ThemeConfig(
    id: 'amber',
    name: '琥珀',
    primary: Color(0xFFD4A574),
    primaryLight: Color(0xFFE8C9A0),
    primaryDark: Color(0xFFB08650),
  );

  static const all = [amber];
  static ThemeConfig? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// 过渡常量：当前主品牌色
/// 在全面接入 Theme.of(context).colorScheme.primary 之前，硬编码位置使用此常量。
abstract class AppColors {
  static const primary = Color(0xFFD4A574);
}

/// 功能色 — 与主色调无关，全局固定
abstract class FunctionalColors {
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFF9500);
  static const error = Color(0xFFFF3B30);
  static const info = Color(0xFF5AC8FA);
}

/// 中性色板 — 亮色/暗色实例
class NeutralPalette {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;

  const NeutralPalette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
  });

  static const light = NeutralPalette(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1D1D1F),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFF8E8E93),
    divider: Color(0xFFE5E5EA),
  );

  static const dark = NeutralPalette(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceElevated: Color(0xFF2C2C2E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF98989F),
    textTertiary: Color(0xFF8E8E93),
    divider: Color(0xFF3A3A3C),
  );

  static NeutralPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

/// 亮色中性色（兼容用，后续逐步迁移到 NeutralPalette）
abstract class NeutralColorsLight {
  static const background = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1D1D1F);
  static const textSecondary = Color(0xFF6E6E73);
  static const textTertiary = Color(0xFF8E8E93);
  static const divider = Color(0xFFE5E5EA);
}

/// 暗色中性色（兼容用，后续逐步迁移到 NeutralPalette）
abstract class NeutralColorsDark {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF2C2C2E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF98989F);
  static const textTertiary = Color(0xFF8E8E93);
  static const divider = Color(0xFF3A3A3C);
}
