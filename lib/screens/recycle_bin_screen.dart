import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';
import '../models/song.dart';
import '../database/song_dao.dart';
import '../providers/comic_series_provider.dart';
import '../providers/library_provider.dart';
import '../database/library_dao.dart';
import '../database/comic_series_dao.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<LibraryItem> _deletedItems = [];
  List<ComicSeries> _deletedSeries = [];
  bool _isLoading = false;
  final Map<String, String?> _musicCoverPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    List<LibraryItem> items = [];
    List<ComicSeries> series = [];

    try {
      items = await LibraryDao().getDeletedItems();
    } catch (e) {
      debugPrint('回收站加载 library_items 失败: $e');
    }

    try {
      series = await ComicSeriesDao().getDeletedSeries();
    } catch (e) {
      debugPrint('回收站加载 comic_series 失败: $e');
    }

    // 预加载音乐项封面，避免列表滚动时的 N+1 查询
    final musicItems = items.where((i) => i.mediaType == MediaType.music).toList();
    if (musicItems.isNotEmpty) {
      final dao = SongDao();
      for (final item in musicItems) {
        try {
          final song = await dao.getSongByPath(item.filePath);
          _musicCoverPaths[item.filePath] = song?.coverPath;
        } catch (_) {
          _musicCoverPaths[item.filePath] = null;
        }
      }
    }

    if (mounted) {
      setState(() {
        _deletedItems = items;
        _deletedSeries = series;
        _isLoading = false;
      });
    }
  }

  List<LibraryItem> _filteredItems(int tabIndex) {
    if (tabIndex == 0) return _deletedItems;
    final type = switch (tabIndex) {
      1 => MediaType.novel,
      2 => MediaType.comic,
      3 => MediaType.video,
      4 => MediaType.music,
      _ => MediaType.novel,
    };
    return _deletedItems.where((i) => i.mediaType == type).toList();
  }

  Future<void> _restoreItem(LibraryItem item) async {
    await LibraryDao().restoreItem(item.id!);
    await context.read<LibraryProvider>().loadLibrary();
    await _loadData();
  }

  Future<void> _restoreSeries(ComicSeries series) async {
    await ComicSeriesDao().restoreSeries(series.id!);
    await context.read<ComicSeriesProvider>().loadSeries();
    await _loadData();
  }

  Future<void> _permanentlyDeleteItem(LibraryItem item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认彻底删除'),
        content: const Text('此操作将永久删除文件，无法恢复。是否继续？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await LibraryDao().permanentlyDeleteItem(item.id!);
    await _loadData();
  }

  Future<void> _permanentlyDeleteSeries(ComicSeries series) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认彻底删除'),
        content: const Text('此操作将永久删除文件，无法恢复。是否继续？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await context.read<ComicSeriesProvider>().permanentlyDeleteSeries(series.id!);
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
                  '回收站',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? neutral.surfaceElevated : neutral.divider,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: isDark ? neutral.divider : neutral.surface,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(text: '全部'),
                  Tab(text: '小说'),
                  Tab(text: '漫画'),
                  Tab(text: '视频'),
                  Tab(text: '音乐'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _KeepAliveWrapper(child: _buildList(_deletedItems, _deletedSeries, bottomPadding)),
                      _KeepAliveWrapper(child: _buildList(_filteredItems(1), [], bottomPadding)),
                      _KeepAliveWrapper(child: _buildList(_filteredItems(2), _deletedSeries, bottomPadding)),
                      _KeepAliveWrapper(child: _buildList(_filteredItems(3), [], bottomPadding)),
                      _KeepAliveWrapper(child: _buildList(_filteredItems(4), [], bottomPadding)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<LibraryItem> items, List<ComicSeries> series, double bottomPadding) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCount = items.length + series.length;

    if (totalCount == 0) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.trash, color: neutral.textTertiary, size: 48),
                    const SizedBox(height: 12),
                    Text('回收站是空的', style: TextStyle(color: neutral.textTertiary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        cacheExtent: 200.0,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (index < items.length) {
            final item = items[index];
            return _DeletedItemTile(
              item: item,
              coverPath: _musicCoverPaths[item.filePath],
              onRestore: () => _restoreItem(item),
              onDelete: () => _permanentlyDeleteItem(item),
            );
          }
          final s = series[index - items.length];
          return _DeletedSeriesTile(
            series: s,
            onRestore: () => _restoreSeries(s),
            onDelete: () => _permanentlyDeleteSeries(s),
          );
        },
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _DeletedItemTile extends StatelessWidget {
  final LibraryItem item;
  final String? coverPath;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _DeletedItemTile({
    required this.item,
    this.coverPath,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: _buildCover(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: neutral.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _typeLabel(item.mediaType),
                  style: TextStyle(
                    fontSize: 12,
                    color: neutral.textTertiary,
                  ),
                ),
                if (item.deletedAt != null)
                  Text(
                    '删除于 ${_formatDate(item.deletedAt!)}',
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
            onPressed: onRestore,
            child: const Icon(CupertinoIcons.arrow_counterclockwise, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: onDelete,
            child: const Icon(CupertinoIcons.trash_fill, color: FunctionalColors.error, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (item.coverPath != null) {
      return Image.file(
        File(item.coverPath!),
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (ctx, __, ___) => _defaultCover(ctx),
      );
    }
    if (item.mediaType == MediaType.music) {
      if (coverPath != null) {
        return Image.file(
          File(coverPath!),
          width: 48,
          height: 64,
          fit: BoxFit.cover,
          cacheWidth: 200,
          errorBuilder: (ctx, __, ___) => _defaultCover(ctx),
        );
      }
      return _defaultCover(context);
    }
    return _defaultCover(context);
  }

  Widget _defaultCover(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? neutral.surfaceElevated : neutral.divider,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Icon(
        _typeIcon(item.mediaType),
        color: neutral.textTertiary,
        size: 20,
      ),
    );
  }

  IconData _typeIcon(MediaType type) {
    switch (type) {
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

  String _typeLabel(MediaType type) {
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

  String _formatDate(DateTime date) {
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _DeletedSeriesTile extends StatelessWidget {
  final ComicSeries series;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _DeletedSeriesTile({
    required this.series,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: _buildCover(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: neutral.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '漫画系列 · ${series.totalChapters} 章节',
                  style: TextStyle(
                    fontSize: 12,
                    color: neutral.textTertiary,
                  ),
                ),
                if (series.deletedAt != null)
                  Text(
                    '删除于 ${_formatDate(series.deletedAt!)}',
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
            onPressed: onRestore,
            child: const Icon(CupertinoIcons.arrow_counterclockwise, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: onDelete,
            child: const Icon(CupertinoIcons.trash_fill, color: FunctionalColors.error, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (series.coverPath != null) {
      return Image.file(
        File(series.coverPath!),
        width: 48,
        height: 64,
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (ctx, __, ___) => _defaultCover(ctx),
      );
    }
    return _defaultCover(context);
  }

  Widget _defaultCover(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? neutral.surfaceElevated : neutral.divider,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Icon(
        CupertinoIcons.photo,
        color: neutral.textTertiary,
        size: 20,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
