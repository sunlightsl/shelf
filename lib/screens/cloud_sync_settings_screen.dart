import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../design_tokens/app_colors.dart';
import '../design_tokens/app_radius.dart';
import '../design_tokens/app_shadows.dart';
import '../services/auto_sync_service.dart';
import '../services/offline_cache_service.dart';
import 'cloud_storage_accounts_screen.dart';

class CloudSyncSettingsScreen extends StatefulWidget {
  const CloudSyncSettingsScreen({super.key});

  @override
  State<CloudSyncSettingsScreen> createState() => _CloudSyncSettingsScreenState();
}

class _CloudSyncSettingsScreenState extends State<CloudSyncSettingsScreen> {
  bool _autoSyncEnabled = false;
  int _cacheSizeBytes = 0;
  int _cacheLimitMB = 0;
  int _cacheCount = 0;
  bool _isLoadingCache = false;

  @override
  void initState() {
    super.initState();
    _loadAutoSync();
    _loadCacheInfo();
  }

  Future<void> _loadAutoSync() async {
    final enabled = await AutoSyncService.isEnabled();
    if (mounted) setState(() => _autoSyncEnabled = enabled);
  }

  Future<void> _toggleAutoSync(bool value) async {
    await AutoSyncService.setEnabled(value);
    setState(() => _autoSyncEnabled = value);
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
        content: Text(
          '将删除 $_cacheCount 个云端下载的缓存文件（共 ${_formatFileSizeMB(_cacheSizeBytes)}），此操作不可恢复。',
        ),
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
    if (confirm == true) {
      setState(() => _isLoadingCache = true);
      await OfflineCacheService.instance.clearAllCache();
      await _loadCacheInfo();
    }
  }

  String _formatFileSizeMB(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatCacheSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云同步'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding + 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _SectionTitle(title: '云端账户'),
              const SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _SettingsButton(
                    icon: CupertinoIcons.cloud,
                    title: '云存储账户',
                    subtitle: '管理 WebDAV 等云存储连接',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const CloudStorageAccountsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '同步设置'),
              const SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _SettingsSwitch(
                    icon: CupertinoIcons.arrow_2_circlepath,
                    title: '自动同步阅读进度',
                    subtitle: '切换应用时自动上传/下载进度',
                    color: AppColors.primary,
                    value: _autoSyncEnabled,
                    onChanged: (v) => _toggleAutoSync(v),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '离线缓存'),
              const SizedBox(height: 8),
              _SettingsCard(
                children: [
                  _CacheInfoRow(
                    sizeBytes: _cacheSizeBytes,
                    limitMB: _cacheLimitMB,
                    count: _cacheCount,
                    isLoading: _isLoadingCache,
                  ),
                  _SettingsDivider(indent: 16),
                  _SettingsRowTap(
                    title: '缓存上限',
                    value: _cacheLimitMB <= 0 ? '无限制' : '$_cacheLimitMB MB',
                    onTap: _showCacheLimitPicker,
                  ),
                  _SettingsDivider(),
                  _SettingsButton(
                    icon: CupertinoIcons.trash,
                    title: '清理缓存',
                    subtitle: '删除所有云端下载的缓存文件',
                    color: FunctionalColors.error,
                    onTap: _clearCache,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
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
        boxShadow: isDark ? null : [AppShadows.ambient],
      ),
      child: Column(children: children),
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

  const _SettingsButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isLoading = false,
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

class _SettingsRowTap extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SettingsRowTap({
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
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
    final neutral = NeutralPalette.of(context);
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
