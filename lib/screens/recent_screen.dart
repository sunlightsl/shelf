import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../services/music_scan_service.dart';
import '../services/music_player_service.dart';
import '../database/song_dao.dart';
import '../database/library_dao.dart';
import '../models/song.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/pressable.dart';
import 'readers/novel_reader_screen.dart';
import 'readers/comic_reader_screen.dart';
import 'readers/video_player_screen.dart';
import 'media/music/music_player_screen.dart';
import 'book_detail_screen.dart';
import 'video_detail_screen.dart';
import 'package:share_plus/share_plus.dart';

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
      _playMusic(context, item);
      return;
  }
  Navigator.of(context).push(
    CupertinoPageRoute(builder: (_) => screen),
  );
}

Future<void> _playMusic(BuildContext context, LibraryItem item) async {
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

class RecentScreen extends StatefulWidget {
  const RecentScreen({super.key});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _lastMusicIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _lastMusicIndex = MusicPlayerService.instance.currentIndex;
    MusicPlayerService.instance.addListener(_onMusicServiceChanged);
    // 自动刷新获取最新数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().loadLibrary();
    });
  }

  @override
  void dispose() {
    MusicPlayerService.instance.removeListener(_onMusicServiceChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onMusicServiceChanged() {
    final service = MusicPlayerService.instance;
    if (service.currentIndex != _lastMusicIndex) {
      _lastMusicIndex = service.currentIndex;
      if (mounted && _tabController.index == 3) {
        context.read<LibraryProvider>().refreshRecentItems();
      }
    }
  }

  List<LibraryItem> _filteredItems(List<LibraryItem> items, int tabIndex) {
    final type = switch (tabIndex) {
      0 => MediaType.novel,
      1 => MediaType.comic,
      2 => MediaType.video,
      3 => MediaType.music,
      _ => MediaType.novel,
    };
    return items.where((i) => i.mediaType == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        // 固定头部：标题 + 分类
        Padding(
          padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 8),
          child: Row(
            children: [
              Text(
                '最近浏览',
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
                return const Center(
                  child: CupertinoActivityIndicator(),
                );
              }

              final allRecent = provider.recentItems;

              return TabBarView(
                controller: _tabController,
                children: [
                  _RecentList(
                    items: _filteredItems(allRecent, 0),
                    bottomPadding: bottomPadding,
                    mediaType: MediaType.novel,
                  ),
                  _RecentList(
                    items: _filteredItems(allRecent, 1),
                    bottomPadding: bottomPadding,
                    mediaType: MediaType.comic,
                  ),
                  _RecentList(
                    items: _filteredItems(allRecent, 2),
                    bottomPadding: bottomPadding,
                    mediaType: MediaType.video,
                  ),
                  _RecentList(
                    items: _filteredItems(allRecent, 3),
                    bottomPadding: bottomPadding,
                    mediaType: MediaType.music,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentList extends StatefulWidget {
  final List<LibraryItem> items;
  final double bottomPadding;
  final MediaType mediaType;

  const _RecentList({
    required this.items,
    required this.bottomPadding,
    required this.mediaType,
  });

  @override
  State<_RecentList> createState() => _RecentListState();
}

class _RecentListState extends State<_RecentList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final refresh = () => context.read<LibraryProvider>().loadLibrary();

    if (widget.items.isEmpty) {
      final (emptyTitle, emptySubtitle) = switch (widget.mediaType) {
        MediaType.novel => ('还没有小说阅读记录', '去书架导入小说并开始阅读吧'),
        MediaType.comic => ('还没有漫画阅读记录', '去书架导入漫画并开始阅读吧'),
        MediaType.video => ('还没有视频观看记录', '去影音导入视频并开始观看吧'),
        MediaType.music => ('还没有音乐播放记录', '去影音导入音乐并开始播放吧'),
      };
      return RefreshIndicator(
        onRefresh: refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: EmptyState(
                  icon: CupertinoIcons.clock,
                  title: emptyTitle,
                  subtitle: emptySubtitle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        cacheExtent: 200.0,
        padding: EdgeInsets.fromLTRB(20, 12, 20, widget.bottomPadding),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          if (widget.mediaType == MediaType.music) {
            return AnimatedListItem(
              index: index,
              child: _RecentMusicTile(item: item),
            );
          }
          return AnimatedListItem(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RecentItemCard(item: item),
            ),
          );
        },
      ),
    );
  }
}

class _RecentItemCard extends StatelessWidget {
  final LibraryItem item;

  const _RecentItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: () => _openReader(context, item),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: neutral.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: isDark ? null : [AppShadows.ambient],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: _buildCover(neutral),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.author != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.author!,
                        style: TextStyle(
                          fontSize: 14,
                          color: neutral.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _TypeChip(type: item.mediaType),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(item.lastOpenedDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: neutral.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: neutral.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(NeutralPalette neutral) {
    if (item.coverPath != null) {
      return Image.file(
        File(item.coverPath!),
        width: 60,
        height: 80,
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (_, __, ___) => _defaultCover(neutral),
      );
    }
    return _defaultCover(neutral);
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      width: 60,
      height: 80,
      decoration: BoxDecoration(
        color: neutral.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Icon(
        _getIcon(),
        color: neutral.textTertiary,
        size: 24,
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

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }
}

class _RecentMusicTile extends StatefulWidget {
  final LibraryItem item;

  const _RecentMusicTile({required this.item});

  @override
  State<_RecentMusicTile> createState() => _RecentMusicTileState();
}

class _RecentMusicTileState extends State<_RecentMusicTile> {
  Song? _song;

  @override
  void initState() {
    super.initState();
    _loadSong();
  }

  Future<void> _loadSong() async {
    final song = await SongDao().getSongByPath(widget.item.filePath);
    if (mounted && song != null) {
      setState(() => _song = song);
    }
  }

  Future<void> _showMoreSheet() async {
    final song = _song;
    final neutral = NeutralPalette.of(context);
    if (song == null) return;

    final isFav = song.id != null &&
        await SongDao().isFavorite(song.id!);

    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(song.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _playMusic(context, widget.item);
            },
            child: const Text('播放'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              if (song.id != null) {
                await SongDao().toggleFavorite(song.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isFav ? '已取消收藏' : '已收藏'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: neutral.surfaceElevated,
                    ),
                  );
                }
              }
            },
            child: Text(isFav ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              Share.shareXFiles([XFile(song.filePath)], text: song.displayTitle);
            },
            child: const Text('分享'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              final libraryItem = await LibraryDao().getItemByPath(song.filePath);
              if (libraryItem?.id != null) {
                await LibraryDao().deleteItem(libraryItem!.id!);
                await context.read<LibraryProvider>().loadLibrary();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        '已移至回收站，可在回收站中找回',
                        style: TextStyle(color: Colors.white),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: neutral.surfaceElevated,
                    ),
                  );
                }
              }
            },
            child: const Text('删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final coverPath = _song?.coverPath ?? widget.item.coverPath;
    final artist = _song?.artist?.trim().isNotEmpty == true
        ? _song!.artist!
        : (widget.item.author ?? '未知艺术家');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: coverPath != null
              ? Image.file(
                  File(coverPath),
                  fit: BoxFit.cover,
                  cacheWidth: 200,
                  errorBuilder: (_, __, ___) => _defaultCover(neutral),
                )
              : _defaultCover(neutral),
        ),
      ),
      title: Text(
        widget.item.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        artist,
        style: TextStyle(
          fontSize: 13,
          color: neutral.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: 0,
        onPressed: _showMoreSheet,
        child: Icon(
          CupertinoIcons.ellipsis_vertical,
          color: neutral.textTertiary,
          size: 18,
        ),
      ),
      onTap: () => _playMusic(context, widget.item),
    );
  }

  Widget _defaultCover(NeutralPalette neutral) {
    return Container(
      color: neutral.surfaceElevated,
      child: Icon(
        CupertinoIcons.music_note,
        color: neutral.textTertiary,
        size: 20,
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final MediaType type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      MediaType.novel => ('小说', AppColors.primary),
      MediaType.comic => ('漫画', FunctionalColors.success),
      MediaType.video => ('视频', FunctionalColors.warning),
      MediaType.music => ('音乐', const Color(0xFF6B4EE6)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
