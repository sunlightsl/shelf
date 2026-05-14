import 'package:local_library/design_tokens/app_shadows.dart';
import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_typography.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../services/folder_settings_service.dart';
import '../services/music_player_settings.dart';
import '../services/tmdb_settings_service.dart';
import '../widgets/pressable.dart';
import 'media/music/eq_settings_sheet.dart';

class MediaTypeSettingsScreen extends StatefulWidget {
  final MediaType mediaType;

  const MediaTypeSettingsScreen({super.key, required this.mediaType});

  @override
  State<MediaTypeSettingsScreen> createState() => _MediaTypeSettingsScreenState();
}

class _MediaTypeSettingsScreenState extends State<MediaTypeSettingsScreen> {
  List<String> _folders = [];
  List<String> _blacklist = [];
  bool _isLoading = false;
  bool _showImportEntry = false;

  // 音效设置
  bool _eqEnabled = false;
  String _eqPresetLabel = '关闭';
  bool _vinylMode = false;
  bool _showVinylCenterDot = true;

  // 视频刮削设置
  String? _tmdbApiKey;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadBlacklist();
    _loadShowImportEntry();
    _loadEqSettings();
    _loadVinylMode();
    _loadShowVinylCenterDot();
    _loadTmdbApiKey();
  }

  Future<void> _loadEqSettings() async {
    if (widget.mediaType != MediaType.music) return;
    final eqEnabled = await MusicPlayerSettings.getEqEnabled();
    final eqPreset = await MusicPlayerSettings.getEqPreset();
    if (mounted) {
      setState(() {
        _eqEnabled = eqEnabled;
        _eqPresetLabel = MusicPlayerSettings.presetLabel(eqPreset);
      });
    }
  }

  Future<void> _loadShowImportEntry() async {
    final value = await FolderSettingsService.instance.getShowImportEntry(widget.mediaType);
    if (mounted) {
      setState(() => _showImportEntry = value);
    }
  }

  Future<void> _loadFolders() async {
    final folders = await FolderSettingsService.instance.getScanFolders(widget.mediaType);
    if (mounted) {
      setState(() => _folders = folders);
    }
  }

  Future<void> _loadBlacklist() async {
    final blacklist = await FolderSettingsService.instance.getBlacklist(widget.mediaType);
    if (mounted) {
      setState(() => _blacklist = blacklist);
    }
  }

  Future<void> _addBlacklistFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    await FolderSettingsService.instance.addToBlacklist(widget.mediaType, result);
    await _loadBlacklist();
  }

  Future<void> _removeBlacklistFolder(String folder) async {
    await FolderSettingsService.instance.removeFromBlacklist(widget.mediaType, folder);
    await _loadBlacklist();
  }

  Future<void> _loadVinylMode() async {
    if (widget.mediaType != MediaType.music) return;
    final mode = await MusicPlayerSettings.getVinylMode();
    if (mounted) setState(() => _vinylMode = mode);
  }

  Future<void> _loadShowVinylCenterDot() async {
    if (widget.mediaType != MediaType.music) return;
    final value = await MusicPlayerSettings.getShowVinylCenterDot();
    if (mounted) setState(() => _showVinylCenterDot = value);
  }

  Future<void> _loadTmdbApiKey() async {
    if (widget.mediaType != MediaType.video) return;
    final key = await TMDBSettingsService.getApiKey();
    if (mounted) setState(() => _tmdbApiKey = key);
  }

  Future<void> _showTmdbKeyDialog() async {
    final ctrl = TextEditingController(text: _tmdbApiKey ?? '');
    final result = await showCupertinoDialog<String?>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('TMDB API Key'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: '输入 TMDB API Key',
            autocorrect: false,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (result != null) {
      await TMDBSettingsService.setApiKey(result.isEmpty ? null : result);
      if (mounted) setState(() => _tmdbApiKey = result.isEmpty ? null : result);
    }
  }

  void _showEqSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => const EqSettingsSheet(),
    ).then((_) => _loadEqSettings());
  }

  String get _typeName {
    return switch (widget.mediaType) {
      MediaType.novel => '小说',
      MediaType.comic => '漫画',
      MediaType.video => '视频',
      MediaType.music => '音乐',
    };
  }

  Future<void> _addFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    await FolderSettingsService.instance.addScanFolder(widget.mediaType, result);
    await _loadFolders();
  }

  Future<void> _removeFolder(String folder) async {
    await FolderSettingsService.instance.removeScanFolder(widget.mediaType, folder);
    await _loadFolders();
  }

  Future<void> _scanFolders() async {
    if (_folders.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('没有配置文件夹'),
          content: const Text('请先添加扫描文件夹'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<LibraryProvider>();
    final validPaths = <String>[];
    int foundCount = 0;

    final blacklist = await FolderSettingsService.instance.getBlacklist(widget.mediaType);
    final lowerBlacklist = blacklist.map((f) => f.toLowerCase()).toList();

    bool isBlacklisted(String path) {
      final lowerPath = path.toLowerCase();
      for (final folder in lowerBlacklist) {
        if (lowerPath == folder || lowerPath.startsWith('$folder\\') || lowerPath.startsWith('$folder/')) {
          return true;
        }
      }
      return false;
    }

    for (final dirPath in _folders) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      validPaths.add(dirPath);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && !isBlacklisted(entity.path) && _isValidExtension(entity.path)) {
          foundCount++;
        }
      }
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (foundCount == 0) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('扫描完成'),
          content: const Text('在配置的文件夹中未找到可导入的文件'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('扫描完成'),
        content: Text('发现 $foundCount 个可导入的文件，是否导入？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await provider.scanAndImportFromPathsWithType(validPaths, widget.mediaType);
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('导入完成'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  bool _isValidExtension(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (widget.mediaType) {
      MediaType.novel => ['txt', 'epub', 'pdf', 'mobi', 'azw3'].contains(ext),
      MediaType.comic => ['zip', 'cbz', 'rar', 'cbr', 'pdf'].contains(ext),
      MediaType.video => ['mp4', 'mkv', 'avi', 'mov', 'wmv'].contains(ext),
      MediaType.music => ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'].contains(ext),
    };
  }

  Future<void> _addDefaultDownloadFolders() async {
    final List<String> defaults = [];
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        defaults.add('${externalDir.parent.path}/Download');
        defaults.add('${externalDir.parent.path}/Downloads');
      }
    } catch (_) {}
    defaults.add('/storage/emulated/0/Download');
    defaults.add('/storage/emulated/0/Downloads');

    for (final p in defaults) {
      final dir = Directory(p);
      if (await dir.exists()) {
        await FolderSettingsService.instance.addScanFolder(widget.mediaType, p);
      }
    }
    await _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('$_typeName设置'),
        border: null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.s20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 导入入口设置
                  _buildSectionTitle('导入入口'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: _buildSwitchRow(isDark: isDark,
                      icon: CupertinoIcons.plus_circle,
                      label: '在书架显示导入入口',
                      subtitle: '在书架网格中显示快捷导入按钮',
                      value: _showImportEntry,
                      onChanged: (v) async {
                        setState(() => _showImportEntry = v);
                        await FolderSettingsService.instance.setShowImportEntry(widget.mediaType, v);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 扫描文件夹区域
                  _buildSectionTitle('扫描文件夹'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Column(
                      children: [
                        if (_folders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s20),
                            child: Text(
                              '暂无扫描文件夹\n点击下方按钮添加',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: neutral.textTertiary,
                              ),
                            ),
                          )
                        else
                          ..._folders.map((folder) => _buildFolderRow(folder, isDark)),
                        Divider(height: 1, color: NeutralPalette.of(context).divider),
                        _buildActionRow(
                          icon: CupertinoIcons.plus_circle_fill,
                          label: '添加文件夹',
                          color: AppColors.primary,
                          onTap: _addFolder,
                          isDark: isDark,
                        ),
                        Divider(height: 1, color: NeutralPalette.of(context).divider),
                        _buildActionRow(
                          icon: CupertinoIcons.folder_badge_plus,
                          label: '添加常用下载文件夹',
                          color: FunctionalColors.success,
                          onTap: _addDefaultDownloadFolders,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 扫描黑名单区域
                  _buildSectionTitle('扫描黑名单'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Column(
                      children: [
                        if (_blacklist.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s20),
                            child: Text(
                              '暂无黑名单文件夹\n添加后扫描时将自动排除',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: neutral.textTertiary,
                              ),
                            ),
                          )
                        else
                          ..._blacklist.map((folder) => _buildBlacklistRow(folder, isDark)),
                        Divider(height: 1, color: NeutralPalette.of(context).divider),
                        _buildActionRow(
                          icon: CupertinoIcons.nosign,
                          label: '添加排除文件夹',
                          color: FunctionalColors.error,
                          onTap: _addBlacklistFolder,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 扫描操作区域
                  _buildSectionTitle('操作'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Column(
                      children: [
                        _buildActionRow(
                          icon: CupertinoIcons.arrow_clockwise,
                          label: '开始扫描',
                          subtitle: '扫描已配置的文件夹并导入',
                          color: FunctionalColors.warning,
                          onTap: _isLoading ? null : _scanFolders,
                          isLoading: _isLoading,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  if (widget.mediaType == MediaType.video) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle('刮削设置'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: neutral.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                        boxShadow: isDark ? null : [AppShadows.ambient],
                      ),
                      child: _buildActionRow(
                        icon: CupertinoIcons.globe,
                        label: 'TMDB API Key',
                        subtitle: _tmdbApiKey != null && _tmdbApiKey!.isNotEmpty
                            ? '已配置'
                            : '未配置（用于获取视频海报和元数据）',
                        color: AppColors.primary,
                        onTap: _showTmdbKeyDialog,
                        isDark: isDark,
                      ),
                    ),
                  ],
                  if (widget.mediaType == MediaType.music) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle('音效设置'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: neutral.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                        boxShadow: isDark ? null : [AppShadows.ambient],
                      ),
                      child: Column(
                        children: [
                          _buildActionRow(
                            icon: CupertinoIcons.slider_horizontal_3,
                            label: '均衡器',
                            subtitle: _eqEnabled ? '已开启 · $_eqPresetLabel' : '关闭',
                            color: AppColors.primary,
                            onTap: _showEqSheet,
                            isDark: isDark,
                          ),
                          Divider(height: 1, color: NeutralPalette.of(context).divider),
                          _buildSwitchRow(
                            icon: CupertinoIcons.circle,
                            label: '黑胶唱片封面',
                            subtitle: '播放器使用黑胶唱片风格旋转封面',
                            value: _vinylMode,
                            onChanged: (v) async {
                              setState(() => _vinylMode = v);
                              await MusicPlayerSettings.setVinylMode(v);
                            },
                            isDark: isDark,
                          ),
                          Divider(height: 1, color: NeutralPalette.of(context).divider),
                          _buildSwitchRow(
                            icon: CupertinoIcons.dot_square,
                            label: '唱片中心点',
                            subtitle: '黑胶唱片封面显示中心点',
                            value: _showVinylCenterDot,
                            onChanged: (v) async {
                              setState(() => _showVinylCenterDot = v);
                              await MusicPlayerSettings.setShowVinylCenterDot(v);
                            },
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final neutral = NeutralPalette.of(context);
    return Text(
      title,
      style: AppTypography.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: neutral.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFolderRow(String folder, bool isDark) {
    final neutral = NeutralPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(CupertinoIcons.folder, color: neutral.textTertiary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder,
              style: AppTypography.body.copyWith(color: neutral.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => _removeFolder(folder),
            child: Icon(CupertinoIcons.delete, color: FunctionalColors.error, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildBlacklistRow(String folder, bool isDark) {
    final neutral = NeutralPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(CupertinoIcons.nosign, color: FunctionalColors.error.withOpacity(0.6), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder,
              style: AppTypography.body.copyWith(color: neutral.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => _removeBlacklistFolder(folder),
            child: Icon(CupertinoIcons.xmark, color: neutral.textTertiary, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDark = false,
  }) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(color: neutral.textTertiary),
                    ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
    bool isDark = false,
  }) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: isLoading
                  ? CupertinoActivityIndicator(color: color, radius: 10)
                  : Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppTypography.caption.copyWith(color: neutral.textTertiary),
                    ),
                ],
              ),
            ),
            Icon(
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
