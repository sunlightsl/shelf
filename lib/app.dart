import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'design_tokens/app_colors.dart';
import 'design_tokens/app_theme.dart';
import 'providers/comic_series_provider.dart';
import 'providers/library_provider.dart';
import 'screens/home_screen.dart';
import 'services/reading_settings_service.dart';
import 'services/privacy_service.dart';
import 'services/filesystem_scanner.dart';
import 'services/auto_sync_service.dart';
import 'services/tmdb_settings_service.dart';
import 'services/offline_cache_service.dart';
import 'models/library_item.dart';

/// 根据当前主题 ID 获取 ThemeConfig
ThemeConfig _currentThemeConfig() {
  final themeId = ReadingSettingsService.instance.settings.themeId;
  return ThemePresets.byId(themeId) ?? ThemePresets.amber;
}

class LocalLibraryApp extends StatefulWidget {
  const LocalLibraryApp({super.key});

  @override
  State<LocalLibraryApp> createState() => _LocalLibraryAppState();
}

class _LocalLibraryAppState extends State<LocalLibraryApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ReadingSettingsService.instance.load();
    PrivacyService.instance.init();
    TMDBSettingsService.init();
    OfflineCacheService.instance.init();
    _runStartupScan();
  }

  /// 启动后延迟扫描文件系统，自动发现新增文件
  void _runStartupScan() async {
    await Future.delayed(const Duration(seconds: 3));
    final scanner = FilesystemScanner();
    for (final type in [MediaType.novel, MediaType.video, MediaType.music]) {
      try {
        final result = await scanner.incrementalScan(type);
        if (result.addedPaths.isNotEmpty) {
          await scanner.autoImportAdded(result, type);
        }
      } catch (e) {
        debugPrint('启动扫描失败 ($type): $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      PrivacyService.instance.onBackground();
      AutoSyncService.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      PrivacyService.instance.onForeground();
      AutoSyncService.onResumed();
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.system) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryProvider()..loadLibrary()),
        ChangeNotifierProvider(create: (_) => ComicSeriesProvider()..loadSeries()),
      ],
      child: ValueListenableBuilder<String>(
        valueListenable: ReadingSettingsService.instance.themeIdNotifier,
        builder: (context, _, __) {
          return ValueListenableBuilder<AppThemeMode>(
            valueListenable: ReadingSettingsService.instance.themeModeNotifier,
            builder: (context, _, __) {
              final isDark = ReadingSettingsService.instance.isDarkMode;
              final themeConfig = _currentThemeConfig();
              return MaterialApp(
                title: '拾光集',
                debugShowCheckedModeBanner: false,
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                theme: buildAppTheme(
                  config: themeConfig,
                  brightness: Brightness.light,
                ),
                darkTheme: buildAppTheme(
                  config: themeConfig,
                  brightness: Brightness.dark,
                ),
                home: AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDark
                  ? SystemUiOverlayStyle.dark.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarIconBrightness: Brightness.light,
                      statusBarIconBrightness: Brightness.light,
                    )
                  : SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarIconBrightness: Brightness.dark,
                      statusBarIconBrightness: Brightness.dark,
                    ),
              child: const HomeScreen(),
            ),
          );
        },
      );
    },
  ),
);
  }

}
