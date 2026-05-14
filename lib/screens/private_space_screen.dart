import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../database/comic_series_dao.dart';
import '../database/library_dao.dart';
import '../database/song_dao.dart';
import '../design_tokens/app_colors.dart';
import '../design_tokens/app_radius.dart';
import '../design_tokens/app_shadows.dart';
import '../design_tokens/app_spacing.dart';
import '../models/comic_series.dart';
import '../models/library_item.dart';
import '../models/song.dart';
import '../services/music_player_service.dart';
import '../services/music_scan_service.dart';
import '../services/privacy_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/pressable.dart';
import 'comic_series_detail_screen.dart';
import 'media/music/music_player_screen.dart';
import 'readers/audio_player_screen.dart';
import 'readers/comic_reader_screen.dart';
import 'readers/novel_reader_screen.dart';
import 'readers/video_player_screen.dart';
import 'book_detail_screen.dart';
import 'video_detail_screen.dart';

class PrivateSpaceScreen extends StatefulWidget {
  const PrivateSpaceScreen({super.key});

  @override
  State<PrivateSpaceScreen> createState() => _PrivateSpaceScreenState();
}

class _PrivateSpaceScreenState extends State<PrivateSpaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Future<List<LibraryItem>>? _novelsFuture;
  Future<List<LibraryItem>>? _videosFuture;
  Future<List<LibraryItem>>? _musicItemsFuture;
  Future<List<ComicSeries>>? _comicsFuture;
  Future<List<Song>>? _songsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    PrivacyService.instance.addListener(_onPrivacyLocked);
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyLocked);
    _tabController.dispose();
    super.dispose();
  }

  void _onPrivacyLocked() {
    if (!PrivacyService.instance.isUnlocked && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _loadData() {
    final dao = LibraryDao();
    _novelsFuture = dao.getPrivateItems().then(
          (items) => items.where((i) => i.mediaType == MediaType.novel).toList(),
        );
    _videosFuture = dao.getPrivateItems().then(
          (items) => items.where((i) => i.mediaType == MediaType.video).toList(),
        );
    _musicItemsFuture = dao.getPrivateItems().then(
          (items) => items.where((i) => i.mediaType == MediaType.music).toList(),
        );
    _comicsFuture = ComicSeriesDao().getPrivateSeries();
    _songsFuture = SongDao().getPrivateSongs();
  }

  void _refresh() {
    setState(() => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('私密空间'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () {
            PrivacyService.instance.lock();
            // 由 _onPrivacyLocked 监听自动 pop，不要手动 pop 避免重复
          },
          child: const Icon(CupertinoIcons.lock_fill, size: 20),
        ),
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
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
                    Tab(text: '视频'),
                    Tab(text: '音乐'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLibraryGrid(_novelsFuture!, MediaType.novel),
                  _buildComicGrid(),
                  _buildLibraryGrid(_videosFuture!, MediaType.video),
                  _buildMusicList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryGrid(Future<List<LibraryItem>> future, MediaType type) {
    return FutureBuilder<List<LibraryItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return EmptyState(
            icon: _emptyIcon(type),
            title: '没有私密的${_typeName(type)}',
            subtitle: '在${_typeName(type)}列表长按标记为私密',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.50,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _PrivateItemCard(
                item: item,
                onTap: () => _openItem(context, item),
                onUnprivate: () => _unprivateItem(item),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildComicGrid() {
    return FutureBuilder<List<ComicSeries>>(
      future: _comicsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator());
        }
        final series = snapshot.data ?? [];
        if (series.isEmpty) {
          return const EmptyState(
            icon: CupertinoIcons.photo_on_rectangle,
            title: '没有私密的漫画',
            subtitle: '在漫画列表长按标记为私密',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.50,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            itemCount: series.length,
            itemBuilder: (context, index) {
              final s = series[index];
              return _PrivateSeriesCard(
                series: s,
                onTap: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => ComicSeriesDetailScreen(series: s),
                    ),
                  );
                },
                onUnprivate: () => _unprivateSeries(s),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMusicList() {
    return FutureBuilder<List<Song>>(
      future: _songsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator());
        }
        final songs = snapshot.data ?? [];
        if (songs.isEmpty) {
          return const EmptyState(
            icon: CupertinoIcons.music_note,
            title: '没有私密的音乐',
            subtitle: '在音乐列表长按标记为私密',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _PrivateSongTile(
                song: song,
                onTap: () => _playSong(context, songs, song),
                onUnprivate: () => _unprivateSong(song),
              );
            },
          ),
        );
      },
    );
  }

  void _openItem(BuildContext context, LibraryItem item) {
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
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => screen));
  }

  Future<void> _playSong(BuildContext context, List<Song> songs, Song target) async {
    final service = MusicPlayerService.instance;
    await service.setQueue(songs);
    await service.playSong(target);
    if (context.mounted && !MusicPlayerScreen.isOpen) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (_) => const MusicPlayerScreen(),
        ),
      );
    }
  }

  Future<void> _unprivateItem(LibraryItem item) async {
    final updated = item.copyWith(isPrivate: false);
    await LibraryDao().updateItem(updated);
    _refresh();
  }

  Future<void> _unprivateSeries(ComicSeries series) async {
    await ComicSeriesDao().setSeriesPrivate(series.id!, false);
    _refresh();
  }

  Future<void> _unprivateSong(Song song) async {
    await SongDao().setSongPrivate(song.id!, false);
    _refresh();
  }

  String _typeName(MediaType type) {
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

  IconData _emptyIcon(MediaType type) {
    switch (type) {
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
}

// ===================== 卡片组件 =====================

class _PrivateItemCard extends StatelessWidget {
  final LibraryItem item;
  final VoidCallback onTap;
  final VoidCallback? onUnprivate;

  const _PrivateItemCard({required this.item, required this.onTap, this.onUnprivate});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: onTap,
      onLongPress: onUnprivate == null ? null : () => _showActionSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                boxShadow: isDark ? null : [AppShadows.ambient],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: _buildCover(neutral),
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
    if (item.coverPath != null) {
      return Image.file(
        File(item.coverPath!),
        fit: BoxFit.cover,
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
          _iconForType(item.mediaType),
          color: neutral.textTertiary,
          size: 32,
        ),
      ),
    );
  }

  IconData _iconForType(MediaType type) {
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

  void _showActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onUnprivate?.call();
            },
            child: const Text('取消私密'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _PrivateSeriesCard extends StatelessWidget {
  final ComicSeries series;
  final VoidCallback onTap;
  final VoidCallback? onUnprivate;

  const _PrivateSeriesCard({required this.series, required this.onTap, this.onUnprivate});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: onTap,
      onLongPress: onUnprivate == null ? null : () => _showActionSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                boxShadow: isDark ? null : [AppShadows.ambient],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: _buildCover(neutral),
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
        child: Icon(CupertinoIcons.photo, color: neutral.textTertiary, size: 32),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(series.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onUnprivate?.call();
            },
            child: const Text('取消私密'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

class _PrivateSongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onUnprivate;

  const _PrivateSongTile({required this.song, required this.onTap, this.onUnprivate});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      onLongPress: onUnprivate == null ? null : () => _showActionSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: neutral.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: song.coverPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: Image.file(
                        File(song.coverPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          CupertinoIcons.music_note,
                          color: neutral.textTertiary,
                        ),
                      ),
                    )
                  : Icon(CupertinoIcons.music_note, color: neutral.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: neutral.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.artist != null && song.artist!.isNotEmpty)
                    Text(
                      song.artist!,
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.play_fill,
              color: neutral.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(song.title ?? '未知歌曲', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onUnprivate?.call();
            },
            child: const Text('取消私密'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }
}
