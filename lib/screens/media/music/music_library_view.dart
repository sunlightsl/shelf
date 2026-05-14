import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../../models/song.dart';
import '../../../models/library_item.dart';
import '../../../services/music_player_service.dart';
import '../../../services/music_scan_service.dart';
import '../../../services/app_directories.dart';
import '../../../database/song_dao.dart';
import '../../../database/library_dao.dart';
import 'music_player_screen.dart';
import '../../../widgets/animated_list_item.dart';
import '../../../widgets/pressable.dart';
import '../../../services/privacy_service.dart';

enum MusicViewMode { all, album, artist, folder, playlist, favorite, recent }

class MusicLibraryView extends StatefulWidget {
  static final GlobalKey<MusicLibraryViewState> globalKey = GlobalKey();
  final String searchQuery;
  final bool selectionMode;
  final SortMode sortMode;
  final bool sortAscending;
  final Set<String> cloudPaths;

  const MusicLibraryView({
    super.key,
    this.searchQuery = '',
    this.selectionMode = false,
    this.sortMode = SortMode.title,
    this.sortAscending = true,
    this.cloudPaths = const {},
  });

  @override
  State<MusicLibraryView> createState() => MusicLibraryViewState();
}

class MusicLibraryViewState extends State<MusicLibraryView>
    with AutomaticKeepAliveClientMixin {
  final SongDao _dao = SongDao();
  List<Song> _songs = [];
  List<Song> get songs => List.unmodifiable(_songs);
  Set<int> _favoriteIds = {};
  MusicViewMode _mode = MusicViewMode.all;
  bool _isLoading = true;
  Set<int> _selectedSongIds = {};
  Map<int, DateTime> _lastPlayedTimes = {};
  Map<String, DateTime> _modTimeCache = {};

  @override
  bool get wantKeepAlive => true;

  Set<int> get selectedSongIds => Set.unmodifiable(_selectedSongIds);
  int get selectedCount => _selectedSongIds.length;
  bool get hasSelection => _selectedSongIds.isNotEmpty;
  bool get allSelected =>
      _songs.isNotEmpty && _songs.every((s) => s.id != null && _selectedSongIds.contains(s.id));

  void toggleSelect(int songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  void selectAll() {
    setState(() {
      _selectedSongIds = _songs.where((s) => s.id != null).map((s) => s.id!).toSet();
    });
  }

  void clearAll() {
    setState(() => _selectedSongIds.clear());
  }

  @override
  void didUpdateWidget(covariant MusicLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {});
    }
    if (oldWidget.selectionMode != widget.selectionMode) {
      setState(() => _selectedSongIds.clear());
    }
    if (oldWidget.sortMode != widget.sortMode || oldWidget.sortAscending != widget.sortAscending) {
      setState(() => _songs = _sortSongs(_songs));
    }
  }

  List<Song> get _filteredSongs {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _songs;
    return _songs.where((s) {
      return s.displayTitle.toLowerCase().contains(query) ||
          s.displayArtist.toLowerCase().contains(query) ||
          s.displayAlbum.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadSongs();
    PrivacyService.instance.addListener(_onPrivacyChanged);
  }

  void _onPrivacyChanged() {
    if (!PrivacyService.instance.isUnlocked) {
      _loadSongs();
    }
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyChanged);
    super.dispose();
  }

  Future<void> refresh() => _loadSongs();

  Future<void> _loadSongs() async {
    setState(() => _isLoading = true);
    try {
      await MusicScanService.instance.syncFromLibrary();
      final songs = await _dao.getAllSongs();
      final favIds = await _dao.getFavoriteSongIds();
      final lastPlayed = await _dao.getAllLastPlayedTimes();
      final modCache = await _preloadModTimes(songs);
      if (mounted) {
        setState(() {
          _modTimeCache = modCache;
          _songs = _sortSongs(songs);
          _favoriteIds = favIds.toSet();
          _lastPlayedTimes = lastPlayed;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载音乐失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Map<String, DateTime>> _preloadModTimes(List<Song> songs) async {
    final cache = <String, DateTime>{};
    for (final song in songs) {
      try {
        cache[song.filePath] = await File(song.filePath).lastModified();
      } catch (_) {}
    }
    return cache;
  }

  List<Song> _sortSongs(List<Song> songs) {
    final sorted = List<Song>.from(songs);
    int cmp(int v) => widget.sortAscending ? v : -v;
    switch (widget.sortMode) {
      case SortMode.title:
        sorted.sort((a, b) => cmp(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase())));
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
        sorted.sort((a, b) {
          if (a.createdAt == null && b.createdAt == null) return 0;
          if (a.createdAt == null) return widget.sortAscending ? 1 : -1;
          if (b.createdAt == null) return widget.sortAscending ? -1 : 1;
          return cmp(a.createdAt!.compareTo(b.createdAt!));
        });
      case SortMode.lastOpenedTime:
        sorted.sort((a, b) {
          final pa = a.id != null ? _lastPlayedTimes[a.id] : null;
          final pb = b.id != null ? _lastPlayedTimes[b.id] : null;
          if (pa == null && pb == null) return 0;
          if (pa == null) return widget.sortAscending ? 1 : -1;
          if (pb == null) return widget.sortAscending ? -1 : 1;
          return cmp(pa.compareTo(pb));
        });
    }
    return sorted;
  }

  Future<void> _toggleFavorite(Song song) async {
    if (song.id == null) return;
    await _dao.toggleFavorite(song.id!);
    final favIds = await _dao.getFavoriteSongIds();
    if (mounted) {
      setState(() => _favoriteIds = favIds.toSet());
    }
  }

  void _playSong(Song song) async {
    final service = MusicPlayerService.instance;
    if (service.queue.isEmpty || service.queue.every((s) => s.id != song.id)) {
      await service.setQueue(_songs);
    }
    await service.playSong(song);
    if (mounted && !MusicPlayerScreen.isOpen) {
      Navigator.of(context).push(MusicPlayerScreen.route());
    }
  }

  void _playAll(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;
    final service = MusicPlayerService.instance;
    await service.setQueue(songs, startIndex: startIndex);
    await service.playSong(songs[startIndex]);
    if (mounted && !MusicPlayerScreen.isOpen) {
      Navigator.of(context).push(MusicPlayerScreen.route());
    }
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '--:--';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final songs = _filteredSongs;

    if (songs.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的音乐',
          textAlign: TextAlign.center,
          style: TextStyle(color: neutral.textTertiary, fontSize: 15),
        ),
      );
    }

    return Column(
      children: [
        // 分类 Tab
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: neutral.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModeTab('全部', MusicViewMode.all),
                  _buildModeTab('专辑', MusicViewMode.album),
                  _buildModeTab('艺术家', MusicViewMode.artist),
                  _buildModeTab('文件夹', MusicViewMode.folder),
                  _buildModeTab('播放列表', MusicViewMode.playlist),
                  _buildModeTab('收藏', MusicViewMode.favorite),
                  _buildModeTab('最近', MusicViewMode.recent),
                ],
              ),
            ),
          ),
        ),
        // 内容区域
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSongs,
            child: switch (_mode) {
              MusicViewMode.all => _buildAllList(),
              MusicViewMode.album => _buildAlbumGrid(),
              MusicViewMode.artist => _buildArtistList(),
              MusicViewMode.folder => _buildFolderList(),
              MusicViewMode.playlist => _buildPlaylistList(),
              MusicViewMode.favorite => _buildFavoriteList(),
              MusicViewMode.recent => _buildRecentList(),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeTab(String label, MusicViewMode mode) {
    final neutral = NeutralPalette.of(context);
    final isActive = _mode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? (isDark ? neutral.surfaceElevated : neutral.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.small),
          boxShadow: isActive && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? (neutral.textPrimary) : neutral.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildAllList() {
    final songs = _filteredSongs;
    return ListView.builder(
      cacheExtent: 200.0,
      padding: const EdgeInsets.only(top: 4),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _PlayAllButton(
            count: songs.length,
            onTap: () => _playAll(songs),
          );
        }
        final song = songs[index - 1];
        return AnimatedListItem(
          index: index - 1,
          child: _SongTile(
            song: song,
            durationText: _formatDuration(song.duration),
            onTap: () => _playSong(song),
            onMorePressed: widget.selectionMode ? null : () => _showSongMoreSheet(song),
            onLongPress: widget.selectionMode ? null : () => _showSongMoreSheet(song),
            selectionMode: widget.selectionMode,
            isSelected: song.id != null && _selectedSongIds.contains(song.id!),
            onToggleSelect: song.id != null ? () => toggleSelect(song.id!) : null,
            isCloud: widget.cloudPaths.contains(song.filePath),
          ),
        );
      },
    );
  }

  Widget _buildAlbumGrid() {
    final songs = _filteredSongs;
    final albums = <String, List<Song>>{};
    for (final song in songs) {
      final key = song.album?.trim().isNotEmpty == true ? song.album! : '未知专辑';
      albums.putIfAbsent(key, () => []).add(song);
    }
    final albumNames = albums.keys.toList()..sort();

    return GridView.builder(
      cacheExtent: 200.0,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albumNames.length,
      itemBuilder: (context, index) {
        final album = albumNames[index];
        final songs = albums[album]!;
        final coverSong = songs.firstWhere(
          (s) => s.coverPath != null,
          orElse: () => songs.first,
        );
        return _AlbumCard(
          album: album,
          artist: songs.first.artist ?? '未知艺术家',
          songCount: songs.length,
          coverPath: coverSong.coverPath,
          onTap: () => _showAlbumSongs(album, songs, type: 'album'),
          onPlayAlbum: () => _playAll(songs),
        );
      },
    );
  }

  Widget _buildArtistList() {
    final songs = _filteredSongs;
    final artists = <String, List<Song>>{};
    for (final song in songs) {
      final key = song.artist?.trim().isNotEmpty == true ? song.artist! : '未知艺术家';
      artists.putIfAbsent(key, () => []).add(song);
    }
    final artistNames = artists.keys.toList()..sort();

    return ListView.builder(
      cacheExtent: 200.0,
      padding: const EdgeInsets.only(top: 4),
      itemCount: artistNames.length,
      itemBuilder: (context, index) {
        final artist = artistNames[index];
        final artistSongs = artists[artist]!;
        final neutral = NeutralPalette.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final coverSong = artistSongs.firstWhere(
          (s) => s.coverPath != null && s.coverPath!.isNotEmpty,
          orElse: () => artistSongs.first,
        );
        final hasCover = coverSong.coverPath != null && coverSong.coverPath!.isNotEmpty;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: hasCover
                  ? Image.file(
                      File(coverSong.coverPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 150,
                      errorBuilder: (_, __, ___) => _buildArtistPlaceholder(isDark),
                    )
                  : _buildArtistPlaceholder(isDark),
            ),
          ),
          title: Text(
            artist,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text('${artistSongs.length} 首歌曲', style: TextStyle(fontSize: 13, color: neutral.textSecondary)),
          trailing: Icon(CupertinoIcons.chevron_forward, color: neutral.textTertiary, size: 14),
          onTap: () => _showAlbumSongs(artist, artistSongs, type: 'artist'),
        );
      },
    );
  }

  Widget _buildArtistPlaceholder(bool isDark) {
    final neutral = NeutralPalette.of(context);
    return Container(
      color: neutral.surfaceElevated,
      child: Icon(
        CupertinoIcons.person,
        color: neutral.textSecondary,
        size: 24,
      ),
    );
  }

  Widget _buildFavoriteList() {
    final neutral = NeutralPalette.of(context);
    final songs = _filteredSongs;
    final favSongs = songs.where((s) => s.id != null && _favoriteIds.contains(s.id)).toList();
    if (favSongs.isEmpty) {
      return Center(
        child: Text(
          '还没有收藏的歌曲',
          style: TextStyle(color: neutral.textTertiary, fontSize: 15),
        ),
      );
    }
    return ListView.builder(
      cacheExtent: 200.0,
      padding: const EdgeInsets.only(top: 4),
      itemCount: favSongs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _PlayAllButton(
            count: favSongs.length,
            onTap: () => _playAll(favSongs),
          );
        }
        final song = favSongs[index - 1];
        return _SongTile(
          song: song,
          durationText: _formatDuration(song.duration),
          onTap: () => _playSong(song),
          onMorePressed: widget.selectionMode ? null : () => _showSongMoreSheet(song),
          onLongPress: widget.selectionMode ? null : () => _showSongMoreSheet(song),
          selectionMode: widget.selectionMode,
          isSelected: song.id != null && _selectedSongIds.contains(song.id!),
          onToggleSelect: song.id != null ? () => toggleSelect(song.id!) : null,
          isCloud: widget.cloudPaths.contains(song.filePath),
        );
      },
    );
  }

  Widget _buildRecentList() {
    final neutral = NeutralPalette.of(context);
    final songs = _filteredSongs;
    return FutureBuilder<List<int>>(
      future: _dao.getRecentSongIds(),
      builder: (context, snapshot) {
        final ids = snapshot.data ?? [];
        final recentSongs = ids
            .where((id) => songs.any((s) => s.id == id))
            .map((id) => songs.firstWhere((s) => s.id == id))
            .toList();
        if (recentSongs.isEmpty) {
          return Center(
            child: Text(
              '还没有播放记录',
              style: TextStyle(color: neutral.textTertiary, fontSize: 15),
            ),
          );
        }
        return ListView.builder(
          cacheExtent: 200.0,
          padding: const EdgeInsets.only(top: 4),
          itemCount: recentSongs.length,
          itemBuilder: (context, index) {
            final song = recentSongs[index];
            return _SongTile(
              song: song,
              durationText: _formatDuration(song.duration),
              onTap: () => _playSong(song),
              onMorePressed: widget.selectionMode ? null : () => _showSongMoreSheet(song),
              onLongPress: widget.selectionMode ? null : () => _showSongMoreSheet(song),
              selectionMode: widget.selectionMode,
              isSelected: song.id != null && _selectedSongIds.contains(song.id!),
              onToggleSelect: song.id != null ? () => toggleSelect(song.id!) : null,
              isCloud: widget.cloudPaths.contains(song.filePath),
            );
          },
        );
      },
    );
  }

  Widget _buildFolderList() {
    final neutral = NeutralPalette.of(context);
    final songs = _filteredSongs;
    final folders = <String>{};
    for (final song in songs) {
      if (song.folderPath != null && song.folderPath!.isNotEmpty) {
        folders.add(song.folderPath!);
      }
    }
    final folderList = folders.toList()..sort();

    if (folderList.isEmpty) {
      return Center(
        child: Text(
          '暂无文件夹数据',
          style: TextStyle(color: neutral.textTertiary, fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      cacheExtent: 200.0,
      padding: const EdgeInsets.only(top: 4),
      itemCount: folderList.length,
      itemBuilder: (context, index) {
        final folder = folderList[index];
        final folderName = folder.split('/').last.split('\\').last;
        final songsInFolder = songs.where((s) => s.folderPath == folder).toList();
        final neutral = NeutralPalette.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: neutral.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(CupertinoIcons.folder, color: neutral.textSecondary, size: 20),
          ),
          title: Text(
            folderName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text('${songsInFolder.length} 首歌曲', style: TextStyle(fontSize: 13, color: neutral.textSecondary)),
          trailing: Icon(CupertinoIcons.chevron_forward, color: neutral.textTertiary, size: 14),
          onTap: () => _showAlbumSongs(folderName, songsInFolder, type: 'folder'),
        );
      },
    );
  }

  Widget _buildPlaylistList() {
    final neutral = NeutralPalette.of(context);
    return FutureBuilder<List<Playlist>>(
      future: _dao.getAllPlaylists(),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        if (playlists.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '还没有播放列表',
                  style: TextStyle(color: neutral.textTertiary, fontSize: 15),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  onPressed: _showCreatePlaylistDialog,
                  child: const Text('创建播放列表', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          cacheExtent: 200.0,
          padding: const EdgeInsets.only(top: 4),
          itemCount: playlists.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.s20),
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  onPressed: _showCreatePlaylistDialog,
                  child: const Text('创建播放列表', style: TextStyle(color: Colors.white)),
                ),
              );
            }
            final playlist = playlists[index - 1];
            final neutral = NeutralPalette.of(context);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final coverPath = playlist.coverPath;
            return FutureBuilder<List<Song>>(
              future: _dao.getPlaylistSongs(playlist.id!),
              builder: (context, songSnapshot) {
                final songCount = songSnapshot.data?.length ?? 0;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: coverPath != null
                          ? Image.file(
                              File(coverPath),
                              fit: BoxFit.cover,
                              cacheWidth: 150,
                              errorBuilder: (_, __, ___) => Container(
                                color: neutral.surfaceElevated,
                                child: Icon(CupertinoIcons.music_albums, color: neutral.textSecondary, size: 20),
                              ),
                            )
                          : Container(
                              color: neutral.surfaceElevated,
                              child: Icon(CupertinoIcons.music_albums, color: neutral.textSecondary, size: 20),
                            ),
                    ),
                  ),
                  title: Text(
                    playlist.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '$songCount 首歌曲',
                    style: TextStyle(fontSize: 13, color: neutral.textSecondary),
                  ),
                  trailing: Icon(CupertinoIcons.chevron_forward, color: neutral.textTertiary, size: 14),
                  onTap: () => _openPlaylist(playlist),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showCreatePlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('新建播放列表'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '播放列表名称',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      await _dao.createPlaylist(name);
      if (mounted) setState(() {});
    }
  }

  void _openPlaylist(Playlist playlist) async {
    final songs = await _dao.getPlaylistSongs(playlist.id!);
    if (!mounted) return;
    final sorted = _sortSongs(songs);
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _PlaylistDetailPage(
          playlist: playlist,
          songs: sorted,
          onPlay: _playSong,
          onMorePressed: _showSongMoreSheet,
          onPlayAll: () => _playAll(sorted),
          onEditCover: (ctx) => _pickAndSavePlaylistCover(playlist, ctx),
          onEditDescription: (ctx) => _editPlaylistDescription(playlist, ctx),
          cloudPaths: widget.cloudPaths,
        ),
      ),
    );
  }

  Future<void> _showAddToPlaylistSheet(Song song) async {
    final neutral = NeutralPalette.of(context);
    if (song.id == null) return;
    final playlists = await _dao.getAllPlaylists();
    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('添加到播放列表'),
        actions: playlists.map((p) => CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(context);
            await _dao.addSongToPlaylist(p.id!, song.id!);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已添加到 ${p.name}'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: neutral.surfaceElevated,
                ),
              );
            }
          },
          child: Text(p.name),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showSongMoreSheet(Song song) async {
    final neutral = NeutralPalette.of(context);
    final isFav = song.id != null && _favoriteIds.contains(song.id);
    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(song.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showAddToPlaylistSheet(song);
            },
            child: const Text('添加到播放列表'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              MusicPlayerService.instance.addToQueue(song);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                content: Text('已添加到播放队列'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
                backgroundColor: neutral.surfaceElevated,
              ),
              );
            },
            child: const Text('添加到当前播放列表'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              if (song.id != null) {
                await _dao.toggleFavorite(song.id!);
                final favIds = await _dao.getFavoriteSongIds();
                if (mounted) {
                  setState(() => _favoriteIds = favIds.toSet());
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
            onPressed: () async {
              Navigator.pop(context);
              if (song.id != null) {
                await SongDao().setSongPrivate(song.id!, !song.isPrivate);
                await _loadSongs();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(song.isPrivate ? '已取消私密' : '已设为私密'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: neutral.surfaceElevated,
                    ),
                  );
                }
              }
            },
            child: Text(song.isPrivate ? '取消私密' : '设为私密'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showSongInfoDialog(song);
            },
            child: const Text('歌曲信息'),
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
                await _loadSongs();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        '已移至回收站，可在回收站中找回',
                        style: TextStyle(color: Colors.white),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Theme.of(context).brightness == Brightness.dark
                          ? neutral.surfaceElevated
                          : neutral.surfaceElevated,
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

  void _showSongInfoDialog(Song song) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('歌曲信息'),
        message: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('标题', song.title ?? '未知'),
            _infoRow('艺术家', song.artist ?? '未知'),
            _infoRow('专辑', song.album ?? '未知'),
            _infoRow('时长', _formatDuration(song.duration)),
            _infoRow('路径', song.filePath),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 14, height: 1.4),
      ),
    );
  }

  Future<String?> _pickCoverImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    return picked?.path;
  }

  Future<String?> _saveCoverToAppDir(String sourcePath, String prefix) async {
    try {
      final coverDir = Directory(AppDirectories.coversCacheDir);
      if (!coverDir.existsSync()) coverDir.createSync(recursive: true);
      final ext = p.extension(sourcePath);
      final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final destPath = p.join(coverDir.path, fileName);
      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('保存封面失败: $e');
      return null;
    }
  }

  Future<void> _pickAndSavePlaylistCover(Playlist playlist, BuildContext pageContext) async {
    if (playlist.id == null) return;
    final path = await _pickCoverImage();
    if (path == null) return;
    final saved = await _saveCoverToAppDir(path, 'playlist_${playlist.id}');
    if (saved != null) {
      await _dao.updatePlaylistCover(playlist.id!, saved);
      if (mounted) {
        Navigator.pop(pageContext);
        _openPlaylist(playlist.copyWith(coverPath: saved));
      }
    }
  }

  Future<void> _editPlaylistDescription(Playlist playlist, BuildContext pageContext) async {
    if (playlist.id == null) return;
    final controller = TextEditingController(text: playlist.description ?? '');
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑简介'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '输入播放列表简介',
            maxLines: 4,
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      final newDesc = result.isEmpty ? null : result;
      await _dao.updatePlaylistDescription(playlist.id!, newDesc);
      if (mounted) {
        Navigator.pop(pageContext);
        _openPlaylist(playlist.copyWith(description: newDesc));
      }
    }
  }

  Future<void> _pickAndSaveArtistCover(Artist artist, List<Song> songs, BuildContext pageContext) async {
    if (artist.id == null) return;
    final path = await _pickCoverImage();
    if (path == null) return;
    final saved = await _saveCoverToAppDir(path, 'artist_${artist.id}');
    if (saved != null) {
      await _dao.updateArtistCover(artist.id!, saved);
      if (mounted) {
        Navigator.pop(pageContext);
        _showAlbumSongs(artist.name, songs, type: 'artist');
      }
    }
  }

  Future<void> _editArtistDescription(Artist artist, List<Song> songs, BuildContext pageContext) async {
    if (artist.id == null) return;
    final controller = TextEditingController(text: artist.description ?? '');
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑简介'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '输入艺术家简介',
            maxLines: 4,
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      final newDesc = result.isEmpty ? null : result;
      await _dao.updateArtistDescription(artist.id!, newDesc);
      if (mounted) {
        Navigator.pop(pageContext);
        _showAlbumSongs(artist.name, songs, type: 'artist');
      }
    }
  }

  Future<void> _pickAndSaveAlbumCover(Album album, List<Song> songs, BuildContext pageContext) async {
    if (album.id == null) return;
    final path = await _pickCoverImage();
    if (path == null) return;
    final saved = await _saveCoverToAppDir(path, 'album_${album.id}');
    if (saved != null) {
      await _dao.updateAlbumCover(album.id!, saved);
      if (mounted) {
        Navigator.pop(pageContext);
        _showAlbumSongs(album.name, songs, type: 'album');
      }
    }
  }

  void _showAlbumSongs(String title, List<Song> songs, {String? type}) async {
    String? coverPath;
    String? description;
    String? subtitle;
    Future<void> Function(BuildContext)? onEditCover;
    Future<void> Function(BuildContext)? onEditDescription;

    if (type == 'artist') {
      final artist = await _dao.getOrCreateArtist(title);
      coverPath = artist.coverPath;
      description = artist.description;
      if (coverPath == null || coverPath.isEmpty && songs.isNotEmpty) {
        final firstWithCover = songs.firstWhere(
          (s) => s.coverPath != null && s.coverPath!.isNotEmpty,
          orElse: () => songs.first,
        );
        coverPath = firstWithCover.coverPath;
      }
      onEditCover = (ctx) => _pickAndSaveArtistCover(artist, songs, ctx);
      onEditDescription = (ctx) => _editArtistDescription(artist, songs, ctx);
    } else if (type == 'album') {
      final albumSongs = songs;
      final album = await _dao.getOrCreateAlbum(
        title,
        artistNames: albumSongs.map((s) => s.artist ?? '未知艺术家').toSet().join(', '),
        coverPath: albumSongs.isEmpty
            ? null
            : albumSongs.firstWhere(
                (s) => s.coverPath != null && s.coverPath!.isNotEmpty,
                orElse: () => albumSongs.first,
              ).coverPath,
      );
      coverPath = album.coverPath;
      final artists = albumSongs.map((s) => s.artist?.trim()).where((a) => a != null && a.isNotEmpty).toSet();
      subtitle = artists.join(', ');
      onEditCover = (ctx) => _pickAndSaveAlbumCover(album, songs, ctx);
    }

    if (!mounted) return;
    final sorted = _sortSongs(songs);
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => _SongListPage(
          title: title,
          songs: sorted,
          onPlay: _playSong,
          onPlayAll: () => _playAll(sorted),
          onMorePressed: _showSongMoreSheet,
          coverPath: coverPath,
          subtitle: subtitle,
          description: description,
          onEditCover: onEditCover,
          onEditDescription: onEditDescription,
          cloudPaths: widget.cloudPaths,
        ),
      ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _PlayAllButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? neutral.surfaceElevated : neutral.divider,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.play_fill,
                  color: Colors.white,
                  size: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '全部播放',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: neutral.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($count 首)',
                style: TextStyle(
                  fontSize: 12,
                  color: neutral.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPlayAllButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _DetailPlayAllButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.play_fill,
              color: Colors.white,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '全部播放',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: neutral.textPrimary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count 首)',
            style: TextStyle(
              fontSize: 12,
              color: neutral.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final Song song;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback? onMorePressed;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final bool isCloud;

  const _SongTile({
    required this.song,
    required this.durationText,
    required this.onTap,
    this.onMorePressed,
    this.onLongPress,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.isCloud = false,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (selectionMode) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: song.coverPath != null
                    ? Image.file(
                        File(song.coverPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 150,
                        errorBuilder: (_, __, ___) => Container(
                          color: neutral.surfaceElevated,
                          child: Icon(CupertinoIcons.music_note, color: neutral.textSecondary, size: 20),
                        ),
                      )
                    : Container(
                        color: neutral.surfaceElevated,
                        child: Icon(CupertinoIcons.music_note, color: neutral.textSecondary, size: 20),
                      ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black.withOpacity(0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  alignment: Alignment.center,
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
                        ? Icon(CupertinoIcons.checkmark, color: Colors.white, size: 14)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          song.displayTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${song.displayArtist} · $durationText',
          style: TextStyle(fontSize: 13, color: neutral.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onToggleSelect,
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: song.coverPath != null
              ? Image.file(
                  File(song.coverPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 150,
                  errorBuilder: (_, __, ___) => Container(
                    color: neutral.surfaceElevated,
                    child: Icon(CupertinoIcons.music_note, color: neutral.textSecondary, size: 20),
                  ),
                )
              : Container(
                  color: neutral.surfaceElevated,
                  child: Icon(CupertinoIcons.music_note, color: neutral.textSecondary, size: 20),
                ),
        ),
      ),
      title: Text(
        song.displayTitle,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.displayArtist,
        style: TextStyle(fontSize: 13, color: neutral.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCloud)
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: FunctionalColors.success,
              size: 14,
            ),
          if (isCloud) const SizedBox(width: 6),
          Text(
            durationText,
            style: TextStyle(fontSize: 13, color: neutral.textTertiary),
          ),
          if (onMorePressed != null) ...[
            const SizedBox(width: 4),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onMorePressed,
              child: Icon(
                CupertinoIcons.ellipsis_vertical,
                color: neutral.textTertiary,
                size: 18,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final String album;
  final String artist;
  final int songCount;
  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback onPlayAlbum;

  const _AlbumCard({
    required this.album,
    required this.artist,
    required this.songCount,
    this.coverPath,
    required this.onTap,
    required this.onPlayAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverPath != null
                      ? Image.file(
                          File(coverPath!),
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, __, ___) => Container(
                            color: neutral.surfaceElevated,
                            child: Icon(CupertinoIcons.music_albums, color: neutral.textTertiary, size: 40),
                          ),
                        )
                      : Container(
                          color: neutral.surfaceElevated,
                          child: Icon(CupertinoIcons.music_albums, color: neutral.textTertiary, size: 40),
                        ),
                  // 播放按钮
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Pressable(
                      onTap: onPlayAlbum,
                      scale: 0.92,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: isDark
                              ? null
                              : [
                                  AppShadows.ambient,
                                ],
                        ),
                        child: const Icon(
                          CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$artist · $songCount 首',
            style: TextStyle(fontSize: 12, color: neutral.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SongListPage extends StatelessWidget {
  final String title;
  final List<Song> songs;
  final void Function(Song) onPlay;
  final VoidCallback? onPlayAll;
  final void Function(Song)? onMorePressed;
  final String? coverPath;
  final String? subtitle;
  final String? description;
  final Future<void> Function(BuildContext)? onEditCover;
  final Future<void> Function(BuildContext)? onEditDescription;
  final Set<String> cloudPaths;

  const _SongListPage({
    required this.title,
    required this.songs,
    required this.onPlay,
    this.onPlayAll,
    this.onMorePressed,
    this.coverPath,
    this.subtitle,
    this.description,
    this.onEditCover,
    this.onEditDescription,
    this.cloudPaths = const {},
  });

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '--:--';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(title),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            pinned: true,
            actions: [
              if (onEditCover != null || onEditDescription != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: () => _showEditMenu(context),
                  child: const Text(
                    '编辑',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  Center(
                    child: GestureDetector(
                      onLongPress: onEditCover != null ? () => onEditCover!(context) : null,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.72,
                        height: MediaQuery.of(context).size.width * 0.72,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            boxShadow: Theme.of(context).brightness == Brightness.dark
                                ? null
                                : [
                                    AppShadows.elevated,
                                  ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            child: coverPath != null
                                ? Image.file(
                                    File(coverPath!),
                                    fit: BoxFit.cover,
                                    cacheWidth: 600,
                                    errorBuilder: (ctx, __, ___) => _buildPlaceholderCover(ctx),
                                  )
                                : _buildPlaceholderCover(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 名称
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // 副标题
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? neutral.textTertiary : neutral.textSecondary,
                      ),
                    ),
                  ],
                  // 简介
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: onEditDescription != null ? () => onEditDescription!(context) : null,
                      child: Text(
                        description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: neutral.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 分隔线
                  Divider(
                    height: 1,
                    color: NeutralPalette.of(context).divider,
                  ),
                  const SizedBox(height: 12),
                  // 全部播放按钮（靠左）
                  if (onPlayAll != null && songs.isNotEmpty)
                    _DetailPlayAllButton(
                      count: songs.length,
                      onTap: onPlayAll!,
                    ),
                ],
              ),
            ),
          ),
          if (songs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  '暂无歌曲',
                  style: TextStyle(color: neutral.textTertiary, fontSize: 15),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return _SongTile(
                  song: song,
                  durationText: _formatDuration(song.duration),
                  onTap: () => onPlay(song),
                  onMorePressed: onMorePressed != null ? () => onMorePressed!(song) : null,
                  onLongPress: onMorePressed != null ? () => onMorePressed!(song) : null,
                  selectionMode: false,
                  isCloud: cloudPaths.contains(song.filePath),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showEditMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          if (onEditCover != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onEditCover!(context);
              },
              child: const Text('更换封面'),
            ),
          if (onEditDescription != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onEditDescription!(context);
              },
              child: const Text('编辑简介'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Container(
      color: neutral.surfaceElevated,
      child: Icon(
        CupertinoIcons.music_albums,
        color: neutral.textTertiary,
        size: 48,
      ),
    );
  }
}

class _PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;
  final List<Song> songs;
  final void Function(Song) onPlay;
  final void Function(Song)? onMorePressed;
  final VoidCallback? onPlayAll;
  final Future<void> Function(BuildContext)? onEditCover;
  final Future<void> Function(BuildContext)? onEditDescription;
  final Set<String> cloudPaths;

  const _PlaylistDetailPage({
    required this.playlist,
    required this.songs,
    required this.onPlay,
    this.onMorePressed,
    this.onPlayAll,
    this.onEditCover,
    this.onEditDescription,
    this.cloudPaths = const {},
  });

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '--:--';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverPath = playlist.coverPath;
    final description = playlist.description;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(playlist.name),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            pinned: true,
            actions: [
              if (onEditCover != null || onEditDescription != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: () => _showEditMenu(context),
                  child: const Text(
                    '编辑',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  Center(
                    child: GestureDetector(
                      onLongPress: onEditCover != null ? () => onEditCover!(context) : null,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.72,
                        height: MediaQuery.of(context).size.width * 0.72,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            boxShadow: Theme.of(context).brightness == Brightness.dark
                                ? null
                                : [
                                    AppShadows.elevated,
                                  ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            child: coverPath != null
                                ? Image.file(
                                    File(coverPath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 600,
                                    errorBuilder: (ctx, __, ___) => _buildPlaceholderCover(ctx),
                                  )
                                : _buildPlaceholderCover(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 名称
                  Text(
                    playlist.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // 简介
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: onEditDescription != null ? () => onEditDescription!(context) : null,
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: neutral.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 分隔线
                  Divider(
                    height: 1,
                    color: NeutralPalette.of(context).divider,
                  ),
                  const SizedBox(height: 12),
                  // 全部播放按钮（靠左）
                  if (onPlayAll != null && songs.isNotEmpty)
                    _DetailPlayAllButton(
                      count: songs.length,
                      onTap: onPlayAll!,
                    ),
                ],
              ),
            ),
          ),
          if (songs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  '播放列表为空',
                  style: TextStyle(color: neutral.textTertiary, fontSize: 15),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                return _SongTile(
                  song: song,
                  durationText: _formatDuration(song.duration),
                  onTap: () => onPlay(song),
                  onMorePressed: onMorePressed != null ? () => onMorePressed!(song) : null,
                  onLongPress: onMorePressed != null ? () => onMorePressed!(song) : null,
                  selectionMode: false,
                  isCloud: cloudPaths.contains(song.filePath),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showEditMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          if (onEditCover != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onEditCover!(context);
              },
              child: const Text('更换封面'),
            ),
          if (onEditDescription != null)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                onEditDescription!(context);
              },
              child: const Text('编辑简介'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Container(
      color: neutral.surfaceElevated,
      child: Icon(
        CupertinoIcons.music_albums,
        color: neutral.textTertiary,
        size: 48,
      ),
    );
  }
}
