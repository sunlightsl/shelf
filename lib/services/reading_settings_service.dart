import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingTheme {
  light,
  dark,
  sepia,
  eyeCare,
}

enum AppThemeMode {
  light,
  dark,
  system,
}

enum OrientationLock {
  auto,
  portrait,
  landscape,
}

enum TextEncoding {
  auto,
  utf8,
  gbk,
  gb2312,
  big5,
  latin1,
}

enum ChineseConversion {
  none,
  t2s, // 繁体转简体
  s2t, // 简体转繁体
}

class ReadingSettings {
  // 正文样式
  double fontSize;
  double lineHeight;
  double paragraphSpacing;
  double horizontalPadding;
  double letterSpacing;
  FontWeight fontWeight;
  ReadingTheme theme;
  double brightness;
  bool isHorizontal;
  String fontFamily;
  double firstLineIndent;

  // 标题样式
  double titleFontSize;
  double titleTopPadding;
  double titleBottomPadding;
  String titleFontFamily;

  // 屏幕方向
  OrientationLock orientationLock;

  // 全局主题模式
  AppThemeMode appThemeMode;

  // 主题色 ID
  String themeId;

  // TXT 文件编码
  TextEncoding textEncoding;

  // 启用的分章规则 ID 列表（null 表示全部启用）
  List<String>? enabledChapterRules;

  // 繁简转换
  ChineseConversion chineseConversion;

  ReadingSettings({
    this.fontSize = 18,
    this.lineHeight = 1.8,
    this.paragraphSpacing = 0,
    this.horizontalPadding = 24,
    this.letterSpacing = 0.3,
    this.fontWeight = FontWeight.w400,
    this.theme = ReadingTheme.light,
    this.brightness = 1.0,
    this.isHorizontal = false,
    this.fontFamily = '',
    this.firstLineIndent = 2.0,
    this.titleFontSize = 22,
    this.titleTopPadding = 32,
    this.titleBottomPadding = 24,
    this.titleFontFamily = '',
    this.orientationLock = OrientationLock.auto,
    this.appThemeMode = AppThemeMode.system,
    this.themeId = 'amber',
    this.textEncoding = TextEncoding.auto,
    this.enabledChapterRules,
    this.chineseConversion = ChineseConversion.none,
  });

  Map<String, dynamic> toMap() {
    return {
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'paragraphSpacing': paragraphSpacing,
      'horizontalPadding': horizontalPadding,
      'letterSpacing': letterSpacing,
      'fontWeight': fontWeight.index,
      'theme': theme.index,
      'brightness': brightness,
      'isHorizontal': isHorizontal,
      'fontFamily': fontFamily,
      'firstLineIndent': firstLineIndent,
      'titleFontSize': titleFontSize,
      'titleTopPadding': titleTopPadding,
      'titleBottomPadding': titleBottomPadding,
      'titleFontFamily': titleFontFamily,
      'orientationLock': orientationLock.index,
      'appThemeMode': appThemeMode.index,
      'themeId': themeId,
      'textEncoding': textEncoding.index,
      'enabledChapterRules': enabledChapterRules,
      'chineseConversion': chineseConversion.index,
    };
  }

  factory ReadingSettings.fromMap(Map<String, dynamic> map) {
    final orientationIndex = ((map['orientationLock'] as int?) ?? 0)
        .clamp(0, OrientationLock.values.length - 1)
        .toInt();
    final themeModeIndex = ((map['appThemeMode'] as int?) ?? 2)
        .clamp(0, AppThemeMode.values.length - 1)
        .toInt();
    final encodingIndex = ((map['textEncoding'] as int?) ?? 0)
        .clamp(0, TextEncoding.values.length - 1)
        .toInt();
    final conversionIndex = ((map['chineseConversion'] as int?) ?? 0)
        .clamp(0, ChineseConversion.values.length - 1)
        .toInt();
    return ReadingSettings(
      fontSize: map['fontSize'] as double? ?? 18,
      lineHeight: map['lineHeight'] as double? ?? 1.8,
      paragraphSpacing: map['paragraphSpacing'] as double? ?? 0,
      horizontalPadding: map['horizontalPadding'] as double? ?? 24,
      letterSpacing: map['letterSpacing'] as double? ?? 0.3,
      fontWeight: FontWeight.values[(map['fontWeight'] as int? ?? 3).clamp(0, FontWeight.values.length - 1)],
      theme: ReadingTheme.values[map['theme'] as int? ?? 0],
      brightness: map['brightness'] as double? ?? 1.0,
      isHorizontal: map['isHorizontal'] as bool? ?? false,
      fontFamily: map['fontFamily'] as String? ?? '',
      firstLineIndent: map['firstLineIndent'] as double? ?? 2.0,
      titleFontSize: map['titleFontSize'] as double? ?? 22,
      titleTopPadding: map['titleTopPadding'] as double? ?? 32,
      titleBottomPadding: map['titleBottomPadding'] as double? ?? 24,
      titleFontFamily: map['titleFontFamily'] as String? ?? '',
      orientationLock: OrientationLock.values[orientationIndex],
      appThemeMode: AppThemeMode.values[themeModeIndex],
      themeId: map['themeId'] as String? ?? 'amber',
      textEncoding: TextEncoding.values[encodingIndex],
      enabledChapterRules: (map['enabledChapterRules'] as List?)?.cast<String>(),
      chineseConversion: ChineseConversion.values[conversionIndex],
    );
  }

  ReadingSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    double? letterSpacing,
    FontWeight? fontWeight,
    ReadingTheme? theme,
    double? brightness,
    bool? isHorizontal,
    String? fontFamily,
    double? firstLineIndent,
    double? titleFontSize,
    double? titleTopPadding,
    double? titleBottomPadding,
    String? titleFontFamily,
    OrientationLock? orientationLock,
    AppThemeMode? appThemeMode,
    String? themeId,
    TextEncoding? textEncoding,
    List<String>? enabledChapterRules,
    ChineseConversion? chineseConversion,
  }) {
    return ReadingSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      fontWeight: fontWeight ?? this.fontWeight,
      theme: theme ?? this.theme,
      brightness: brightness ?? this.brightness,
      isHorizontal: isHorizontal ?? this.isHorizontal,
      fontFamily: fontFamily ?? this.fontFamily,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      titleTopPadding: titleTopPadding ?? this.titleTopPadding,
      titleBottomPadding: titleBottomPadding ?? this.titleBottomPadding,
      titleFontFamily: titleFontFamily ?? this.titleFontFamily,
      orientationLock: orientationLock ?? this.orientationLock,
      appThemeMode: appThemeMode ?? this.appThemeMode,
      themeId: themeId ?? this.themeId,
      textEncoding: textEncoding ?? this.textEncoding,
      enabledChapterRules: enabledChapterRules ?? this.enabledChapterRules,
      chineseConversion: chineseConversion ?? this.chineseConversion,
    );
  }
}

class ReadingSettingsService {
  static final ReadingSettingsService instance = ReadingSettingsService._init();
  ReadingSettingsService._init();

  ReadingSettings _settings = ReadingSettings();
  ReadingSettings get settings => _settings;

  final ValueNotifier<AppThemeMode> themeModeNotifier = ValueNotifier(AppThemeMode.system);
  final ValueNotifier<String> themeIdNotifier = ValueNotifier('amber');

  ReadingTheme _safeThemeFromIndex(int? index) {
    if (index == null || index < 0 || index >= ReadingTheme.values.length) {
      return ReadingTheme.light;
    }
    return ReadingTheme.values[index];
  }

