import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../providers/comic_series_provider.dart';
import '../services/folder_settings_service.dart';
import '../services/wifi_transfer_service.dart';
import '../services/import_pipeline.dart';
import '../widgets/pressable.dart';
import 'cloud_storage_accounts_screen.dart';

Future<void> _scanDownloadFolders(BuildContext context) async {
  final provider = context.read<LibraryProvider>();
  final List<String> scanPaths = [];

  // 从所有类型的配置中收集扫描文件夹
  for (final type in MediaType.values) {
    final folders = await FolderSettingsService.instance.getScanFolders(type);
    for (final f in folders) {
      if (!scanPaths.contains(f)) scanPaths.add(f);
    }
  }

  // 如果没有任何配置，使用默认下载目录
  if (scanPaths.isEmpty) {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        scanPaths.add('${externalDir.parent.path}/Download');
        scanPaths.add('${externalDir.parent.path}/Downloads');
      }
    } catch (_) {}
    scanPaths.add('/storage/emulated/0/Download');
    scanPaths.add('/storage/emulated/0/Downloads');
  }

  int foundCount = 0;
  for (final dirPath in scanPaths) {
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          if (ImportPipeline.isSupportedExtension(entity.path)) {
            foundCount++;
          }
        }
      }
    }
  }

  if (!context.mounted) return;

  if (foundCount == 0) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('扫描完成'),
        content: const Text('在配置的下载文件夹中未找到可导入的文件'),
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

  if (confirm == true) {
    await provider.scanAndImportFromPaths(scanPaths);
  }
}

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('导入资源'),
        border: null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _ImportCard(
                    isDark: isDark,
                    icon: CupertinoIcons.doc_text,
                    title: '选择文件',
                    subtitle: '从设备中选择单个或多个文件',
                    color: AppColors.primary,
                    onTap: () => context.read<LibraryProvider>().importFiles(),
                  ),
                  const SizedBox(height: 12),
                  _ImportCard(
                    isDark: isDark,
                    icon: CupertinoIcons.folder,
                    title: '选择文件夹',
                    subtitle: '批量导入整个文件夹中的内容',
                    color: FunctionalColors.success,
                    onTap: () => context.read<LibraryProvider>().importFolder(),
                  ),
                  const SizedBox(height: 12),
                  _ImportCard(
                    isDark: isDark,
                    icon: CupertinoIcons.arrow_down_circle,
                    title: '扫描下载文件夹',
                    subtitle: '自动扫描常见下载文件夹',
                    color: FunctionalColors.warning,
                    onTap: () => _scanDownloadFolders(context),
                  ),
                  const SizedBox(height: 12),
                  _ImportCard(
                    isDark: isDark,
                    icon: CupertinoIcons.cloud,
                    title: '云存储',
                    subtitle: '从 WebDAV / S3 云端导入资源',
                    color: const Color(0xFF5B8DEF),
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const CloudStorageAccountsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _WifiTransferSection(isDark: isDark),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ImportCard({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: isDark ? neutral.surface : neutral.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: isDark ? null : [AppShadows.ambient],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: neutral.textTertiary,
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

class _WifiTransferSection extends StatefulWidget {
  final bool isDark;

  const _WifiTransferSection({required this.isDark});

  @override
  State<_WifiTransferSection> createState() => _WifiTransferSectionState();
}

class _WifiTransferSectionState extends State<_WifiTransferSection> {
  final WifiTransferService _wifiService = WifiTransferService.instance;
  StreamSubscription<String>? _uploadSubscription;

  @override
  void initState() {
    super.initState();
    _wifiService.addListener(_onServiceUpdate);
    _uploadSubscription = _wifiService.uploadStream.listen(_onFileUploaded);
  }

  @override
  void dispose() {
    _uploadSubscription?.cancel();
    _wifiService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onFileUploaded(String filePath) async {
    final type = _wifiService.getFileType(filePath);
    final provider = context.read<LibraryProvider>();
    LibraryItem? item;
    try {
      if (type != null && type != 'auto') {
        final mediaType = switch (type) {
          'novel' => MediaType.novel,
          'comic' => MediaType.comic,
          'video' => MediaType.video,
          'music' => MediaType.music,
          _ => null,
        };
        if (mediaType != null) {
          item = await provider.importFromWifiWithType(filePath, mediaType);
        } else {
          item = await provider.importFromWifi(filePath);
        }
      } else {
        item = await provider.importFromWifi(filePath);
      }

      if (item != null) {
        _wifiService.updateTransferRecord(filePath,
          status: 'success',
          destinationPath: item.filePath,
        );
        if (item.mediaType == MediaType.comic) {
          await context.read<ComicSeriesProvider>().loadSeries();
        }
      } else {
        _wifiService.updateTransferRecord(filePath,
          status: 'failed',
          errorMessage: '文件格式不支持或导入失败',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入失败：文件格式不支持')),
          );
        }
      }
    } catch (e) {
      _wifiService.updateTransferRecord(filePath,
        status: 'failed',
        errorMessage: e.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: neutral.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: widget.isDark ? null : [AppShadows.ambient],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FunctionalColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(
                  CupertinoIcons.wifi,
                  color: FunctionalColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WiFi 传输',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: neutral.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '同一局域网内通过浏览器导入',
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: _wifiService.isRunning,
                onChanged: (value) async {
                  if (value) {
                    await _wifiService.startServer();
                  } else {
                    await _wifiService.stopServer();
                  }
                },
              ),
            ],
          ),
          if (_wifiService.isRunning && _wifiService.ipAddress != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(AppSpacing.s16),
              decoration: BoxDecoration(
                color: widget.isDark ? neutral.surfaceElevated : neutral.background,
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: Column(
                children: [
                  Text(
                    '在电脑浏览器中打开',
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.isDark ? neutral.textTertiary : neutral.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'http://${_wifiService.ipAddress}:${_wifiService.port}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (_wifiService.transferHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '传输记录',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: neutral.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: _wifiService.clearTransferHistory,
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _wifiService.transferHistory.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: neutral.divider),
                  itemBuilder: (context, index) {
                    final record = _wifiService.transferHistory[index];
                    return _TransferHistoryTile(record: record);
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TransferHistoryTile extends StatelessWidget {
  final WifiTransferRecord record;

  const _TransferHistoryTile({required this.record});

  String get _typeLabel {
    switch (record.mediaTypeLabel) {
      case 'novel':
        return '小说';
      case 'comic':
        return '漫画';
      case 'video':
        return '视频';
      case 'music':
        return '音乐';
      default:
        return '自动识别';
    }
  }

  String get _statusLabel {
    switch (record.status) {
      case 'success':
        return '导入成功';
      case 'failed':
        return '导入失败';
      case 'pending':
        return '处理中...';
      default:
        return record.status;
    }
  }

  Color _statusColor(BuildContext context) {
    switch (record.status) {
      case 'success':
        return FunctionalColors.success;
      case 'failed':
        return FunctionalColors.error;
      case 'pending':
        return NeutralPalette.of(context).textTertiary;
      default:
        return NeutralPalette.of(context).textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.fileName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: neutral.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (record.destinationPath != null)
            Text(
              '存放路径：${record.destinationPath}',
              style: TextStyle(
                fontSize: 11,
                color: neutral.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}:${record.timestamp.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 11,
                  color: neutral.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: _statusColor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (record.errorMessage != null) ...[
            const SizedBox(height: 2),
            Text(
              record.errorMessage!,
              style: TextStyle(
                fontSize: 11,
                color: FunctionalColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
