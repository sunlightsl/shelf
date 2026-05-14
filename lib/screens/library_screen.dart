import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';
import '../providers/comic_series_provider.dart';
import '../providers/library_provider.dart';
import '../services/cover_service.dart';
import '../services/folder_settings_service.dart';
import '../services/privacy_service.dart';
import '../services/video_filename_parser.dart';
import '../database/library_dao.dart';
import '../database/comic_series_dao.dart';
import '../database/offline_cache_dao.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/pressable.dart';
import '../widgets/cover_badges.dart';
import 'comic_series_detail_screen.dart';
import 'readers/novel_reader_screen.dart';
import 'readers/comic_reader_screen.dart';
import 'readers/video_player_screen.dart';
import 'readers/audio_player_screen.dart';
import 'book_detail_screen.dart';
import 'video_detail_screen.dart';

void _openReader(BuildContext context, LibraryItem item) {
  Widget screen;
  switch (item.mediaType) {
    case MediaType.novel:
      screen = BookDetailScreen(item: item);
      break;
    case MediaType.comic:
      screen = ComicReaderScreen(item: item);
      break;
    case MediaType.video:
      screen = VideoDetailScreen(item: item);
      break;
    case MediaType.music:
      screen = AudioPlayerScreen(item: item);
      break;
  }
  Navigator.of(context).push(
    CupertinoPageRoute(builder: (_) => screen),
  );
}

