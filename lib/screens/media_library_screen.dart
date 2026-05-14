import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import '../services/app_directories.dart';
import '../widgets/pressable.dart';

class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key});

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  bool _isLoading = true;
  int _totalBytes = 0;
  String _appDirPath = '';
  final Map<String, int> _categoryBytes = {};
  final Map<String, List<_FileItem>> _groupedFiles = {};
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final categories = {
      '小说': Directory(AppDirectories.novelDir),
      '漫画': Directory(AppDirectories.comicDir),
      '视频': Directory(AppDirectories.videoDir),
      '音乐': Directory(AppDirectories.musicDir),
      '封面缓存': Directory(AppDirectories.coversCacheDir),
      'WiFi传输': Directory(AppDirectories.wifiUploadDir),
      '备份': Directory(AppDirectories.backupDir),
    };

    var total = 0;
    final catBytes = <String, int>{};
    final grouped = <String, List<_FileItem>>{};

    for (final entry in categories.entries) {
      final dir = entry.value;
      if (!await dir.exists()) continue;

      var catTotal = 0;
      final files = <_FileItem>[];

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            catTotal += stat.size;
            files.add(_FileItem(
              name: path.basename(entity.path),
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
              category: entry.key,
            ));
          } catch (_) {}
        }
      }

      if (files.isNotEmpty) {
        files.sort((a, b) => b.size.compareTo(a.size));
        grouped[entry.key] = files;
        catBytes[entry.key] = catTotal;
        total += catTotal;
      }
    }

    if (mounted) {
      setState(() {
        _totalBytes = total;
        _appDirPath = AppDirectories.mediaRootDir;
        _categoryBytes.addAll(catBytes);
        _groupedFiles.clear();
        _groupedFiles.addAll(grouped);
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFile(_FileItem item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认删除'),
        content: Text('删除 ${item.name}？此操作不可恢复。'),
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
    if (confirm != true) return;

    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
      return;
    }

    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: neutral.background,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 8),
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(CupertinoIcons.back, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  '媒体库',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: _buildTotalCard(isDark),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            child: _buildCategoryGrid(isDark),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            child: Text(
                              '文件夹 (${_groupedFiles.length})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: neutral.textTertiary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        SliverList.builder(
                          itemCount: _groupedFiles.length,
                          itemBuilder: (context, index) {
                            final entry = _groupedFiles.entries.elementAt(index);
                            return _FolderSection(
                              category: entry.key,
                              files: entry.value,
                              isDark: isDark,
                              isExpanded: _expandedCategories.contains(entry.key),
                              onToggle: () {
                                setState(() {
                                  if (_expandedCategories.contains(entry.key)) {
                                    _expandedCategories.remove(entry.key);
                                  } else {
                                    _expandedCategories.add(entry.key);
                                  }
                                });
                              },
                              onDeleteFile: (item) => _deleteFile(item),
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(height: bottomPadding + 20),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard(bool isDark) {
    final neutral = NeutralPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: isDark
            ? null
            : [
                AppShadows.ambient,
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(CupertinoIcons.folder_fill, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '总占用空间',
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatSize(_totalBytes),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: neutral.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_appDirPath.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: NeutralPalette.of(context).divider,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _appDirPath,
                    style: TextStyle(
                      fontSize: 12,
                      color: neutral.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minSize: 0,
                  onPressed: () => _copyPath(_appDirPath),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: const Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyPath(String filePath) async {
    await Clipboard.setData(ClipboardData(text: filePath));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('路径已复制到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildCategoryGrid(bool isDark) {
    final neutral = NeutralPalette.of(context);
    final entries = _categoryBytes.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s20),
        decoration: BoxDecoration(
          color: neutral.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
        child: Center(
          child: Text('暂无文件', style: TextStyle(color: neutral.textTertiary)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.large),
        boxShadow: isDark
            ? null
            : [
                AppShadows.ambient,
              ],
      ),
      child: Column(
        children: entries.asMap().entries.map((mapEntry) {
          final index = mapEntry.key;
          final entry = mapEntry.value;
          final percent = _totalBytes > 0 ? entry.value / _totalBytes : 0.0;
          final color = _categoryColor(entry.key);

          return Column(
            children: [
              if (index > 0)
                Divider(height: 1, indent: 56, color: NeutralPalette.of(context).divider),
              Padding(
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
                      child: Icon(_categoryIcon(entry.key), color: color, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: neutral.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.small),
                            child: LinearProgressIndicator(
                              value: percent,
                              backgroundColor: isDark ? neutral.surfaceElevated : neutral.divider,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatSize(entry.value),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: neutral.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      '小说' => AppColors.primary,
      '漫画' => FunctionalColors.warning,
      '视频' => FunctionalColors.success,
      '音乐' => const Color(0xFFAF52DE),
      '封面缓存' => const Color(0xFF5856D6),
      'WiFi传输' => const Color(0xFF00C7BE),
      '备份' => FunctionalColors.error,
      _ => NeutralColorsLight.textTertiary,
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      '小说' => CupertinoIcons.book,
      '漫画' => CupertinoIcons.photo,
      '视频' => CupertinoIcons.film,
      '音乐' => CupertinoIcons.music_note,
      '封面缓存' => CupertinoIcons.photo_fill,
      'WiFi传输' => CupertinoIcons.wifi,
      '备份' => CupertinoIcons.archivebox,
      _ => CupertinoIcons.doc,
    };
  }

}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}

class _FileItem {
  final String name;
  final String path;
  final int size;
  final DateTime modified;
  final String category;

  _FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    required this.category,
  });
}

class _FolderSection extends StatelessWidget {
  final String category;
  final List<_FileItem> files;
  final bool isDark;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(_FileItem) onDeleteFile;

  const _FolderSection({
    required this.category,
    required this.files,
    required this.isDark,
    required this.isExpanded,
    required this.onToggle,
    required this.onDeleteFile,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final color = _categoryColor(category);
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        children: [
          Pressable(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: neutral.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Icon(_categoryIcon(category), color: color, size: 14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: neutral.textPrimary,
                          ),
                        ),
                        Text(
                          '${files.length} 个文件 · ${_formatSize(totalSize)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: neutral.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: files.map((item) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark ? neutral.surfaceElevated : neutral.surface,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: neutral.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _formatSize(item.size),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: neutral.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () => onDeleteFile(item),
                          child: Icon(
                            CupertinoIcons.trash_fill,
                            color: FunctionalColors.error,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    return switch (category) {
      '小说' => AppColors.primary,
      '漫画' => FunctionalColors.warning,
      '视频' => FunctionalColors.success,
      '音乐' => const Color(0xFFAF52DE),
      '封面缓存' => const Color(0xFF5856D6),
      'WiFi传输' => const Color(0xFF00C7BE),
      '备份' => FunctionalColors.error,
      _ => NeutralColorsLight.textTertiary,
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      '小说' => CupertinoIcons.book,
      '漫画' => CupertinoIcons.photo,
      '视频' => CupertinoIcons.film,
      '音乐' => CupertinoIcons.music_note,
      '封面缓存' => CupertinoIcons.photo_fill,
      'WiFi传输' => CupertinoIcons.wifi,
      '备份' => CupertinoIcons.archivebox,
      _ => CupertinoIcons.doc,
    };
  }
}