  AppThemeMode _safeThemeModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= AppThemeMode.values.length) {
      return AppThemeMode.system;
    }
    return AppThemeMode.values[index];
  }

  bool get isDarkMode {
    switch (_settings.appThemeMode) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final orientationIndex = (prefs.getInt('rs_orientationLock') ?? 0)
        .clamp(0, OrientationLock.values.length - 1)
        .toInt();
    final encodingIndex = (prefs.getInt('rs_textEncoding') ?? 0)
        .clamp(0, TextEncoding.values.length - 1)
        .toInt();
    final conversionIndex = (prefs.getInt('rs_chinese_conversion') ?? 0)
        .clamp(0, ChineseConversion.values.length - 1)
        .toInt();
    _settings = ReadingSettings(
      fontSize: prefs.getDouble('rs_fontSize') ?? 18,
      lineHeight: prefs.getDouble('rs_lineHeight') ?? 1.8,
      paragraphSpacing: prefs.getDouble('rs_paragraphSpacing') ?? 0,
      horizontalPadding: prefs.getDouble('rs_horizontalPadding') ?? 24,
      letterSpacing: prefs.getDouble('rs_letterSpacing') ?? 0.3,
      fontWeight: FontWeight.values[(prefs.getInt('rs_fontWeight') ?? 3).clamp(0, FontWeight.values.length - 1)],
      theme: _safeThemeFromIndex(prefs.getInt('rs_theme')),
      brightness: prefs.getDouble('rs_brightness') ?? 1.0,
      isHorizontal: prefs.getBool('rs_isHorizontal') ?? false,
      fontFamily: prefs.getString('rs_fontFamily') ?? '',
      firstLineIndent: prefs.getDouble('rs_firstLineIndent') ?? 2.0,
      titleFontSize: prefs.getDouble('rs_titleFontSize') ?? 22,
      titleTopPadding: prefs.getDouble('rs_titleTopPadding') ?? 32,
      titleBottomPadding: prefs.getDouble('rs_titleBottomPadding') ?? 24,
      titleFontFamily: prefs.getString('rs_titleFontFamily') ?? '',
      orientationLock: OrientationLock.values[orientationIndex],
      appThemeMode: _safeThemeModeFromIndex(prefs.getInt('rs_app_theme_mode')),
      themeId: prefs.getString('rs_theme_id') ?? 'amber',
      textEncoding: TextEncoding.values[encodingIndex],
      enabledChapterRules: prefs.getStringList('rs_enabled_chapter_rules'),
      chineseConversion: ChineseConversion.values[conversionIndex],
    );
    themeModeNotifier.value = _settings.appThemeMode;
    themeIdNotifier.value = _settings.themeId;
  }

  Future<void> save(ReadingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('rs_fontSize', settings.fontSize);
    await prefs.setDouble('rs_lineHeight', settings.lineHeight);
    await prefs.setDouble('rs_paragraphSpacing', settings.paragraphSpacing);
    await prefs.setDouble('rs_horizontalPadding', settings.horizontalPadding);
    await prefs.setDouble('rs_letterSpacing', settings.letterSpacing);
    await prefs.setInt('rs_fontWeight', settings.fontWeight.index);
    await prefs.setInt('rs_theme', settings.theme.index);
    await prefs.setDouble('rs_brightness', settings.brightness);
    await prefs.setBool('rs_isHorizontal', settings.isHorizontal);
    await prefs.setString('rs_fontFamily', settings.fontFamily);
    await prefs.setDouble('rs_firstLineIndent', settings.firstLineIndent);
    await prefs.setDouble('rs_titleFontSize', settings.titleFontSize);
    await prefs.setDouble('rs_titleTopPadding', settings.titleTopPadding);
    await prefs.setDouble('rs_titleBottomPadding', settings.titleBottomPadding);
    await prefs.setString('rs_titleFontFamily', settings.titleFontFamily);
    await prefs.setInt('rs_orientationLock', settings.orientationLock.index);
    await prefs.setInt('rs_app_theme_mode', settings.appThemeMode.index);
    await prefs.setString('rs_theme_id', settings.themeId);
    await prefs.setInt('rs_textEncoding', settings.textEncoding.index);
    await prefs.setInt('rs_chinese_conversion', settings.chineseConversion.index);
    if (settings.enabledChapterRules != null) {
      await prefs.setStringList('rs_enabled_chapter_rules', settings.enabledChapterRules!);
    } else {
      await prefs.remove('rs_enabled_chapter_rules');
    }
    _settings = settings;
    themeModeNotifier.value = settings.appThemeMode;
    themeIdNotifier.value = settings.themeId;
  }

  Future<void> setThemeId(String themeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rs_theme_id', themeId);
    _settings = _settings.copyWith(themeId: themeId);
    themeIdNotifier.value = themeId;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('rs_app_theme_mode', mode.index);
    _settings = _settings.copyWith(appThemeMode: mode);
    themeModeNotifier.value = mode;
  }

  Color getBackgroundColor(ReadingTheme theme) {
    switch (theme) {
      case ReadingTheme.light:
        return const Color(0xFFF5F5F7);
      case ReadingTheme.dark:
        return const Color(0xFF1C1C1E);
      case ReadingTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReadingTheme.eyeCare:
        return const Color(0xFFE8F5E9);
    }
  }

  Color getTextColor(ReadingTheme theme) {
    switch (theme) {
      case ReadingTheme.light:
        return const Color(0xFF1D1D1F);
      case ReadingTheme.dark:
        return const Color(0xFFE5E5EA);
      case ReadingTheme.sepia:
        return const Color(0xFF5B4636);
      case ReadingTheme.eyeCare:
        return const Color(0xFF2E4A2E);
    }
  }
}
