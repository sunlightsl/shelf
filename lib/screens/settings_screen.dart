import 'package:local_library/design_tokens/app_shadows.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../providers/comic_series_provider.dart';
import '../providers/library_provider.dart';
import '../services/backup_service.dart';
import '../services/reading_settings_service.dart';
import '../services/music_player_service.dart';
import '../services/music_scan_service.dart';
import '../services/filesystem_scanner.dart';
import '../services/app_directories.dart';
import '../services/auto_sync_service.dart';
import '../services/offline_cache_service.dart';
import '../design_tokens/app_colors.dart';
import '../design_tokens/app_theme.dart';
import 'import_screen.dart';
import 'media/music/music_library_view.dart';
import 'media_library_screen.dart';
import 'media_type_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'private_space_screen.dart';
import 'recycle_bin_screen.dart';
import 'cloud_sync_settings_screen.dart';
import '../services/privacy_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _BackupInfo {
  final File file;
  final String size;
  final String date;
  _BackupInfo({required this.file, required this.size, required this.date});
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackupService _backupService = BackupService.instance;
  List<_BackupInfo> _backups = [];
  bool _isCreatingBackup = false;
  bool _isRestoring = false;
  bool _autoSyncEnabled = false;
  bool _isScanning = false;
  int _cacheSizeBytes = 0;
  int _cacheLimitMB = 0;
  int _cacheCount = 0;
  bool _isLoadingCache = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
    PrivacyService.instance.addListener(_onPrivacyChanged);
  }

  Future<void> _loadAutoSync() async {
    final enabled = await AutoSyncService.isEnabled();
    if (mounted) setState(() => _autoSyncEnabled = enabled);
  }

  Future<void> _loadCacheInfo() async {
    setState(() => _isLoadingCache = true);
    final size = await OfflineCacheService.instance.getTotalSizeBytes();
    final limit = await OfflineCacheService.instance.getCacheLimitMB();
    final count = await OfflineCacheService.instance.getCount();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = size;
        _cacheLimitMB = limit;
        _cacheCount = count;
        _isLoadingCache = false;
      });
    }
  }

  Future<void> _toggleAutoSync(bool value) async {
    await AutoSyncService.setEnabled(value);
    setState(() => _autoSyncEnabled = value);
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyChanged);
    super.dispose();
  }

  void _onPrivacyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBackups() async {
    final files = await _backupService.getBackupFiles();
    if (!mounted) return;
    final infos = await Future.wait(files.map((file) async {
      final stat = await file.stat();
      return _BackupInfo(
        file: file,
        size: _formatFileSize(stat.size),
        date: DateFormat('yyyy-MM-dd HH:mm').format(stat.modified),
      );
    }));
    setState(() => _backups = infos);
  }

  Future<void> _showCacheLimitPicker() async {
    final options = [0, 1024, 2048, 5120, 10240];
    final labels = ['无限制', '1 GB', '2 GB', '5 GB', '10 GB'];
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择缓存上限'),
        actions: [
          for (int i = 0; i < options.length; i++)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(context);
                await OfflineCacheService.instance.setCacheLimitMB(options[i]);
                await _loadCacheInfo();
              },
              child: Text(
                labels[i],
                style: TextStyle(
                  fontWeight: _cacheLimitMB == options[i] ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _clearCache() async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认清理缓存'),
        content: Text('将删除 ${_cacheCount} 个云端下载的缓存文件（共 ${_formatFileSizeMB(_cacheSizeBytes)}），此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoadingCache = true);
      final freed = await OfflineCacheService.instance.clearAllCache();
      await _loadCacheInfo();
      if (mounted) {
        _showSuccess('已释放 ${_formatFileSizeMB(freed)}');
        context.read<LibraryProvider>().loadLibrary();
        context.read<ComicSeriesProvider>().loadSeries();
        MusicScanService.instance.syncFromLibrary();
      }
    }
  }

  String _formatFileSizeMB(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 24),
          child: Text(
            '设置',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(title: '外观'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    ValueListenableBuilder<AppThemeMode>(
                      valueListenable: ReadingSettingsService.instance.themeModeNotifier,
                      builder: (context, mode, _) => _SettingsRowTap(
                        title: '主题',
                        value: _themeModeLabel(mode),
                        onTap: _showThemePicker,
                      ),
                    ),
                    const _SettingsDivider(indent: 16),
                    ValueListenableBuilder<String>(
                      valueListenable: ReadingSettingsService.instance.themeIdNotifier,
                      builder: (context, themeId, _) => _SettingsRowTap(
                        title: '个性化',
                        value: _themeNameLabel(themeId),
                        valuePrefix: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: ThemePresets.byId(themeId)?.primary ?? AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onTap: _showThemeColorPicker,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '资源管理'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsButton(
                      icon: CupertinoIcons.folder_fill,
                      title: '媒体库',
                      subtitle: '浏览文件、查看各类型占用',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const MediaLibraryScreen(),
                          ),
                        );
                      },
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.square_arrow_down,
                      title: '导入资源',
                      subtitle: '导入小说、漫画、视频、音乐',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const ImportScreen(),
                          ),
                        );
                      },
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.trash,
                      title: '回收站',
                      subtitle: '查看已删除的资源，可恢复或彻底删除',
                      color: FunctionalColors.error,
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const RecycleBinScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '存储维护'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsButton(
                      icon: CupertinoIcons.arrow_2_circlepath,
                      title: '扫描并导入新文件',
                      subtitle: '扫描各类型文件夹，自动导入新增文件',
                      color: AppColors.primary,
                      isLoading: _isScanning,
                      onTap: () => _scanAndImport(),
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: '清理缺失文件',
                      subtitle: '检测已删除的本地文件并移入回收站',
                      color: FunctionalColors.error,
                      onTap: _cleanupMissingFiles,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '分类设置'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsButton(
                      icon: CupertinoIcons.book,
                      title: '小说设置',
                      subtitle: '设置小说扫描文件夹',
                      color: AppColors.primary,
                      onTap: () => _openTypeSettings(MediaType.novel),
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.photo,
                      title: '漫画设置',
                      subtitle: '设置漫画扫描文件夹',
                      color: AppColors.primary,
                      onTap: () => _openTypeSettings(MediaType.comic),
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.film,
                      title: '视频设置',
                      subtitle: '设置视频扫描文件夹',
                      color: AppColors.primary,
                      onTap: () => _openTypeSettings(MediaType.video),
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.music_note,
                      title: '音乐设置',
                      subtitle: '设置音乐扫描文件夹',
                      color: AppColors.primary,
                      onTap: () => _openTypeSettings(MediaType.music),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '私密安全'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    if (PrivacyService.instance.showPrivateSpaceInSettings)
                      _SettingsButton(
                        icon: CupertinoIcons.lock_shield_fill,
                        title: '私密空间',
                        subtitle: '查看已标记为私密的资源',
                        color: FunctionalColors.error,
                        onTap: () async {
                          if (PrivacyService.instance.isUnlocked) {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => const PrivateSpaceScreen(),
                              ),
                            );
                          } else {
                            final success = await PrivacyService.instance.unlock();
                            if (success && mounted) {
                              Navigator.of(context).push(
                                CupertinoPageRoute(
                                  builder: (_) => const PrivateSpaceScreen(),
                                ),
                              );
                            } else if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('认证失败，无法进入私密空间'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    if (PrivacyService.instance.showPrivateSpaceInSettings)
                      const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.lock_fill,
                      title: '私密安全',
                      subtitle: '管理私密模式、认证设置',
                      color: AppColors.primary,
                      onTap: () async {
                        if (PrivacyService.instance.isUnlocked) {
                          _navigateToPrivacySettings();
                        } else {
                          final success = await PrivacyService.instance.unlock();
                          if (success && mounted) {
                            _navigateToPrivacySettings();
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('认证失败，无法进入私密安全'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '云同步'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsButton(
                      icon: CupertinoIcons.cloud,
                      title: '云同步',
                      subtitle: '云存储账户、自动同步、离线缓存',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => const CloudSyncSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle(title: '数据管理'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsButton(
                      icon: CupertinoIcons.arrow_up_doc,
                      title: '创建备份',
                      subtitle: '备份书库数据和阅读进度',
                      color: AppColors.primary,
                      isLoading: _isCreatingBackup,
                      onTap: _createBackup,
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.arrow_down_doc,
                      title: '恢复备份',
                      subtitle: '从备份文件恢复数据',
                      color: FunctionalColors.success,
                      onTap: _restoreBackup,
                    ),
                    const _SettingsDivider(),
                    _SettingsButton(
                      icon: CupertinoIcons.delete,
                      title: '清空数据',
                      subtitle: '删除所有书库数据（保留表结构）',
                      color: FunctionalColors.error,
                      onTap: _clearAllData,
                    ),
                  ],
                ),
                if (_backups.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionTitle(title: '历史备份'),
                  const SizedBox(height: 8),
                  _SettingsCard(
                    children: _backups.map((info) {
                      return _SettingsButton(
                        icon: CupertinoIcons.doc_fill,
                        title: '备份 ${info.date}',
                        subtitle: info.size,
                        color: AppColors.primary,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(CupertinoIcons.share, size: 20),
                              onPressed: () => _backupService.shareBackup(info.file.path),
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.delete, size: 20, color: FunctionalColors.error),
                              onPressed: () => _deleteBackup(info.file),
                            ),
                          ],
                        ),
                        onTap: () => _restoreFromFile(info.file.path),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 32),
                _SectionTitle(title: '关于'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsRow(
                      title: '版本',
                      value: '1.0.0',
                    ),
                    const _SettingsDivider(indent: 16),
                    _SettingsRow(
                      title: '开发',
                      value: '拾光集',
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _themeModeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '日间';
      case AppThemeMode.dark:
        return '夜间';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }

  String _themeNameLabel(String themeId) {
    final config = ThemePresets.byId(themeId);
    return config?.name ?? '琥珀';
  }

  void _showThemePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择主题'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              ReadingSettingsService.instance.setThemeMode(AppThemeMode.light);
            },
            child: Text(
              '日间',
              style: TextStyle(
                color: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.light
                    ? AppColors.primary
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.light
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              ReadingSettingsService.instance.setThemeMode(AppThemeMode.dark);
            },
            child: Text(
              '夜间',
              style: TextStyle(
                color: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.dark
                    ? AppColors.primary
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.dark
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              ReadingSettingsService.instance.setThemeMode(AppThemeMode.system);
            },
            child: Text(
              '跟随系统',
              style: TextStyle(
                color: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.system
                    ? AppColors.primary
                    : (isDark ? Colors.white : Colors.black),
                fontWeight: ReadingSettingsService.instance.settings.appThemeMode == AppThemeMode.system
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showThemeColorPicker() {
    final currentId = ReadingSettingsService.instance.settings.themeId;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择主题色'),
        actions: ThemePresets.all.map((config) {
          final isSelected = config.id == currentId;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              ReadingSettingsService.instance.setThemeId(config.id);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: config.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  config.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(CupertinoIcons.checkmark_alt, size: 16, color: AppColors.primary),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _openTypeSettings(MediaType type) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => MediaTypeSettingsScreen(mediaType: type),
      ),
    );
  }

  void _navigateToPrivacySettings() {
    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (_) => const PrivacySettingsScreen(),
          ),
        )
        .then((result) {
          if (result == 'locked' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已锁定私密空间'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
  }

  Future<void> _scanAndImport() async {
    setState(() => _isScanning = true);

    final scanner = FilesystemScanner();
    final types = [MediaType.novel, MediaType.video, MediaType.music];
    var totalAdded = 0;
    var totalImported = 0;
    final allOrphaned = <LibraryItem>[];

    for (final type in types) {
      final result = await scanner.fullScan(type);
      if (result.addedPaths.isNotEmpty) {
        totalAdded += result.addedPaths.length;
        final imported = await scanner.autoImportAdded(result, type);
        totalImported += imported;
      }
      allOrphaned.addAll(result.orphanedItems);
    }

    setState(() => _isScanning = false);

    if (!mounted) return;

    context.read<LibraryProvider>().loadLibrary();
    MusicScanService.instance.syncFromLibrary();

    if (allOrphaned.isNotEmpty) {
      final confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('发现缺失文件'),
          content: Text('扫描完成：发现新增 $totalAdded 个，导入成功 $totalImported 个。\n\n同时检测到 ${allOrphaned.length} 个文件已从本地删除，是否将其移入回收站？'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('暂不处理'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移入回收站'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        final marked = await FilesystemScanner().markOrphanedAsDeleted(allOrphaned);
        context.read<LibraryProvider>().loadLibrary();
        _showSuccess('已清理 $marked 个缺失文件');
      }
    } else {
      _showSuccess('扫描完成：发现新增 $totalAdded 个，导入成功 $totalImported 个');
    }
  }

  Future<void> _cleanupMissingFiles() async {
    setState(() => _isScanning = true);

    final scanner = FilesystemScanner();
    final types = [MediaType.novel, MediaType.video, MediaType.music];
    final allOrphaned = <LibraryItem>[];

    for (final type in types) {
      final result = await scanner.incrementalScan(type, checkOrphaned: true);
      allOrphaned.addAll(result.orphanedItems);
    }

    setState(() => _isScanning = false);

    if (!mounted) return;

    if (allOrphaned.isEmpty) {
      _showSuccess('未发现缺失文件');
      return;
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('确认清理'),
        content: Text('检测到 ${allOrphaned.length} 个文件已从本地删除，是否将其移入回收站？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移入回收站'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final marked = await FilesystemScanner().markOrphanedAsDeleted(allOrphaned);
      context.read<LibraryProvider>().loadLibrary();
      _showSuccess('已清理 $marked 个缺失文件');
    }
  }

  Future<void> _clearAllData() async {
    // 敏感操作前需要身份验证
    if (!PrivacyService.instance.isUnlocked) {
      final success = await PrivacyService.instance.unlock();
      if (!success || !mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('认证失败，无法执行敏感操作'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认清空'),
        content: const Text('此操作将删除所有书库数据、阅读进度、封面缓存和导入的文件，且无法恢复。是否继续？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<LibraryProvider>().clearAllData();
      await context.read<ComicSeriesProvider>().clearAllData();
      // 清空音乐播放器队列并刷新音乐页面
      await MusicPlayerService.instance.clearQueue();
      MusicLibraryView.globalKey.currentState?.refresh();
      if (mounted) {
        _showSuccess('数据已清空');
      }
    }
  }

  Future<void> _createBackup() async {
    setState(() => _isCreatingBackup = true);
    final path = await _backupService.createBackup();
    setState(() => _isCreatingBackup = false);
    if (path != null) {
      await _loadBackups();
      if (mounted) {
        _showSuccess('备份创建成功');
      }
    } else {
      if (mounted) {
        _showError('备份创建失败');
      }
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path != null) {
      await _restoreFromFile(path);
    }
  }

  Future<void> _restoreFromFile(String path) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认恢复'),
        content: const Text('恢复备份将覆盖当前所有数据，是否继续？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isRestoring = true);
      final success = await _backupService.restoreBackup(path);
      setState(() => _isRestoring = false);
      if (mounted) {
        _showSuccess(success ? '恢复成功' : '恢复失败');
      }
    }
  }

  Future<void> _deleteBackup(File file) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，是否继续？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _backupService.deleteBackup(file.path);
      await _loadBackups();
    }
  }

  void _showSuccess(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    _showSuccess(message);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _CacheInfoRow extends StatelessWidget {
  final int sizeBytes;
  final int limitMB;
  final int count;
  final bool isLoading;

  const _CacheInfoRow({
    required this.sizeBytes,
    required this.limitMB,
    required this.count,
    required this.isLoading,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    final limitBytes = limitMB > 0 ? limitMB * 1024 * 1024 : null;
    final progress = limitBytes != null && limitBytes > 0
        ? (sizeBytes / limitBytes).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '缓存占用',
                style: TextStyle(
                  fontSize: 16,
                  color: neutral.textPrimary,
                ),
              ),
              if (isLoading)
                const CupertinoActivityIndicator(radius: 10)
              else
                Text(
                  '${_formatSize(sizeBytes)} / ${limitMB <= 0 ? '无限制' : _formatSize(limitBytes!)} · $count 个文件',
                  style: TextStyle(
                    fontSize: 14,
                    color: neutral.textSecondary,
                  ),
                ),
            ],
          ),
          if (limitBytes != null && limitBytes > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: neutral.divider,
                valueColor: AlwaysStoppedAnimation(
                  progress > 0.9 ? FunctionalColors.error : AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final neutral = Theme.of(context).brightness == Brightness.dark
        ? NeutralPalette.dark
        : NeutralPalette.light;
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: neutral.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return Container(
      decoration: BoxDecoration(
        color: neutral.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: isDark
            ? null
            : [AppShadows.ambient],
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;
  final Widget? trailing;

  const _SettingsButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLoading = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return _Pressable(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: isLoading
                  ? CupertinoActivityIndicator(color: color, radius: 10)
                  : Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: neutral.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: neutral.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            trailing ?? Icon(
              CupertinoIcons.chevron_forward,
              color: neutral.textTertiary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final String value;

  const _SettingsRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: neutral.textPrimary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: neutral.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRowTap extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;
  final Widget? valuePrefix;

  const _SettingsRowTap({
    required this.title,
    required this.value,
    required this.onTap,
    this.valuePrefix,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return _Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: neutral.textPrimary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (valuePrefix != null) ...[
                  valuePrefix!,
                  const SizedBox(width: 6),
                ],
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: neutral.textSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: neutral.textTertiary,
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  final double indent;
  const _SettingsDivider({this.indent = 56});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: indent,
      color: NeutralPalette.of(context).divider,
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: neutral.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: neutral.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 列表项按压反馈：scale 0.98 + 背景淡入
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _pressed ? neutral.textPrimary.withOpacity(0.04) : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
