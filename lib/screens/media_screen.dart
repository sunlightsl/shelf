import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import '../providers/library_provider.dart';
import '../providers/comic_series_provider.dart';
import '../services/folder_settings_service.dart';
import '../services/music_scan_service.dart';
import '../services/music_player_service.dart';
import '../database/song_dao.dart';
import '../database/library_dao.dart';
import '../widgets/empty_state.dart';
import '../widgets/pressable.dart';
import '../widgets/cover_badges.dart';
import '../database/offline_cache_dao.dart';
import 'video_detail_screen.dart';
import '../services/video_filename_parser.dart';
import 'media/music/music_library_view.dart';
import 'media/music/music_player_screen.dart';

void _openMedia(BuildContext context, LibraryItem item) {
  switch (item.mediaType) {
    case MediaType.video:
      Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => VideoDetailScreen(item: item)),
      );
      break;
    case MediaType.music:
      _playMusic(context, item);
      break;
    default:
      return;
  }
}

Future<void> _playMusic(BuildContext context, LibraryItem item) async {
  // 确保音乐数据已同步到 songs 表
  await MusicScanService.instance.syncFromLibrary();
  final songs = await SongDao().getAllSongs();
  if (songs.isEmpty) return;

  final targetSong = songs.firstWhere(
    (s) => s.filePath == item.filePath,
    orElse: () => songs.first,
  );

  final service = MusicPlayerService.instance;
  await service.setQueue(songs);
  await service.playSong(targetSong);

  if (context.mounted && !MusicPlayerScreen.isOpen) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MusicPlayerScreen(),
      ),
    );
  }
}

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  SortMode _sortMode = SortMode.title;
  bool _sortAscending = true;

  // 云端已下载的 filePath 集合
  Set<String> _cloudFilePaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCloudPaths();
    // 同步音乐数据到 songs 表
    _initMusicSync();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _selectionMode) {
        setState(() => _selectedIds.clear());
      }
      if (!_tabController.indexIsChanging && _tabController.index == 1) {
        MusicLibraryView.globalKey.currentState?.refresh();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initMusicSync() async {
    try {
      await MusicScanService.instance.syncFromLibrary();
    } catch (e) {
      debugPrint('初始音乐同步失败: $e');
    }
  }

  Future<void> _loadCloudPaths() async {
    try {
      final paths = await OfflineCacheDao().getAllFilePaths();
      if (mounted) setState(() => _cloudFilePaths = paths);
    } catch (e) {
      debugPrint('[MediaScreen] 加载云端路径失败: $e');
    }
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
    MusicLibraryView.globalKey.currentState?.clearAll();
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
              context.read<LibraryProvider>().importFilesWithType(MediaType.video);
            },
            child: const Text('导入视频'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              context.read<LibraryProvider>().importFilesWithType(MediaType.music);
            },
            child: const Text('导入音乐'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
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

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAllInCurrentTab(List<LibraryItem> items) {
    setState(() {
      for (final item in items) {
        if (item.id != null) _selectedIds.add(item.id!);
      }
    });
  }

  Future<void> _batchDelete() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_tabController.index == 1) {
      final musicViewState = MusicLibraryView.globalKey.currentState;
      final selectedSongIds = musicViewState?.selectedSongIds ?? {};
      if (selectedSongIds.isEmpty) return;
      final confirm = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text('确认删除', style: TextStyle(color: NeutralPalette.of(context).textPrimary)),
          content: Text(
            '确定删除选中的 ${selectedSongIds.length} 首歌曲？删除后可在回收站找回。',
            style: TextStyle(color: NeutralPalette.of(context).textSecondary),
          ),
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
      if (confirm != true || !mounted) return;
      final songs = musicViewState?.songs ?? [];
      for (final song in songs) {
        if (song.id != null && selectedSongIds.contains(song.id)) {
          final libraryItem = await LibraryDao().getItemByPath(song.filePath);
          if (libraryItem?.id != null) {
            await LibraryDao().deleteItem(libraryItem!.id!);
          }
        }
      }
      await musicViewState?.refresh();
      await context.read<LibraryProvider>().loadLibrary();
      if (mounted) {
        _exitSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '已移至回收站，可在回收站中找回',
              style: TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralPalette.of(context).surfaceElevated,
          ),
        );
      }
      return;
    }

    if (_selectedIds.isEmpty) return;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('确认删除', style: TextStyle(color: NeutralPalette.of(context).textPrimary)),
        content: Text(
          '确定删除选中的 ${_selectedIds.length} 项？删除后可在回收站找回。',
          style: TextStyle(color: NeutralPalette.of(context).textSecondary),
        ),
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
    if (confirm != true || !mounted) return;
    await context.read<LibraryProvider>().deleteItems(_selectedIds.toList());
    if (mounted) {
      _exitSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '已移至回收站，可在回收站中找回',
            style: TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: NeutralPalette.of(context).surfaceElevated,
        ),
      );
    }
  }

  Future<void> _batchToggleFavorite() async {
    if (_tabController.index == 1) {
      final musicViewState = MusicLibraryView.globalKey.currentState;
      final selectedSongIds = musicViewState?.selectedSongIds ?? {};
      if (selectedSongIds.isEmpty) return;
      final dao = SongDao();
      bool allFavorited = true;
      for (final id in selectedSongIds) {
        if (!await dao.isFavorite(id)) {
          allFavorited = false;
          break;
        }
      }
      for (final id in selectedSongIds) {
        final isFav = await dao.isFavorite(id);
        if (allFavorited) {
          if (isFav) await dao.toggleFavorite(id);
        } else {
          if (!isFav) await dao.toggleFavorite(id);
        }
      }
      await musicViewState?.refresh();
      if (mounted) _exitSelection();
      return;
    }

    if (_selectedIds.isEmpty) return;
    final provider = context.read<LibraryProvider>();
    final selectedItems = provider.allItems.where((i) => _selectedIds.contains(i.id)).toList();
    final allFavorited = selectedItems.every((i) => i.isFavorite);
    await provider.setItemsFavorite(_selectedIds.toList(), !allFavorited);
    if (mounted) _exitSelection();
  }

  List<LibraryItem> _currentTabItems(LibraryProvider provider) {
    return _tabController.index == 0 ? provider.videos : provider.musics;
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
            // 固定头部：标题 + 选择按钮
            Padding(
              padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    '影音',
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
            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                placeholder: '搜索视频、音乐',
                style: const TextStyle(fontSize: 15),
              ),
            ),
            // 分类 TabBar
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
                        ? null
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
                    Tab(text: '视频'),
                    Tab(text: '音乐'),
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
                      _VideoLibraryGrid(
                        items: provider.videos,
                        query: _searchQuery,
                        selectionMode: _selectionMode,
                        selectedIds: _selectedIds,
                        onToggleSelect: _toggleSelect,
                        sortMode: _sortMode,
                        sortAscending: _sortAscending,
                        cloudPaths: _cloudFilePaths,
                      ),
                      MusicLibraryView(
                        key: MusicLibraryView.globalKey,
                        searchQuery: _searchQuery,
                        selectionMode: _selectionMode,
                        sortMode: _sortMode,
                        sortAscending: _sortAscending,
                        cloudPaths: _cloudFilePaths,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        // 底部选择操作栏
        if (_selectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer<LibraryProvider>(
              builder: (context, provider, _) {
                if (_tabController.index == 1) {
                  final musicViewState = MusicLibraryView.globalKey.currentState;
                  final songs = musicViewState?.songs ?? [];
                  final selectedCount = musicViewState?.selectedCount ?? 0;
                  final allSelected = songs.isNotEmpty &&
                      songs.every((s) => s.id != null && (musicViewState?.selectedSongIds.contains(s.id) ?? false));
                  return _MediaSelectionBottomBar(
                    selectedCount: selectedCount,
                    totalCount: songs.length,
                    allSelected: allSelected,
                    onSelectAll: () => musicViewState?.selectAll(),
                    onClearAll: () => musicViewState?.clearAll(),
                    onDelete: _batchDelete,
                    onToggleFavorite: _batchToggleFavorite,
                  );
                }
                final items = _currentTabItems(provider);
                final filtered = _searchQuery.isEmpty
                    ? items
                    : items.where((item) {
                        return item.title.toLowerCase().contains(_searchQuery) ||
                            (item.author?.toLowerCase().contains(_searchQuery) ?? false);
                      }).toList();
                return _MediaSelectionBottomBar(
                  selectedCount: _selectedIds.length,
                  totalCount: filtered.length,
                  allSelected: filtered.isNotEmpty &&
                      filtered.every((i) => i.id != null && _selectedIds.contains(i.id)),
                  onSelectAll: () => _selectAllInCurrentTab(filtered),
                  onClearAll: () => setState(() => _selectedIds.clear()),
                  onDelete: _batchDelete,
                  onToggleFavorite: _batchToggleFavorite,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _MediaGrid extends StatefulWidget {
  final List<LibraryItem> items;
  final MediaType type;
  final String query;
  final bool selectionMode;
  final Set<int> selectedIds;
  final void Function(int id) onToggleSelect;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final SortMode sortMode;
  final bool sortAscending;

  const _MediaGrid({
    required this.items,
    required this.type,
    this.query = '',
    this.selectionMode = false,
    this.selectedIds = const {},
    required this.onToggleSelect,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.sortMode = SortMode.title,
    this.sortAscending = true,
  });

  @override
  State<_MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<_MediaGrid>
    with AutomaticKeepAliveClientMixin {
  late Future<bool> _showEntryFuture;
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
    return widget.items.where((item) {
      return item.title.toLowerCase().contains(widget.query) ||
          (item.author?.toLowerCase().contains(widget.query) ?? false);
    }).toList();
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
    final neutral = NeutralPalette.of(context);
    super.build(context);
    return FutureBuilder<bool>(
      future: _showEntryFuture,
      builder: (context, snapshot) {
        final showEntry = snapshot.data ?? false;
        final filtered = _sortItems(_filteredItems);
        if (filtered.isEmpty) {
          return widget.query.isNotEmpty
              ? Center(
                  child: Text(
                    '没有找到匹配的内容',
                    style: TextStyle(color: neutral.textTertiary),
                  ),
                )
              : _buildEmptyState(context, showEntry);
        }

        final bottomPad = MediaQuery.paddingOf(context).bottom + (widget.selectionMode ? 80 : 0);

        return RefreshIndicator(
          onRefresh: () => context.read<LibraryProvider>().loadLibrary(),
          child: GridView.builder(
            cacheExtent: 200.0,
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
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
              return _MediaCard(
                item: item,
                selectionMode: widget.selectionMode,
                isSelected: isSelected,
                onToggleSelect: () {
                  if (item.id != null) widget.onToggleSelect(item.id!);
                },
              );
            },
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
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle,
                  subtitle: showEntry
                      ? '点击上方按钮导入${_typeName()}'
                      : '点击右上角 + 按钮导入${_typeName()}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeName() {
    return switch (widget.type) {
      MediaType.video => '视频',
      MediaType.music => '音乐',
      _ => '',
    };
  }
}

// ===================== 视频剧集分组网格 =====================

class _VideoSeriesGroup {
  final String seriesName;
  final List<LibraryItem> episodes;

  const _VideoSeriesGroup({
    required this.seriesName,
    required this.episodes,
  });

  bool get isStandalone => episodes.length == 1;
  LibraryItem get firstItem => episodes.first;
  String? get coverPath {
    for (final e in episodes) {
      if (e.remoteCoverUrl != null) return e.remoteCoverUrl;
    }
    for (final e in episodes) {
      if (e.coverPath != null) return e.coverPath;
    }
    return null;
  }

  bool get isCloudGroup {
    return episodes.any((e) => e.isCloudSource);
  }

  bool get isDownloaded {
    return episodes.any((e) => e.filePath.startsWith('cloud://'));
  }
}

class _VideoLibraryGrid extends StatefulWidget {
  final List<LibraryItem> items;
  final String query;
  final bool selectionMode;
  final Set<int> selectedIds;
  final void Function(int id) onToggleSelect;
  final SortMode sortMode;
  final bool sortAscending;
  final Set<String> cloudPaths;

  const _VideoLibraryGrid({
    required this.items,
    this.query = '',
    this.selectionMode = false,
    this.selectedIds = const {},
    required this.onToggleSelect,
    this.sortMode = SortMode.title,
    this.sortAscending = true,
    this.cloudPaths = const {},
  });

  @override
  State<_VideoLibraryGrid> createState() => _VideoLibraryGridState();
}

enum _VideoFilter { all, movie, series, unwatched, recent }

class _VideoLibraryGridState extends State<_VideoLibraryGrid>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<bool> _showEntryFuture;
  List<LibraryItem> _upNextItems = [];
  _VideoFilter _filter = _VideoFilter.all;
  Map<int, ReadingProgress> _progressMap = {};

  @override
  void initState() {
    super.initState();
    _showEntryFuture = FolderSettingsService.instance.getShowImportEntry(MediaType.video);
    _loadUpNext();
    _loadVideoProgress();
  }

  @override
  void didUpdateWidget(covariant _VideoLibraryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length ||
        widget.items.map((i) => i.id).join(',') !=
            oldWidget.items.map((i) => i.id).join(',')) {
      _loadVideoProgress();
    }
  }

  Future<void> _loadVideoProgress() async {
    final allIds = widget.items.where((i) => i.id != null).map((i) => i.id!).toList();
    if (allIds.isEmpty) {
      if (mounted) setState(() => _progressMap = {});
      return;
    }
    try {
      final progressList = await LibraryDao().getProgressByItemIds(allIds);
      final map = <int, ReadingProgress>{};
      for (final p in progressList) {
        map[p.itemId] = p;
      }
      if (mounted) setState(() => _progressMap = map);
    } catch (e) {
      debugPrint('[VideoLibrary] 加载进度失败: $e');
    }
  }

  Future<void> _loadUpNext() async {
    try {
      final items = await LibraryDao().getUpNextVideos(limit: 10);
      if (mounted) setState(() => _upNextItems = items);
    } catch (e) {
      debugPrint('[VideoLibrary] 加载 Up Next 失败: $e');
    }
  }

  List<_VideoSeriesGroup> get _groups {
    // 先过滤
    var items = widget.items;
    if (widget.query.isNotEmpty) {
      items = items.where((item) {
        return item.title.toLowerCase().contains(widget.query) ||
            (item.author?.toLowerCase().contains(widget.query) ?? false);
      }).toList();
    }

    // 按系列名分组
    final map = <String, List<LibraryItem>>{};
    for (final item in items) {
      String key;
      if (item.isCloudSource) {
        // 云端条目：用 author（seriesName）或 title 分组
        key = item.author?.trim().isNotEmpty == true ? item.author! : item.title;
      } else {
        final result = VideoFilenameParser.parse(item.filePath);
        final name = result.seriesName.trim();
        key = name.isNotEmpty && result.hasEpisodeInfo ? name : item.title;
      }
      map.putIfAbsent(key, () => []).add(item);
    }

    // 对每个组内的剧集按季、集排序
    for (final episodes in map.values) {
      if (episodes.length > 1) {
        episodes.sort((a, b) {
          final sourceA = a.isCloudSource ? a.title : a.filePath;
          final sourceB = b.isCloudSource ? b.title : b.filePath;
          final pa = VideoFilenameParser.parse(sourceA);
          final pb = VideoFilenameParser.parse(sourceB);
          final sa = pa.seasonNumber ?? 0;
          final sb = pb.seasonNumber ?? 0;
          if (sa != sb) return sa.compareTo(sb);
          final ea = pa.episodeNumber ?? 0;
          final eb = pb.episodeNumber ?? 0;
          return ea.compareTo(eb);
        });
      }
    }

    final groups = map.entries
        .map((e) => _VideoSeriesGroup(seriesName: e.key, episodes: e.value))
        .toList();

    // 排序
    int cmp(int v) => widget.sortAscending ? v : -v;
    switch (widget.sortMode) {
      case SortMode.title:
        groups.sort((a, b) =>
            cmp(a.seriesName.toLowerCase().compareTo(b.seriesName.toLowerCase())));
      case SortMode.modifiedTime:
        groups.sort((a, b) {
          DateTime? ma, mb;
          try {
            ma = File(a.firstItem.filePath).lastModifiedSync();
          } catch (_) {}
          try {
            mb = File(b.firstItem.filePath).lastModifiedSync();
          } catch (_) {}
          if (ma == null && mb == null) return 0;
          if (ma == null) return widget.sortAscending ? 1 : -1;
          if (mb == null) return widget.sortAscending ? -1 : 1;
          return cmp(ma.compareTo(mb));
        });
      case SortMode.addedTime:
        groups.sort((a, b) =>
            cmp(a.firstItem.addedDate.compareTo(b.firstItem.addedDate)));
      case SortMode.lastOpenedTime:
        groups.sort((a, b) {
          if (a.firstItem.lastOpenedDate == null &&
              b.firstItem.lastOpenedDate == null) return 0;
          if (a.firstItem.lastOpenedDate == null) {
            return widget.sortAscending ? 1 : -1;
          }
          if (b.firstItem.lastOpenedDate == null) {
            return widget.sortAscending ? -1 : 1;
          }
          return cmp(
              a.firstItem.lastOpenedDate!.compareTo(b.firstItem.lastOpenedDate!));
        });
    }

    // 分类筛选
    switch (_filter) {
      case _VideoFilter.all:
        break;
      case _VideoFilter.movie:
        groups.removeWhere((g) => g.episodes.length > 1);
      case _VideoFilter.series:
        groups.removeWhere((g) => g.episodes.length == 1);
      case _VideoFilter.unwatched:
        groups.removeWhere((g) => g.firstItem.lastOpenedDate != null);
      case _VideoFilter.recent:
        groups.sort((a, b) => b.firstItem.addedDate.compareTo(a.firstItem.addedDate));
        if (groups.length > 20) groups.removeRange(20, groups.length);
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    super.build(context);

    final groups = _groups;
    if (groups.isEmpty && _upNextItems.isEmpty) {
      return widget.query.isNotEmpty
          ? Center(
              child: Text(
                '没有找到匹配的内容',
                style: TextStyle(color: neutral.textTertiary),
              ),
            )
          : _buildEmptyState(context);
    }

    final bottomPad =
        MediaQuery.paddingOf(context).bottom + (widget.selectionMode ? 80 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<LibraryProvider>().loadLibrary();
        await _loadUpNext();
        await _loadVideoProgress();
      },
      child: CustomScrollView(
        cacheExtent: 200.0,
        slivers: [
          // Up Next 横向列表
          if (_upNextItems.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildUpNextSection(context, neutral),
            ),
          // 筛选标签栏
          SliverToBoxAdapter(
            child: _buildFilterBar(context, neutral),
          ),
          // 网格内容
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad),
            sliver: groups.isEmpty
                ? SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: Center(
                        child: Text(
                          '该分类下暂无内容',
                          style: TextStyle(color: neutral.textTertiary),
                        ),
                      ),
                    ),
                  )
                : SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.48,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final group = groups[index];
                        if (group.isStandalone) {
                          final item = group.firstItem;
                          final isSelected =
                              item.id != null && widget.selectedIds.contains(item.id);
                          return _MediaCard(
                            item: item,
                            progress: item.id != null ? _progressMap[item.id] : null,
                            selectionMode: widget.selectionMode,
                            isSelected: isSelected,
                            isCloud: item.isCloudSource,
                            isDownloaded: widget.cloudPaths.contains(item.filePath),
                            onToggleSelect: () {
                              if (item.id != null) widget.onToggleSelect(item.id!);
                            },
                          );
                        }
                        return _VideoSeriesCard(
                          group: group,
                          progressMap: _progressMap,
                          selectionMode: widget.selectionMode,
                          isSelected: group.episodes.any((e) =>
                              e.id != null && widget.selectedIds.contains(e.id)),
                          isCloud: group.isCloudGroup,
                          isDownloaded: group.episodes.any((e) => widget.cloudPaths.contains(e.filePath)),
                          onToggleSelect: () {
                            for (final e in group.episodes) {
                              if (e.id != null) widget.onToggleSelect(e.id!);
                            }
                          },
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => VideoDetailScreen(
                                  item: group.firstItem,
                                  episodes: group.episodes,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: groups.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Up Next 横向列表：继续观看
  Widget _buildUpNextSection(BuildContext context, NeutralPalette neutral) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '继续观看',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: neutral.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _upNextItems.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = _upNextItems[index];
              return _UpNextCard(
                item: item,
                isCloud: item.isCloudSource,
                isDownloaded: widget.cloudPaths.contains(item.filePath),
                onTap: () => _openMedia(context, item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 分类筛选标签栏
  Widget _buildFilterBar(BuildContext context, NeutralPalette neutral) {
    final filters = <(_VideoFilter, String)>[
      (_VideoFilter.all, '全部'),
      (_VideoFilter.movie, '电影'),
      (_VideoFilter.series, '剧集'),
      (_VideoFilter.unwatched, '未观看'),
      (_VideoFilter.recent, '最近添加'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: filters.map((f) {
          final isActive = _filter == f.$1;
          return CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => _filter = f.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : neutral.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                f.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : neutral.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
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
                FutureBuilder<bool>(
                  future: _showEntryFuture,
                  builder: (context, snapshot) {
                    final showEntry = snapshot.data ?? false;
                    if (!showEntry) return const SizedBox.shrink();
                    return SizedBox(
                      width: itemWidth,
                      child: _AddButton(type: MediaType.video),
                    );
                  },
                ),
                const SizedBox(height: 40),
                EmptyState(
                  icon: CupertinoIcons.film,
                  title: '还没有视频',
                  subtitle: '点击上方按钮导入视频',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoSeriesCard extends StatelessWidget {
  final _VideoSeriesGroup group;
  final Map<int, ReadingProgress> progressMap;
  final bool selectionMode;
  final bool isSelected;
  final bool isCloud;
  final bool isDownloaded;
  final VoidCallback onToggleSelect;
  final VoidCallback onTap;

  const _VideoSeriesCard({
    required this.group,
    this.progressMap = const {},
    this.selectionMode = false,
    this.isSelected = false,
    this.isCloud = false,
    this.isDownloaded = false,
    required this.onToggleSelect,
    required this.onTap,
  });

  // 系列观看进度：取第一个在看（非看完）的集进度
  ReadingProgress? get _seriesProgress {
    for (final ep in group.episodes) {
      if (ep.id == null) continue;
      final p = progressMap[ep.id];
      if (p != null && p.percentage > 0 && p.percentage < 0.95) {
        return p;
      }
    }
    return null;
  }

  bool get _isAllWatched {
    if (group.episodes.isEmpty) return false;
    for (final ep in group.episodes) {
      if (ep.id == null) return false;
      final p = progressMap[ep.id];
      if (p == null || p.percentage < 0.95) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Pressable(
      onTap: () {
        if (selectionMode) {
          onToggleSelect();
        } else {
          onTap();
        }
      },
      onLongPress: selectionMode ? null : () => _showSeriesOptions(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
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
                // 云端角标（右上角）
                if (isCloud)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: SourceBadge(
                      sourceType: group.firstItem.sourceType,
                      isDownloaded: isDownloaded,
                    ),
                  ),
                // 集数角标（如果无云端角标则放右上角，否则放右下角）
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: StatusBadge.episodeCount(count: '${group.episodes.length} 集'),
                ),
                if (selectionMode)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.black.withOpacity(0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(AppSpacing.s8),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.primary
                              : Colors.white.withOpacity(0.85),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : neutral.textTertiary,
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(CupertinoIcons.checkmark,
                                color: Colors.white, size: 14)
                            : null,
                      ),
                    ),
                  ),
                // 全部已看完标记
                if (_isAllWatched)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                // 底部进度条
                if (_seriesProgress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(AppRadius.medium),
                          bottomRight: Radius.circular(AppRadius.medium),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _seriesProgress!.percentage.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(AppRadius.medium),
                              bottomRight: Radius.circular(AppRadius.medium),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            group.seriesName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: neutral.textPrimary,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${group.episodes.length} 集',
            style: TextStyle(
              fontSize: 11,
              color: neutral.textSecondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(NeutralPalette neutral) {
    final tag = 'hero_video_cover_${group.firstItem.filePath.hashCode}';
    final cover = group.coverPath;
    if (cover != null) {
      final isNetwork = cover.startsWith('http://') || cover.startsWith('https://');
      return Hero(
        tag: tag,
        child: isNetwork
            ? Image.network(
                cover,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _defaultCover(neutral),
              )
            : Image.file(
                File(cover),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 400,
                errorBuilder: (_, __, ___) => _defaultCover(neutral),
              ),
      );
    }
    return _defaultCover(neutral);
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(
          CupertinoIcons.play_circle,
          color: neutral.textSecondary,
          size: 32,
        ),
      ),
    );
  }

  void _showSeriesOptions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(group.seriesName),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              for (final item in group.episodes) {
                context.read<LibraryProvider>().toggleFavorite(item.id!);
              }
              Navigator.pop(context);
            },
            child: const Text('全部收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              for (final item in group.episodes) {
                context.read<LibraryProvider>().setItemsPrivate([item.id!], !item.isPrivate);
              }
              Navigator.pop(context);
            },
            child: const Text('设为私密/取消私密'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              final confirm = await showCupertinoDialog<bool>(
                context: context,
                builder: (context) => CupertinoAlertDialog(
                  title: const Text('确认删除'),
                  content: Text('删除 ${group.seriesName} 的 ${group.episodes.length} 个视频？'),
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
              if (confirm == true && context.mounted) {
                for (final item in group.episodes) {
                  await context.read<LibraryProvider>().deleteItem(item.id!);
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除全部'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final LibraryItem item;
  final ReadingProgress? progress;
  final bool selectionMode;
  final bool isSelected;
  final bool isCloud;
  final bool isDownloaded;
  final VoidCallback onToggleSelect;

  const _MediaCard({
    required this.item,
    this.progress,
    this.selectionMode = false,
    this.isSelected = false,
    this.isCloud = false,
    this.isDownloaded = false,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMusic = item.mediaType == MediaType.music;
    return Pressable(
      onTap: () {
        if (selectionMode) {
          onToggleSelect();
        } else {
          _openMedia(context, item);
        }
      },
      onLongPress: selectionMode ? null : () => _showOptions(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: isMusic ? 1 : 2 / 3,
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
                // 云端角标（右上角）
                if (isCloud)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: SourceBadge(
                      sourceType: item.sourceType,
                      isDownloaded: isDownloaded,
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
                // 已看完标记（仅视频）
                if (!isMusic && progress != null && progress!.percentage >= 0.95)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                // 底部进度条（仅视频，在看中）
                if (!isMusic && progress != null && progress!.percentage > 0 && progress!.percentage < 0.95)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(AppRadius.medium),
                          bottomRight: Radius.circular(AppRadius.medium),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress!.percentage.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(AppRadius.medium),
                              bottomRight: Radius.circular(AppRadius.medium),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
    final tag = 'hero_video_cover_${item.filePath.hashCode}';
    final cover = item.effectiveCover;
    if (cover != null) {
      final isNetwork = cover.startsWith('http://') || cover.startsWith('https://');
      return Hero(
        tag: tag,
        child: isNetwork
            ? Image.network(
                cover,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _defaultCover(neutral),
              )
            : Image.file(
                File(cover),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 400,
                errorBuilder: (_, __, ___) => _defaultCover(neutral),
              ),
      );
    }
    return _defaultCover(neutral);
  }

  Widget _defaultCover(NeutralPalette neutral) {
    final isMusic = item.mediaType == MediaType.music;
    return Container(
      color: neutral.surfaceElevated,
      child: Center(
        child: Icon(
          isMusic ? CupertinoIcons.music_note : CupertinoIcons.play_circle,
          color: neutral.textSecondary,
          size: 32,
        ),
      ),
    );
  }
}

void _showOptions(BuildContext context, LibraryItem item) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(item.title),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () {
            context.read<LibraryProvider>().toggleFavorite(item.id!);
            Navigator.pop(context);
          },
          child: Text(item.isFavorite ? '取消收藏' : '收藏'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            context.read<LibraryProvider>().setItemsPrivate([item.id!], !item.isPrivate);
            Navigator.pop(context);
          },
          child: Text(item.isPrivate ? '取消私密' : '设为私密'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            _showMoveSheet(context, item);
          },
          child: const Text('移动到'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(context);
            await context.read<LibraryProvider>().changeCover(item.id!);
          },
          child: const Text('更换封面'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            _showEditDialog(context, item);
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
              title: Text('确认删除', style: TextStyle(color: NeutralPalette.of(context).textPrimary)),
              content: Text(
                '删除后可在回收站找回，是否继续？',
                style: TextStyle(color: NeutralPalette.of(context).textSecondary),
              ),
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
          if (confirm == true && context.mounted) {
            await context.read<LibraryProvider>().deleteItem(item.id!);
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('删除'),
      ),
    ),
  );
}

void _showMoveSheet(BuildContext context, LibraryItem item) {
  final targets = MediaType.values.where((t) => t != item.mediaType).toList();
  showCupertinoModalPopup(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('移动到'),
      actions: targets.map((type) {
        return CupertinoActionSheetAction(
          onPressed: () async {
            await context.read<LibraryProvider>().moveItemToType(item.id!, type);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(_mediaTypeName(type)),
        );
      }).toList(),
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ),
  );
}

void _showEditDialog(BuildContext context, LibraryItem item) {
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
              color: NeutralPalette.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: authorController,
            placeholder: '作者',
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: NeutralPalette.of(context).surfaceElevated,
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
              color: NeutralPalette.of(context).surfaceElevated,
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

class _AddButton extends StatelessWidget {
  final MediaType type;

  const _AddButton({required this.type});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
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
            aspectRatio: type == MediaType.music ? 1 : 2 / 3,
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
              color: neutral.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaSelectionBottomBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const _MediaSelectionBottomBar({
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClearAll,
    required this.onDelete,
    required this.onToggleFavorite,
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

/// Up Next 卡片：160×90（16:9）+ 底部进度条
class _UpNextCard extends StatelessWidget {
  final LibraryItem item;
  final bool isCloud;
  final bool isDownloaded;
  final VoidCallback onTap;

  const _UpNextCard({required this.item, this.isCloud = false, this.isDownloaded = false, required this.onTap});

  Widget _buildUpNextCover(LibraryItem item, NeutralPalette neutral) {
    final cover = item.effectiveCover;
    if (cover == null) {
      return Center(
        child: Icon(CupertinoIcons.film, color: neutral.textTertiary, size: 28),
      );
    }
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return Image.network(
        cover,
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(CupertinoIcons.film, color: neutral.textTertiary, size: 28),
        ),
      );
    }
    return Image.file(
      File(cover),
      fit: BoxFit.cover,
      cacheWidth: 400,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(CupertinoIcons.film, color: neutral.textTertiary, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final progress = item.totalProgress != null && item.totalProgress! > 0
        ? (item.lastOpenedDate != null ? 0.3 : 0.0) // 简化：有打开记录就显示30%进度
        : 0.0;

    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Stack(
                children: [
                  Container(
                    width: 160,
                    height: 90,
                    color: neutral.surfaceElevated,
                    child: _buildUpNextCover(item, neutral),
                  ),
                  // 云端角标（右上角）
                  if (isCloud)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: SourceBadge(
                        sourceType: item.sourceType,
                        isDownloaded: isDownloaded,
                      ),
                    ),
                  // 底部进度条
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3,
                        color: Colors.black.withOpacity(0.3),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(color: AppColors.primary),
                        ),
                      ),
                    ),
                ],
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
    final color = isDestructive
        ? FunctionalColors.error
        : enabled
            ? AppColors.primary
            : neutral.textTertiary;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      minSize: 0,
      onPressed: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}