String _mediaTypeName(MediaType type) {
  switch (type) {
    case MediaType.novel:
      return '小说';
    case MediaType.comic:
      return '漫画';
    case MediaType.video:
      return '视频';
    case MediaType.music:
      return '音乐';
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // 选择模式状态
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};

  // 排序状态
  SortMode _sortMode = SortMode.title;
  bool _sortAscending = true;

  // 继续阅读/播放数据
  List<LibraryItem> _continueNovels = [];
  List<ComicSeries> _continueComics = [];

  // 云端已下载的 filePath 集合
  Set<String> _cloudFilePaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _selectionMode) {
        setState(() {
          _selectedIds.clear();
        });
      }
    });
    _loadContinueReading();
    _loadCloudPaths();
  }

  Future<void> _loadContinueReading() async {
    try {
      final novels = await LibraryDao().getContinueReading(MediaType.novel, limit: 10);
      // 漫画的继续阅读：从所有系列中筛选 readChapters > 0 且 < totalChapters 的
      final allSeries = await ComicSeriesDao().getAllSeries();
      final comics = allSeries.where((s) {
        return s.readChapters > 0 && s.totalChapters > 0 && s.readChapters < s.totalChapters;
      }).toList();
      // 按最后阅读时间排序，取前10
      comics.sort((a, b) {
        final at = a.lastReadAt ?? DateTime(1970);
        final bt = b.lastReadAt ?? DateTime(1970);
        return bt.compareTo(at);
      });
      if (comics.length > 10) comics.removeRange(10, comics.length);

      if (mounted) {
        setState(() {
          _continueNovels = novels;
          _continueComics = comics;
        });
      }
    } catch (e) {
      debugPrint('[LibraryScreen] 加载继续阅读失败: $e');
    }
  }

  Future<void> _loadCloudPaths() async {
    try {
      final paths = await OfflineCacheDao().getAllFilePaths();
      if (mounted) setState(() => _cloudFilePaths = paths);
    } catch (e) {
      debugPrint('[LibraryScreen] 加载云端路径失败: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim().toLowerCase());
  }

  void _enterSelection() {
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _showImportSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('导入'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              context.read<LibraryProvider>().importFilesWithType(MediaType.novel);
            },
            child: const Text('导入小说'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<LibraryProvider>().importFilesWithType(MediaType.comic);
              if (context.mounted) {
                context.read<ComicSeriesProvider>().loadSeries();
              }
            },
            child: const Text('导入漫画'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchTogglePrivate(LibraryProvider provider) async {
    if (_selectedIds.isEmpty) return;
    final selectedItems = provider.allItems.where((i) => _selectedIds.contains(i.id)).toList();
    final allPrivate = selectedItems.every((i) => i.isPrivate);
    await provider.setItemsPrivate(_selectedIds.toList(), !allPrivate);
    if (mounted) _exitSelection();
  }

  Future<void> _batchMove(LibraryProvider provider) async {
    if (_selectedIds.isEmpty) return;
    final targets = MediaType.values.where((t) => t != MediaType.novel).toList();

    final targetType = await showCupertinoModalPopup<MediaType>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('移动到'),
        actions: targets.map((type) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, type),
            child: Text(_mediaTypeName(type)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );

    if (targetType != null && mounted) {
      await provider.moveItemsToType(_selectedIds.toList(), targetType);
      // 如果目标类型是漫画，触发漫画系列扫描，使漫画 tab 能立即显示
      if (targetType == MediaType.comic) {
        await context.read<ComicSeriesProvider>().loadSeries();
      }
      if (mounted) _exitSelection();
    }
  }

  Future<void> _batchSetGroup(LibraryProvider provider) async {
    if (_selectedIds.isEmpty) return;
    final groupController = TextEditingController();
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('分组'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: groupController,
            placeholder: '输入分组名（留空=移出分组）',
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: NeutralPalette.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, groupController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    groupController.dispose();
    if (result == null || !mounted) return;
    await provider.setItemsGroup(_selectedIds.toList(), result.isEmpty ? null : result);
    if (mounted) _exitSelection();
  }

  void _showSortSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('排序方式'),
        actions: [
          _sortAction(ctx, SortMode.title, '标题 (A-Z)'),
          _sortAction(ctx, SortMode.modifiedTime, '修改时间'),
          _sortAction(ctx, SortMode.addedTime, '添加时间'),
          _sortAction(ctx, SortMode.lastOpenedTime, '最近打开'),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _sortAction(BuildContext ctx, SortMode mode, String label) {
    final isSelected = _sortMode == mode;
    return CupertinoActionSheetAction(
      onPressed: () {
        Navigator.pop(ctx);
        setState(() => _sortMode = mode);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Icon(CupertinoIcons.checkmark_alt, size: 16, color: AppColors.primary),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Column(
          children: [
            // 固定头部：标题 + 搜索 + 分类
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '书架',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(width: 12),
                  if (!_selectionMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () => _showSortSheet(context),
                          child: const Text(
                            '排序方式',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () => setState(() => _sortAscending = !_sortAscending),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_up,
                                size: _sortAscending ? 12 : 7,
                                color: _sortAscending
                                    ? AppColors.primary
                                    : AppColors.primary.withOpacity(0.35),
                              ),
                              Icon(
                                CupertinoIcons.arrow_down,
                                size: !_sortAscending ? 12 : 7,
                                color: !_sortAscending
                                    ? AppColors.primary
                                    : AppColors.primary.withOpacity(0.35),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const Spacer(),
                  if (!_selectionMode)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: () => _showImportSheet(context),
                      child: const Icon(CupertinoIcons.add, color: AppColors.primary, size: 24),
                    ),
                  if (!_selectionMode) const SizedBox(width: 16),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _selectionMode ? _exitSelection : _enterSelection,
                    child: Text(
                      _selectionMode ? '完成' : '选择',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_selectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  placeholder: '搜索书名、作者',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: neutral.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: isDark ? neutral.surfaceElevated : neutral.surface,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: neutral.textPrimary,
                  unselectedLabelColor: neutral.textTertiary,
                  labelStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: '小说'),
                    Tab(text: '漫画'),
                  ],
                ),
              ),
            ),
            // 可滚动内容区域
            Expanded(
              child: Consumer<LibraryProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _MediaGrid(
                        items: provider.novels,
                        type: MediaType.novel,
                        query: _searchQuery,
                        selectionMode: _selectionMode,
                        selectedIds: _selectedIds,
                        onToggleSelect: _toggleSelect,
                        onLongPressStartSelection: (id) {
                          setState(() {
                            _selectionMode = true;
                            _selectedIds.add(id);
                          });
                        },
                        sortMode: _sortMode,
                        sortAscending: _sortAscending,
                        continueItems: _continueNovels,
                        cloudPaths: _cloudFilePaths,
                      ),
                      _ComicSeriesGrid(
                        query: _searchQuery,
                        selectionMode: _selectionMode,
                        selectedIds: _selectedIds,
                        onToggleSelect: _toggleSelect,
                        onTapSeries: (series) {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => ComicSeriesDetailScreen(series: series),
                            ),
                          );
                        },
                        sortMode: _sortMode,
                        sortAscending: _sortAscending,
                        continueItems: _continueComics,
                        cloudPaths: _cloudFilePaths,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (_selectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer<LibraryProvider>(
              builder: (context, provider, _) {
                final isComicTab = _tabController.index == 1;
                final comicProvider = context.read<ComicSeriesProvider>();
                final totalCount = isComicTab ? comicProvider.series.length : provider.novels.length;
                final allSelected = totalCount > 0 && _selectedIds.length == totalCount;

                return _SelectionBottomBar(
                  selectedCount: _selectedIds.length,
                  totalCount: totalCount,
                  allSelected: allSelected,
                  onSelectAll: () {
                    setState(() {
                      if (isComicTab) {
                        for (final s in comicProvider.series) {
                          if (s.id != null) _selectedIds.add(s.id!);
                        }
                      } else {
                        for (final item in provider.novels) {
                          if (item.id != null) _selectedIds.add(item.id!);
                        }
                      }
                    });
                  },
                  onClearAll: () => setState(() => _selectedIds.clear()),
                  onDelete: () async {
                    if (_selectedIds.isEmpty) return;
                    final confirm = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (context) {
                        final dialogNeutral = NeutralPalette.of(context);
                        return CupertinoAlertDialog(
                          title: Text('确认删除', style: TextStyle(color: dialogNeutral.textPrimary)),
                          content: Text('确定删除选中的 ${_selectedIds.length} 项？删除后将无法恢复。', style: TextStyle(color: dialogNeutral.textSecondary)),
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
                      );
                    },
                  );
                    if (confirm != true || !mounted) return;
                    if (isComicTab) {
                      final ids = _selectedIds.toList();
                      for (final id in ids) {
                        await comicProvider.deleteSeries(id);
                      }
                    } else {
                      await provider.deleteItems(_selectedIds.toList());
                    }
                    if (mounted) _exitSelection();
                  },
                  onTogglePrivate: () => _batchTogglePrivate(provider),
                  onGroup: () => _batchSetGroup(provider),
                  onToggleFavorite: () async {
                    if (isComicTab) return;
                    final selectedItems = provider.allItems
                        .where((i) => _selectedIds.contains(i.id))
                        .toList();
                    final allFavorited = selectedItems.every((i) => i.isFavorite);
                    await provider.setItemsFavorite(_selectedIds.toList(), !allFavorited);
                    if (mounted) _exitSelection();
                  },
                  onMove: isComicTab ? null : () => _batchMove(provider),
                  onMerge: isComicTab
                      ? () async {
                          if (_selectedIds.length < 2) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请至少选择 2 个系列'), duration: Duration(seconds: 1)),
                            );
                            return;
                          }
                          final controller = TextEditingController();
                          final confirm = await showCupertinoDialog<bool>(
                            context: context,
                            builder: (context) => CupertinoAlertDialog(
                              title: const Text('合并系列'),
                              content: Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: CupertinoTextField(
                                  controller: controller,
                                  placeholder: '输入合并后的系列名',
                                  padding: const EdgeInsets.all(AppSpacing.s12),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(AppRadius.small),
                                  ),
                                ),
                              ),
                              actions: [
                                CupertinoDialogAction(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                CupertinoDialogAction(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('合并'),
                                ),
                              ],
                            ),
                          );
                          controller.dispose();
                          if (confirm == true && mounted) {
                            await context.read<ComicSeriesProvider>().mergeSeries(
                              _selectedIds.toList(),
                              controller.text.trim(),
                            );
                            if (mounted) _exitSelection();
                          }
                        }
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ComicSeriesGrid extends StatefulWidget {
  final String query;
  final bool selectionMode;
  final Set<int> selectedIds;
  final void Function(int id) onToggleSelect;
  final void Function(ComicSeries series) onTapSeries;
  final SortMode sortMode;
  final bool sortAscending;
  final List<ComicSeries> continueItems;
  final Set<String> cloudPaths;

  const _ComicSeriesGrid({
    this.query = '',
    this.selectionMode = false,
    this.selectedIds = const {},
    required this.onToggleSelect,
    required this.onTapSeries,
    this.sortMode = SortMode.title,
    this.sortAscending = true,
    this.continueItems = const [],
    this.cloudPaths = const {},
  });

  @override
  State<_ComicSeriesGrid> createState() => _ComicSeriesGridState();
}

class _ComicSeriesGridState extends State<_ComicSeriesGrid>
    with AutomaticKeepAliveClientMixin {
  late Future<bool> _showEntryFuture;
  List<ComicSeries>? _cachedFiltered;
  String _cachedQuery = '';
  int _cachedSeriesLength = 0;
  final Map<String, DateTime> _modifiedCache = {};
  int _lastSeriesCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _showEntryFuture = FolderSettingsService.instance.getShowImportEntry(MediaType.comic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComicSeriesProvider>().loadSeries();
    });
  }

  Future<void> _refreshModifiedCache(List<ComicSeries> series) async {
    final futures = <Future<void>>[];
    for (final s in series) {
      final path = s.folderPath;
      if (path != null && !_modifiedCache.containsKey(path)) {
        futures.add(() async {
          try {
            final stat = await Directory(path).stat();
            _modifiedCache[path] = stat.modified;
          } catch (_) {
            _modifiedCache[path] = DateTime(1970);
          }
        }());
      }
    }
    await Future.wait(futures);
    if (mounted) setState(() {});
  }

  List<ComicSeries> _filterSeries(List<ComicSeries> series) {
    if (widget.query.isEmpty) return series;
    if (_cachedFiltered != null &&
        _cachedQuery == widget.query &&
        _cachedSeriesLength == series.length) {
      return _cachedFiltered!;
    }
    _cachedQuery = widget.query;
    _cachedSeriesLength = series.length;
    _cachedFiltered = series.where((s) => s.title.toLowerCase().contains(widget.query.toLowerCase())).toList();
    return _cachedFiltered!;
  }

  List<ComicSeries> _sortSeries(List<ComicSeries> series) {
    final sorted = List<ComicSeries>.from(series);
    int cmp(int v) => widget.sortAscending ? v : -v;
    switch (widget.sortMode) {
      case SortMode.title:
        sorted.sort((a, b) => cmp(a.title.toLowerCase().compareTo(b.title.toLowerCase())));
      case SortMode.modifiedTime:
        sorted.sort((a, b) {
          final ma = a.folderPath != null ? _modifiedCache[a.folderPath!] : null;
          final mb = b.folderPath != null ? _modifiedCache[b.folderPath!] : null;
          if (ma == null && mb == null) return 0;
          if (ma == null) return widget.sortAscending ? 1 : -1;
          if (mb == null) return widget.sortAscending ? -1 : 1;
          return cmp(ma.compareTo(mb));
        });
      case SortMode.addedTime:
        sorted.sort((a, b) => cmp(a.createdAt.compareTo(b.createdAt)));
      case SortMode.lastOpenedTime:
        sorted.sort((a, b) {
          if (a.lastReadAt == null && b.lastReadAt == null) return 0;
          if (a.lastReadAt == null) return widget.sortAscending ? 1 : -1;
          if (b.lastReadAt == null) return widget.sortAscending ? -1 : 1;
          return cmp(a.lastReadAt!.compareTo(b.lastReadAt!));
        });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<bool>(
      future: _showEntryFuture,
      builder: (context, settingSnapshot) {
        final showEntry = settingSnapshot.data ?? false;
        return Consumer<ComicSeriesProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CupertinoActivityIndicator());
            }

            if (provider.series.length != _lastSeriesCount) {
              _lastSeriesCount = provider.series.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _refreshModifiedCache(provider.series);
              });
            }

            final filtered = _sortSeries(_filterSeries(provider.series));

            if (filtered.isEmpty) {
              return widget.query.isNotEmpty
                  ? Center(child: Text('没有找到匹配的内容', style: TextStyle(color: NeutralPalette.of(context).textTertiary)))
                  : _buildEmptyState(showEntry);
            }

            final bottomPad = MediaQuery.paddingOf(context).bottom + (widget.selectionMode ? 80 : 0);
            final hasContinue = widget.continueItems.isNotEmpty && !widget.selectionMode && widget.query.isEmpty;

            return RefreshIndicator(
              onRefresh: () => context.read<ComicSeriesProvider>().loadSeries(),
              child: CustomScrollView(
                cacheExtent: 200.0,
                slivers: [
                  if (hasContinue)
                    SliverToBoxAdapter(
                      child: _ComicContinueSection(
                        seriesList: widget.continueItems,
                        onTap: (series) => widget.onTapSeries(series),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, hasContinue ? 8 : 20, 20, bottomPad),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.50,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: filtered.length + (widget.selectionMode || !showEntry ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (!widget.selectionMode && showEntry && index == 0) {
                          return _AddButton(type: MediaType.comic);
                        }
                        final series = filtered[index - (!widget.selectionMode && showEntry ? 1 : 0)];
                        final isSelected = series.id != null && widget.selectedIds.contains(series.id);
                        return _SeriesCard(
                          series: series,
                          selectionMode: widget.selectionMode,
                          isSelected: isSelected,
                          isCloud: series.folderPath != null && widget.cloudPaths.contains(series.folderPath),
                          onTap: () {
                            if (widget.selectionMode) {
                              if (series.id != null) widget.onToggleSelect(series.id!);
                            } else {
                              widget.onTapSeries(series);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(bool showEntry) {
    final size = MediaQuery.of(context).size;
    final itemWidth = (size.width - 20 - 20 - 24) / 3;
    return RefreshIndicator(
      onRefresh: () => context.read<ComicSeriesProvider>().loadSeries(),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showEntry)
                  SizedBox(
                    width: itemWidth,
                    child: _AddButton(type: MediaType.comic),
                  ),
                if (showEntry) const SizedBox(height: 40),
                const EmptyState(
                  icon: CupertinoIcons.photo_on_rectangle,
                  title: '还没有漫画系列',
                  subtitle: '点击右上角 + 按钮导入漫画',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final ComicSeries series;
  final bool selectionMode;
  final bool isSelected;
  final bool isCloud;
  final VoidCallback onTap;

  const _SeriesCard({
    required this.series,
    required this.onTap,
    this.selectionMode = false,
    this.isSelected = false,
    this.isCloud = false,
  });

  Future<void> _handleTap(BuildContext context) async {
    if (selectionMode) {
      onTap();
      return;
    }
    if (series.isPrivate && !PrivacyService.instance.isUnlocked) {
      final unlocked = await PrivacyService.instance.unlock();
      if (!unlocked) return;
    }
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPrivate = series.isPrivate;
    final progress = series.totalChapters > 0
        ? series.readChapters / series.totalChapters
        : 0.0;
    return Pressable(
      onTap: () => _handleTap(context),
      onLongPress: () => _showOptions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                boxShadow: isDark
                    ? null
                    : [
                        AppShadows.ambient,
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildCover(neutral)),
                    // 私密角标（左上角）
                    if (isPrivate)
                      const Positioned(
                        top: 6,
                        left: 6,
                        child: StatusBadge.lock(),
                      ),
                    // 云端角标（右上角）
                    if (isCloud && !isPrivate)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: StatusBadge.cloudOnly(),
                      ),
                    // 底部进度条
                    if (progress > 0 && progress < 1.0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: CoverProgressBar(progress: progress),
                      ),
                    if (selectionMode)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.black.withOpacity(0.3) : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                          ),
                          alignment: Alignment.topRight,
                          padding: const EdgeInsets.all(AppSpacing.s8),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.85),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : neutral.textTertiary,
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 14)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: neutral.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${series.readChapters} / ${series.totalChapters} 章节',
            style: TextStyle(
              fontSize: 11,
              color: neutral.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCover(NeutralPalette neutral) {
    if (series.coverPath != null) {
      return Image.file(
        File(series.coverPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => _defaultCover(neutral),
      );
    }
    return _defaultCover(neutral);
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(
          CupertinoIcons.photo,
          color: neutral.textTertiary,
          size: 32,
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    final currentGroup = series.tags
        .firstWhere((t) => t.startsWith('分组:'), orElse: () => '')
        .replaceFirst('分组:', '');
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(series.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              if (series.id != null) {
                await context.read<ComicSeriesProvider>().toggleFavorite(series.id!);
              }
            },
            child: Text(series.isFavorite ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              if (series.id != null) {
                await context.read<ComicSeriesProvider>().setSeriesPrivate(series.id!, !series.isPrivate);
              }
            },
            child: Text(series.isPrivate ? '取消私密' : '设为私密'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showGroupDialog(context, currentGroup);
            },
            child: const Text('设置分组'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showMoveSheet(context);
            },
            child: const Text('移动到'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickCover(context);
            },
            child: const Text('更换封面'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showEditDialog(context);
            },
            child: const Text('编辑信息'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () async {
            final confirm = await showCupertinoDialog<bool>(
              context: context,
              builder: (context) => CupertinoAlertDialog(
                title: const Text('确认删除'),
                content: const Text('删除后将无法恢复，是否继续？'),
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
            if (confirm == true && context.mounted && series.id != null) {
              await context.read<ComicSeriesProvider>().deleteSeries(series.id!);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('删除'),
        ),
      ),
    );
  }

  void _showGroupDialog(BuildContext context, String currentGroup) {
    final controller = TextEditingController(text: currentGroup);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('设置分组'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '输入分组名（留空=移出分组）',
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: NeutralPalette.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              if (series.id != null) {
                await context.read<ComicSeriesProvider>().setSeriesGroup(
                  series.id!,
                  controller.text.trim(),
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showMoveSheet(BuildContext context) {
    final targets = MediaType.values.where((t) => t != MediaType.comic).toList();
    // 提前保存引用，避免 async 后 context 失效
    final comicProvider = context.read<ComicSeriesProvider>();
    final libraryProvider = context.read<LibraryProvider>();
    showCupertinoModalPopup(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: const Text('移动到'),
        actions: targets.map((type) {
          return CupertinoActionSheetAction(
            onPressed: () async {
              await comicProvider.moveSeriesToType(series.id!, type);
              await libraryProvider.loadLibrary();
              if (modalContext.mounted) Navigator.pop(modalContext);
            },
            child: Text(_mediaTypeName(type)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(modalContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _pickCover(BuildContext context) async {
    final seriesId = series.id;
    if (seriesId == null) return;

    // 提前保存引用，避免 async 后 context 失效
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<ComicSeriesProvider>();

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('未选择图片'), duration: Duration(seconds: 1)),
        );
        return;
      }
      final bytes = await image.readAsBytes();
      final coverPath = await CoverService.instance.saveCustomCover(bytes, series.title);
      if (coverPath == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('封面保存失败'), duration: Duration(seconds: 2)),
        );
        return;
      }

      await provider.changeCover(seriesId, coverPath);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('封面更换成功'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      debugPrint('更换封面失败: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('封面更换失败: $e'), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _showEditDialog(BuildContext context) {
    final titleController = TextEditingController(text: series.title);
    final authorController = TextEditingController(text: series.author ?? '');
    final descController = TextEditingController(text: series.description ?? '');

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑信息'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: titleController,
              placeholder: '标题',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: authorController,
              placeholder: '作者',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: descController,
              placeholder: '简介',
              padding: const EdgeInsets.all(AppSpacing.s12),
              maxLines: 3,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              if (series.id != null) {
                await context.read<ComicSeriesProvider>().updateSeriesInfo(
                  series.id!,
                  title: titleController.text.isEmpty ? null : titleController.text,
                  author: authorController.text.isEmpty ? null : authorController.text,
                  description: descController.text.isEmpty ? null : descController.text,
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      titleController.dispose();
      authorController.dispose();
      descController.dispose();
    });
  }
}

class _MediaGrid extends StatefulWidget {
  final List<LibraryItem> items;
  final MediaType type;
  final String query;
  final bool selectionMode;
  final Set<int> selectedIds;
  final void Function(int id) onToggleSelect;
  final void Function(int id) onLongPressStartSelection;
  final SortMode sortMode;
  final bool sortAscending;
  final List<LibraryItem> continueItems;
  final Set<String> cloudPaths;

  const _MediaGrid({
    required this.items,
    required this.type,
    this.query = '',
    this.selectionMode = false,
    this.selectedIds = const {},
    required this.onToggleSelect,
    required this.onLongPressStartSelection,
    this.sortMode = SortMode.title,
    this.sortAscending = true,
    this.continueItems = const [],
    this.cloudPaths = const {},
  });

  @override
  State<_MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<_MediaGrid>
    with AutomaticKeepAliveClientMixin {
  late Future<bool> _showEntryFuture;
  List<LibraryItem>? _cachedFiltered;
  String _cachedQuery = '';
  List<LibraryItem> _cachedItems = [];
  Map<String, DateTime> _modTimeCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _showEntryFuture = FolderSettingsService.instance.getShowImportEntry(widget.type);
    _preloadModTimes();
  }

  @override
  void didUpdateWidget(covariant _MediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length ||
        widget.items.map((i) => i.id).join(',') !=
            oldWidget.items.map((i) => i.id).join(',')) {
      _preloadModTimes();
    }
  }

  Future<void> _preloadModTimes() async {
    final cache = <String, DateTime>{};
    for (final item in widget.items) {
      try {
        cache[item.filePath] = await File(item.filePath).lastModified();
      } catch (_) {}
    }
    if (mounted) setState(() => _modTimeCache = cache);
  }

  List<LibraryItem> get _filteredItems {
    if (widget.query.isEmpty) return widget.items;
    if (_cachedFiltered != null &&
        _cachedQuery == widget.query &&
        _cachedItems.length == widget.items.length &&
        _cachedItems.every((i) => widget.items.contains(i))) {
      return _cachedFiltered!;
    }
    _cachedQuery = widget.query;
    _cachedItems = List.from(widget.items);
    _cachedFiltered = widget.items.where((item) {
      return item.title.toLowerCase().contains(widget.query) ||
          (item.author?.toLowerCase().contains(widget.query) ?? false);
    }).toList();
    return _cachedFiltered!;
  }

  List<LibraryItem> _sortItems(List<LibraryItem> items) {
    final sorted = List<LibraryItem>.from(items);
    int cmp(int v) => widget.sortAscending ? v : -v;
    switch (widget.sortMode) {
      case SortMode.title:
        sorted.sort((a, b) => cmp(a.title.toLowerCase().compareTo(b.title.toLowerCase())));
      case SortMode.modifiedTime:
        sorted.sort((a, b) {
          final ma = _modTimeCache[a.filePath];
          final mb = _modTimeCache[b.filePath];
          if (ma == null && mb == null) return 0;
          if (ma == null) return widget.sortAscending ? 1 : -1;
          if (mb == null) return widget.sortAscending ? -1 : 1;
          return cmp(ma.compareTo(mb));
        });
      case SortMode.addedTime:
        sorted.sort((a, b) => cmp(a.addedDate.compareTo(b.addedDate)));
      case SortMode.lastOpenedTime:
        sorted.sort((a, b) {
          if (a.lastOpenedDate == null && b.lastOpenedDate == null) return 0;
          if (a.lastOpenedDate == null) return widget.sortAscending ? 1 : -1;
          if (b.lastOpenedDate == null) return widget.sortAscending ? -1 : 1;
          return cmp(a.lastOpenedDate!.compareTo(b.lastOpenedDate!));
        });
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<bool>(
      future: _showEntryFuture,
      builder: (context, snapshot) {
        final showEntry = snapshot.data ?? false;
        final filtered = _sortItems(_filteredItems);
        if (filtered.isEmpty) {
          return widget.query.isNotEmpty
              ? Center(child: Text('没有找到匹配的内容', style: TextStyle(color: NeutralPalette.of(context).textTertiary)))
              : _buildEmptyState(context, showEntry);
        }

        final bottomPad = MediaQuery.paddingOf(context).bottom + (widget.selectionMode ? 80 : 20);
        final hasContinue = widget.continueItems.isNotEmpty && !widget.selectionMode && widget.query.isEmpty;

        return RefreshIndicator(
          onRefresh: () => context.read<LibraryProvider>().loadLibrary(),
          child: CustomScrollView(
            cacheExtent: 200.0,
            slivers: [
              if (hasContinue)
                SliverToBoxAdapter(
                  child: _NovelContinueSection(
                    items: widget.continueItems,
                    onTap: (item) => _openReader(context, item),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, hasContinue ? 8 : 20, 20, bottomPad),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.50,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filtered.length + (widget.selectionMode || !showEntry ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (!widget.selectionMode && showEntry && index == 0) {
                      return _AddButton(type: widget.type);
                    }
                    final item = filtered[index - (!widget.selectionMode && showEntry ? 1 : 0)];
                    final isSelected = item.id != null && widget.selectedIds.contains(item.id);
                    final listIndex = index - (!widget.selectionMode && showEntry ? 1 : 0);
                    return AnimatedListItem(
                      index: listIndex,
                      child: _BookCard(
                        item: item,
                        selectionMode: widget.selectionMode,
                        isSelected: isSelected,
                        isCloud: widget.cloudPaths.contains(item.filePath),
                        onToggleSelect: () {
                          if (item.id != null) widget.onToggleSelect(item.id!);
                        },
                        onStartSelection: () {
                          if (item.id != null) widget.onLongPressStartSelection(item.id!);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool showEntry) {
    final size = MediaQuery.of(context).size;
    final itemWidth = (size.width - 20 - 20 - 24) / 3;
    return RefreshIndicator(
      onRefresh: () => context.read<LibraryProvider>().loadLibrary(),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showEntry)
                  SizedBox(
                    width: itemWidth,
                    child: _AddButton(type: widget.type),
                  ),
                if (showEntry) const SizedBox(height: 40),
                EmptyState(
                  icon: _getEmptyIcon(),
                  title: '还没有${_getTypeName()}',
                  subtitle: showEntry
                      ? '点击上方按钮导入${_getTypeName()}'
                      : '点击右上角 + 按钮导入${_getTypeName()}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getEmptyIcon() {
    switch (widget.type) {
      case MediaType.novel:
        return CupertinoIcons.book;
      case MediaType.comic:
        return CupertinoIcons.photo_on_rectangle;
      case MediaType.video:
        return CupertinoIcons.film;
      case MediaType.music:
        return CupertinoIcons.music_note;
    }
  }

  String _getTypeName() {
    switch (widget.type) {
      case MediaType.novel:
        return '小说';
      case MediaType.comic:
        return '漫画';
      case MediaType.video:
        return '视频';
      case MediaType.music:
        return '音乐';
    }
  }
}

class _BookCard extends StatelessWidget {
  final LibraryItem item;
  final bool selectionMode;
  final bool isSelected;
  final bool isCloud;
  final VoidCallback onToggleSelect;
  final VoidCallback onStartSelection;

  const _BookCard({
    required this.item,
    this.selectionMode = false,
    this.isSelected = false,
    this.isCloud = false,
    required this.onToggleSelect,
    required this.onStartSelection,
  });

  Future<void> _handleTap(BuildContext context) async {
    if (item.isPrivate && !PrivacyService.instance.isUnlocked) {
      final unlocked = await PrivacyService.instance.unlock();
      if (!unlocked) return;
    }
    _openReader(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPrivate = item.isPrivate;
    return Pressable(
      onTap: () {
        if (selectionMode) {
          onToggleSelect();
        } else {
          _handleTap(context);
        }
      },
      onLongPress: () => _showOptions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Hero(
              tag: 'cover_${item.id}',
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        boxShadow: isDark
                            ? null
                            : [
                                AppShadows.ambient,
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        child: _buildCover(neutral),
                      ),
                    ),
                  ),
                  // 私密角标（左上角）
                  if (isPrivate)
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: StatusBadge.lock(),
                    ),
                  // 云端角标（右上角）
                  if (item.sourceType != null && item.sourceType != 'local' && !isPrivate)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: SourceBadge(
                        sourceType: item.sourceType,
                        isDownloaded: isCloud,
                      ),
                    ),
                  if (item.mediaType == MediaType.video)
                    _buildVideoBadge(),
                  // 底部进度条
                  if ((item.totalProgress ?? 0) > 0 && (item.totalProgress ?? 0) < 100)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: CoverProgressBar(
                        progress: (item.totalProgress ?? 0) / 100,
                      ),
                    ),
                  if (selectionMode)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.black.withOpacity(0.3) : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                        ),
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.all(AppSpacing.s8),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.85),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : neutral.textTertiary,
                              width: 1.5,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 14)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: neutral.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.author != null)
            Text(
              item.author!,
              style: TextStyle(
                fontSize: 11,
                color: neutral.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildCover(NeutralPalette neutral) {
    // 优先使用远程封面 URL
    if (item.remoteCoverUrl != null) {
      return Image.network(
        item.remoteCoverUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _fallbackLocalCover(neutral),
      );
    }
    return _fallbackLocalCover(neutral);
  }

  Widget _fallbackLocalCover(NeutralPalette neutral) {
    if (item.coverPath != null) {
      return Image.file(
        File(item.coverPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => _defaultCover(neutral),
      );
    }
    return _defaultCover(neutral);
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(
          _getIcon(),
          color: neutral.textTertiary,
          size: 32,
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (item.mediaType) {
      case MediaType.novel:
        return CupertinoIcons.book;
      case MediaType.comic:
        return CupertinoIcons.photo;
      case MediaType.video:
        return CupertinoIcons.play_circle;
      case MediaType.music:
        return CupertinoIcons.music_note;
    }
  }

  void _showOptions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: Text(item.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              modalContext.read<LibraryProvider>().toggleFavorite(item.id!);
              Navigator.pop(modalContext);
            },
            child: Text(item.isFavorite ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              modalContext.read<LibraryProvider>().setItemsPrivate([item.id!], !item.isPrivate);
              Navigator.pop(modalContext);
            },
            child: Text(item.isPrivate ? '取消私密' : '设为私密'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(modalContext);
              _showMoveSheet(context);
            },
            child: const Text('移动到'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(modalContext);
              await context.read<LibraryProvider>().changeCover(item.id!);
            },
            child: const Text('更换封面'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(modalContext);
              _showEditDialog(context);
            },
            child: const Text('编辑信息'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () async {
            final confirm = await showCupertinoDialog<bool>(
              context: modalContext,
              builder: (dialogContext) => CupertinoAlertDialog(
                title: const Text('确认删除'),
                content: const Text('删除后将无法恢复，是否继续？'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (confirm == true && modalContext.mounted) {
              await modalContext.read<LibraryProvider>().deleteItem(item.id!);
            }
            if (modalContext.mounted) Navigator.pop(modalContext);
          },
          child: const Text('删除'),
        ),
      ),
    );
  }

  void _showMoveSheet(BuildContext context) {
    final targets = MediaType.values.where((t) => t != item.mediaType).toList();
    showCupertinoModalPopup(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: const Text('移动到'),
        actions: targets.map((type) {
          return CupertinoActionSheetAction(
            onPressed: () async {
              await context.read<LibraryProvider>().moveItemToType(item.id!, type);
              if (type == MediaType.comic) {
                await context.read<ComicSeriesProvider>().loadSeries();
              }
              if (modalContext.mounted) Navigator.pop(modalContext);
            },
            child: Text(_mediaTypeName(type)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(modalContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final titleController = TextEditingController(text: item.title);
    final authorController = TextEditingController(text: item.author ?? '');
    final descController = TextEditingController(text: item.description ?? '');

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑信息'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: titleController,
              placeholder: '标题',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: authorController,
              placeholder: '作者',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: descController,
              placeholder: '简介',
              padding: const EdgeInsets.all(AppSpacing.s12),
              maxLines: 3,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              await context.read<LibraryProvider>().updateItemInfo(
                item.id!,
                title: titleController.text.isEmpty ? null : titleController.text,
                author: authorController.text.isEmpty ? null : authorController.text,
                description: descController.text.isEmpty ? null : descController.text,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      titleController.dispose();
      authorController.dispose();
      descController.dispose();
    });
  }

  Widget _buildVideoBadge() {
    final result = VideoFilenameParser.parse(item.filePath);
    if (!result.hasEpisodeInfo) return const SizedBox.shrink();
    return Positioned(
      bottom: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          result.displayLabel,
          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

}

class _AddButton extends StatelessWidget {
  final MediaType type;

  const _AddButton({required this.type});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: () async {
        await context.read<LibraryProvider>().importFilesWithType(type);
        if (type == MediaType.comic) {
          await context.read<ComicSeriesProvider>().loadSeries();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 2,
                ),
                color: isDark ? AppColors.primary.withOpacity(0.15) : AppColors.primary.withOpacity(0.05),
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.add,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: NeutralPalette.of(context).textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SelectionBottomBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final VoidCallback onDelete;
  final VoidCallback onTogglePrivate;
  final VoidCallback onGroup;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onMerge;
  final VoidCallback? onMove;

  const _SelectionBottomBar({
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClearAll,
    required this.onDelete,
    required this.onTogglePrivate,
    required this.onGroup,
    required this.onToggleFavorite,
    this.onMerge,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = selectedCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: neutral.surface,
        boxShadow: isDark
            ? null
            : [
                AppShadows.ambient,
              ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Text(
                    '已选 $selectedCount 项',
                    style: TextStyle(fontSize: 13, color: neutral.textTertiary),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: allSelected ? onClearAll : onSelectAll,
                    child: Text(
                      allSelected ? '取消全选' : '全选',
                      style: const TextStyle(fontSize: 14, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (onMerge != null)
                    _BarButton(
                      icon: CupertinoIcons.arrow_merge,
                      label: '合并',
                      enabled: hasSelection && selectedCount >= 2,
                      onTap: onMerge!,
                    ),
                  if (onMove != null)
                    _BarButton(
                      icon: CupertinoIcons.arrow_right_circle,
                      label: '移动',
                      enabled: hasSelection,
                      onTap: onMove!,
                    ),
                  _BarButton(
                    icon: CupertinoIcons.folder,
                    label: '分组',
                    enabled: hasSelection,
                    onTap: onGroup,
                  ),
                  _BarButton(
                    icon: CupertinoIcons.lock,
                    label: '私密',
                    enabled: hasSelection,
                    onTap: onTogglePrivate,
                  ),
                  _BarButton(
                    icon: CupertinoIcons.heart,
                    label: '收藏',
                    enabled: hasSelection,
                    onTap: onToggleFavorite,
                  ),
                  _BarButton(
                    icon: CupertinoIcons.delete,
                    label: '删除',
                    enabled: hasSelection,
                    isDestructive: true,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDestructive;
  final VoidCallback onTap;

  const _BarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final color = !enabled
        ? neutral.textTertiary
        : (isDestructive ? FunctionalColors.error : neutral.textPrimary);
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

// ===================== 书架 P0 UI 组件 =====================

/// 封面底部琥珀色进度条（3pt 高）
/// 小说继续阅读横向列表
class _NovelContinueSection extends StatelessWidget {
  final List<LibraryItem> items;
  final void Function(LibraryItem item) onTap;

  const _NovelContinueSection({
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '继续阅读',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: neutral.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final progress = (item.totalProgress ?? 0) / 100;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Pressable(
                  onTap: () => onTap(item),
                  child: SizedBox(
                    width: 90,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.medium),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _buildNetworkOrLocalCover(
                                    remoteUrl: item.remoteCoverUrl,
                                    localPath: item.coverPath,
                                    neutral: neutral,
                                  ),
                                ),
                                if (item.isPrivate)
                                  const Positioned(
                                    top: 4,
                                    left: 4,
                                    child: StatusBadge.lock(),
                                  ),
                                if (progress > 0 && progress < 1)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: CoverProgressBar(progress: progress),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: neutral.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '已读 ${(progress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: neutral.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(CupertinoIcons.book, color: neutral.textTertiary, size: 24),
      ),
    );
  }
}

/// 漫画继续阅读横向列表
class _ComicContinueSection extends StatelessWidget {
  final List<ComicSeries> seriesList;
  final void Function(ComicSeries series) onTap;

  const _ComicContinueSection({
    required this.seriesList,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '继续阅读',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: neutral.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: seriesList.length,
            itemBuilder: (context, index) {
              final series = seriesList[index];
              final progress = series.totalChapters > 0
                  ? series.readChapters / series.totalChapters
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Pressable(
                  onTap: () => onTap(series),
                  child: SizedBox(
                    width: 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.medium),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: series.coverPath != null
                                      ? Image.file(
                                          File(series.coverPath!),
                                          fit: BoxFit.cover,
                                          cacheWidth: 300,
                                          errorBuilder: (_, __, ___) => _defaultCover(neutral),
                                        )
                                      : _defaultCover(neutral),
                                ),
                                if (series.isPrivate)
                                  const Positioned(
                                    top: 4,
                                    left: 4,
                                    child: StatusBadge.lock(),
                                  ),
                                if (progress > 0 && progress < 1)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: CoverProgressBar(progress: progress),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          series.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: neutral.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${series.readChapters} / ${series.totalChapters} 话',
                          style: TextStyle(
                            fontSize: 11,
                            color: neutral.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(CupertinoIcons.photo, color: neutral.textTertiary, size: 24),
      ),
    );
  }
}

/// 通用封面构建：优先网络 URL，其次本地文件，最后默认占位
Widget _buildNetworkOrLocalCover({
  String? remoteUrl,
  String? localPath,
  required NeutralPalette neutral,
  int? cacheWidth,
}) {
  if (remoteUrl != null) {
    return Image.network(
      remoteUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _buildLocalOrDefaultCover(
        localPath: localPath,
        neutral: neutral,
        cacheWidth: cacheWidth,
      ),
    );
  }
  return _buildLocalOrDefaultCover(
    localPath: localPath,
    neutral: neutral,
    cacheWidth: cacheWidth,
  );
}

Widget _buildLocalOrDefaultCover({
  String? localPath,
  required NeutralPalette neutral,
  int? cacheWidth,
}) {
  if (localPath != null) {
    return Image.file(
      File(localPath),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheWidth ?? 400,
      errorBuilder: (_, __, ___) => _defaultCoverWidget(neutral),
    );
  }
  return _defaultCoverWidget(neutral);
}

Widget _defaultCoverWidget(NeutralPalette neutral) {
  return Container(
    color: neutral.surfaceElevated,
    child: Center(
      child: Icon(CupertinoIcons.photo, color: neutral.textTertiary, size: 24),
    ),
  );
}
