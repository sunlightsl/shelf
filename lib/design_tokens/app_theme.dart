import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 根据 [ThemeConfig] 与 [Brightness] 构建完整的 [ThemeData]
///
/// 后续增加主题时，只需要向 [ThemePresets] 添加新的 [ThemeConfig]，
/// 调用处无需任何改动。
ThemeData buildAppTheme({
  required ThemeConfig config,
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: config.primary,
    onPrimary: _contrastColor(config.primary),
    primaryContainer: config.light,
    onPrimaryContainer: _contrastColor(config.light),
    secondary: config.dark,
    onSecondary: _contrastColor(config.dark),
    secondaryContainer: config.subtleBg,
    onSecondaryContainer: config.primary,
    surface: neutral.surface,
    onSurface: neutral.textPrimary,
    surfaceContainerHighest: neutral.surfaceElevated,
    error: FunctionalColors.error,
    onError: Colors.white,
    outline: neutral.divider,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: neutral.background,
    dividerColor: neutral.divider,
    // --- Typography ---
    textTheme: TextTheme(
      displayLarge: AppTypography.display.copyWith(color: neutral.textPrimary),
      displayMedium: AppTypography.headline.copyWith(color: neutral.textPrimary),
      headlineMedium: AppTypography.title.copyWith(color: neutral.textPrimary),
      bodyLarge: AppTypography.body.copyWith(color: neutral.textPrimary),
      bodyMedium: AppTypography.body.copyWith(color: neutral.textSecondary),
      bodySmall: AppTypography.caption.copyWith(color: neutral.textSecondary),
      labelSmall: AppTypography.overline.copyWith(color: neutral.textTertiary),
    ),
    // --- AppBar ---
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: isDark ? neutral.surface : neutral.background,
      foregroundColor: neutral.textPrimary,
      elevation: 0,
      titleTextStyle: AppTypography.title.copyWith(color: neutral.textPrimary),
    ),
    // --- Card ---
    cardTheme: CardThemeData(
      color: neutral.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
    ),
    // --- BottomSheet ---
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: neutral.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
    ),
    // --- Dialog ---
    dialogTheme: DialogThemeData(
      backgroundColor: neutral.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
    ),
    // --- ListTile ---
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      iconColor: neutral.textSecondary,
      textColor: neutral.textPrimary,
    ),
    // --- Slider ---
    sliderTheme: SliderThemeData(
      activeTrackColor: config.primary,
      inactiveTrackColor: config.subtleBg,
      thumbColor: config.primary,
      overlayColor: config.primary.withOpacity(0.12),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    // --- Switch ---
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return config.primary;
        return neutral.textTertiary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return config.subtleBg;
        return neutral.divider;
      }),
    ),
    // --- FloatingActionButton ---
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: config.primary,
      foregroundColor: _contrastColor(config.primary),
      elevation: 2,
      highlightElevation: 4,
    ),
    // --- InputDecoration ---
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? neutral.surfaceElevated : neutral.background,
      contentPadding: const EdgeInsets.all(AppSpacing.s12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: config.primary, width: 1.5),
      ),
      hintStyle: AppTypography.body.copyWith(color: neutral.textTertiary),
    ),
    // --- Chip ---
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? neutral.surfaceElevated : neutral.background,
      selectedColor: config.subtleBg,
      labelStyle: AppTypography.caption.copyWith(color: neutral.textPrimary),
      secondaryLabelStyle: AppTypography.caption.copyWith(color: config.primary),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    ),
    // --- BottomNavigationBar ---
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: neutral.surface,
      selectedItemColor: config.primary,
      unselectedItemColor: neutral.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    // --- ElevatedButton ---
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: config.primary,
        foregroundColor: _contrastColor(config.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s24,
          vertical: AppSpacing.s12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        elevation: 0,
        textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    // --- TextButton ---
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: config.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        textStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    // --- IconButton ---
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: neutral.textSecondary,
      ),
    ),
    // --- TabBar ---
    tabBarTheme: TabBarThemeData(
      labelColor: config.primary,
      unselectedLabelColor: neutral.textSecondary,
      indicatorColor: config.primary,
      labelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: AppTypography.body,
    ),
    // --- PopupMenu ---
    popupMenuTheme: PopupMenuThemeData(
      color: neutral.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      elevation: 2,
    ),
    // --- Tooltip ---
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: neutral.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      textStyle: AppTypography.caption.copyWith(color: neutral.surface),
    ),
    // --- PageTransitions ---
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// 根据背景色亮度自动选择对比色（黑/白）
Color _contrastColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
