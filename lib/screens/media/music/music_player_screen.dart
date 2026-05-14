import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'dart:io';
import 'dart:math' show pi, cos, sin;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/song.dart';
import '../../../services/music_player_service.dart';
import 'music_queue_screen.dart';
import 'music_lyrics_view.dart';
import 'sleep_timer_sheet.dart';
import 'music_library_view.dart';
import 'cover_driven_background.dart';
import 'eq_settings_sheet.dart';
import '../../../database/song_dao.dart';
import '../../../database/library_dao.dart';
import '../../../services/metadata_service.dart';
import '../../../services/music_player_settings.dart';
import 'tag_edit_sheet.dart';
import 'vinyl_disc_painter.dart';
import '../../../widgets/pressable.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  static bool isOpen = false;

  static Route<dynamic> route() {
    return PageRouteBuilder<dynamic>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (context, animation, secondaryAnimation) => const MusicPlayerScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
    );
  }

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with TickerProviderStateMixin {
  final MusicPlayerService _service = MusicPlayerService.instance;
  final SongDao _dao = SongDao();
  late AnimationController _rotationController;
  late AnimationController _toneArmController;
  late Animation<double> _toneArmAngle;
  late AnimationController _toneArmTrackController;
  late Animation<double> _toneArmTrackOffset;
  late PageController _pageController;
  final ValueNotifier<double?> _dragValueNotifier = ValueNotifier(null);
  bool _showLyrics = false;
  bool _isOpeningQueue = false;
  bool _isVinylMode = false;
  bool _showVinylCenterDot = true;
  BackgroundMode _bgMode = BackgroundMode.extreme;
  final ValueNotifier<double> _dragOffsetNotifier = ValueNotifier(0.0);

  // 唱针拖拽状态
  double _toneArmDragStart = 0;
  double _toneArmDragCurrent = 0;

  @override
  void initState() {
    super.initState();
    MusicPlayerScreen.isOpen = true;
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _toneArmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _toneArmController.value = _service.isPlaying ? 1.0 : 0.0;
    _toneArmAngle = Tween<double>(
      begin: -0.9,  // 暂停：远离唱片
      end: -0.35,   // 播放：靠近唱片
    ).animate(CurvedAnimation(
      parent: _toneArmController,
      curve: Curves.easeInOutCubic,
    ));
    _toneArmTrackController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _toneArmTrackOffset = Tween<double>(
      begin: -0.03,
      end: 0.03,
    ).animate(CurvedAnimation(
      parent: _toneArmTrackController,
      curve: Curves.easeInOutSine,
    ));
    _pageController = PageController();
    _service.addListener(_onServiceUpdate);
    _updateRotation();
    _updateToneArm();
    _loadPlayerSettings();
  }

  Future<void> _loadPlayerSettings() async {
    final mode = await MusicPlayerSettings.getVinylMode();
    final showDot = await MusicPlayerSettings.getShowVinylCenterDot();
    final bgMode = await MusicPlayerSettings.getBackgroundMode();
    if (mounted) {
      setState(() {
        _isVinylMode = mode;
        _showVinylCenterDot = showDot;
        _bgMode = bgMode;
      });
    }
  }

  void _toggleCoverStyle() {
    setState(() => _isVinylMode = !_isVinylMode);
    MusicPlayerSettings.setVinylMode(_isVinylMode);
    _updateToneArm();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _pageController.dispose();
    _rotationController.dispose();
    _toneArmController.dispose();
    _toneArmTrackController.dispose();
    _dragOffsetNotifier.dispose();
    MusicPlayerScreen.isOpen = false;
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _updateRotation();
      _updateToneArm();
    }
  }

  void _updateRotation() {
    if (!mounted) return;
    if (_service.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      _rotationController.stop();
    }
  }

  void _snapBackAnimation() {
    final startValue = _dragOffsetNotifier.value;
    if (startValue == 0) return;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );
    animation.addListener(() {
      _dragOffsetNotifier.value = startValue * (1 - animation.value);
    });
    controller.forward().then((_) {
      _dragOffsetNotifier.value = 0;
      controller.dispose();
    });
  }

  void _updateToneArm() {
    if (!_isVinylMode) return;
    if (_service.isPlaying) {
      _toneArmController.forward();
      _toneArmTrackController.repeat(reverse: true);
    } else {
      _toneArmController.reverse();
      _toneArmTrackController.stop();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _showMoreSheet() async {
    final song = _service.currentSong;
    bool isFav = false;
    if (song?.id != null) {
      isFav = await _dao.isFavorite(song!.id!);
    }
    if (!mounted) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              showCupertinoModalPopup(
                context: context,
                builder: (_) => const SleepTimerSheet(),
              );
            },
            child: const Text('定时关闭'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _toggleFavoriteAndPop(isFav),
            child: Text(isFav ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _addToPlaylistAndPop(),
            child: const Text('添加到播放列表'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _updateMetadataAndPop(),
            child: const Text('更新元数据'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _editTagAndPop(),
            child: const Text('编辑标签'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _showSpeedPickerAndPop(),
            child: Text('播放速度 (${_service.speed}x)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _showEqAndPop(),
            child: const Text('均衡器'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _showBgModePickerAndPop(),
            child: Text('背景特效 (${MusicPlayerSettings.backgroundModeLabel(_bgMode)})'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => _deleteSongAndPop(),
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

  Future<void> _toggleFavoriteAndPop(bool isFav) async {
    Navigator.pop(context);
    final s = _service.currentSong;
    if (s?.id != null) {
      await _dao.toggleFavorite(s!.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFav ? '已取消收藏' : '已收藏'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralColorsDark.surfaceElevated,
          ),
        );
      }
    }
  }

  Future<void> _addToPlaylistAndPop() async {
    Navigator.pop(context);
    final s = _service.currentSong;
    if (s?.id != null) {
      final playlists = await _dao.getAllPlaylists();
      if (!mounted) return;
      showCupertinoModalPopup(
        context: context,
        builder: (_) => CupertinoActionSheet(
          title: const Text('添加到播放列表'),
          actions: playlists.map((p) => CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _dao.addSongToPlaylist(p.id!, s!.id!);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已添加到 ${p.name}'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: NeutralColorsDark.surfaceElevated,
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
  }

  void _showSpeedPickerAndPop() {
    Navigator.pop(context);
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('播放速度'),
        actions: speeds.map((speed) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            _service.setSpeed(speed);
          },
          child: Text(
            '${speed}x',
            style: TextStyle(
              color: _service.speed == speed
                  ? AppColors.primary
                  : Colors.black,
              fontWeight: _service.speed == speed
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showEqAndPop() {
    Navigator.pop(context);
    showCupertinoModalPopup(
      context: context,
      builder: (_) => const EqSettingsSheet(),
    );
  }

  void _showBgModePickerAndPop() {
    Navigator.pop(context);
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('背景特效'),
        actions: BackgroundMode.values.map((mode) {
          final isSelected = _bgMode == mode;
          return CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await MusicPlayerSettings.setBackgroundMode(mode);
              setState(() => _bgMode = mode);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(MusicPlayerSettings.backgroundModeLabel(mode)),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.check_mark, size: 16, color: AppColors.primary),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _editTagAndPop() {
    Navigator.pop(context);
    final song = _service.currentSong;
    if (song == null) return;
    showCupertinoModalPopup(
      context: context,
      builder: (_) => TagEditSheet(song: song),
    );
  }

  Future<void> _toggleVinylCenterDotAndPop() async {
    Navigator.pop(context);
    final newValue = !_showVinylCenterDot;
    await MusicPlayerSettings.setShowVinylCenterDot(newValue);
    setState(() => _showVinylCenterDot = newValue);
  }

  Future<void> _deleteSongAndPop() async {
    Navigator.pop(context);
    final song = _service.currentSong;
    if (song == null) return;
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('确认删除', style: TextStyle(color: neutral.textPrimary)),
        content: Text(
          '删除后可在回收站找回，是否继续？',
          style: TextStyle(color: isDark ? neutral.textPrimary.withOpacity(0.7) : neutral.textPrimary.withOpacity(0.87)),
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
    final libraryItem = await LibraryDao().getItemByPath(song.filePath);
    if (libraryItem?.id != null) {
      await LibraryDao().deleteItem(libraryItem!.id!);
      MusicLibraryView.globalKey.currentState?.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '已移至回收站，可在回收站中找回',
              style: TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: isDark ? NeutralColorsDark.surfaceElevated : NeutralColorsDark.divider,
          ),
        );
      }
    }
  }

  Future<void> _updateMetadataAndPop() async {
    Navigator.pop(context);
    final s = _service.currentSong;
    if (s?.id == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在更新元数据...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: NeutralColorsDark.surfaceElevated,
        ),
      );
    }

    try {
      final result = await MetadataService.instance.readMetadata(s!.filePath);
      String? coverPath = s.coverPath;
      if (result.coverBytes != null) {
        coverPath = await MetadataService.instance.saveCoverImage(
          result.coverBytes!,
          s.filePath,
        );
      }

      final updatedSong = s.copyWith(
        title: result.title,
        artist: result.artist,
        album: result.album,
        duration: result.durationMs,
        coverPath: coverPath,
        embeddedLyrics: result.lyrics,
      );

      await _dao.updateSongMetadata(updatedSong);
      _service.updateSongInQueue(updatedSong);
      MusicLibraryView.globalKey.currentState?.refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('元数据已更新'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralColorsDark.surfaceElevated,
          ),
        );
      }
    } catch (e) {
      debugPrint('更新元数据失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失败: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: NeutralColorsDark.surfaceElevated,
          ),
        );
      }
    }
  }

  void _toggleLyrics() {
    final newValue = !_showLyrics;
    setState(() => _showLyrics = newValue);
    _pageController.animateToPage(
      newValue ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _showLyrics = index == 1);
  }

  void _showQueue() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => const MusicQueueScreen(),
    );
  }

  IconData _getModeIcon() {
    switch (_service.playMode) {
      case PlayMode.loopAll:
        return CupertinoIcons.arrow_2_circlepath;
      case PlayMode.loopOne:
        return CupertinoIcons.repeat_1;
      case PlayMode.shuffle:
        return CupertinoIcons.shuffle;
    }
  }

  void _showModeToast() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _getModeLabel(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        backgroundColor: NeutralColorsDark.surfaceElevated.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
        margin: EdgeInsets.only(bottom: screenHeight * 0.45, left: 120, right: 120),
        elevation: 0,
      ),
    );
  }

  String _getModeLabel() {
    switch (_service.playMode) {
      case PlayMode.loopAll:
        return '列表循环';
      case PlayMode.loopOne:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  Widget _buildFavoriteButton() {
    final song = _service.currentSong;
    if (song?.id == null) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: null,
        child: Icon(
          CupertinoIcons.heart,
          color: Colors.white.withOpacity(0.7),
          size: 20,
        ),
      );
    }
    final s = song!;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () async {
        final wasFav = await _dao.isFavorite(s.id!);
        await _dao.toggleFavorite(s.id!);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(wasFav ? '已取消收藏' : '已收藏'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
              backgroundColor: NeutralColorsDark.surfaceElevated,
            ),
          );
        }
      },
      child: FutureBuilder<bool>(
        future: _dao.isFavorite(s.id!),
        builder: (context, snapshot) {
          final isFav = snapshot.data ?? false;
          return Icon(
            isFav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: isFav ? FunctionalColors.error : NeutralColorsDark.textTertiary,
            size: 20,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _service.currentSong;
    final screenHeight = MediaQuery.of(context).size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _dragOffsetNotifier,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _dragOffsetNotifier.value),
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: child!,
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 0: 动态氛围背景
              Positioned.fill(
                child: _buildDynamicBackground(),
              ),

              // Layer 1: 内容层
              SafeArea(
                child: Column(
                  children: [
                  // 顶部栏
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 左边返回按钮
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            child: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 28),
                          ),
                        ),
                        // 中间标题 — 绝对居中
                        Pressable(
                          onTap: _toggleLyrics,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _showLyrics ? '歌词' : '正在播放',
                              key: ValueKey(_showLyrics),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // 右边按钮组
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _toggleCoverStyle,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    _isVinylMode
                                        ? CupertinoIcons.square
                                        : CupertinoIcons.circle,
                                    key: ValueKey(_isVinylMode),
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _showMoreSheet,
                                child: const Icon(CupertinoIcons.ellipsis, color: Colors.white, size: 24),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 封面 / 歌词 切换区域 + 歌曲信息（共享手势区域）
                  Expanded(
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        if (details.delta.dy > 0) {
                          _dragOffsetNotifier.value += details.delta.dy;
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (_dragOffsetNotifier.value > 150 && details.primaryVelocity != null && details.primaryVelocity! > 200) {
                          Navigator.pop(context);
                        } else {
                          _snapBackAnimation();
                        }
                      },
                      child: Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: song == null
                                ? const SizedBox.shrink()
                                : PageView(
                                    controller: _pageController,
                                    onPageChanged: _onPageChanged,
                                    clipBehavior: Clip.none,
                                    children: [
                                      // 第 0 页：封面 + 歌曲信息（一起滑动）
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 56),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Center(
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  alignment: Alignment.center,
                                                  children: [
                                                    AspectRatio(
                                                      aspectRatio: 1,
                                                      child: _buildCover(song),
                                                    ),
                                                    if (_isVinylMode && song != null)
                                                      _buildToneArm(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 40),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 0),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    song.displayTitle,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    song.displayArtist,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 32),
                                          ],
                                        ),
                                      ),
                                      // 第 1 页：歌词（共享全屏氛围背景，无独立背景层）
                                      MusicLyricsView(
                                        key: ValueKey(song.filePath),
                                        song: song,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!_showLyrics) ...[
                    // 进度条
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: StreamBuilder<Duration>(
                          stream: _service.positionStream,
                          builder: (context, positionSnapshot) {
                            return ValueListenableBuilder<double?>(
                              valueListenable: _dragValueNotifier,
                              builder: (context, dragValue, _) {
                                final position = dragValue != null
                                    ? Duration(milliseconds: (dragValue * (_service.duration.inMilliseconds)).toInt())
                                    : positionSnapshot.data ?? Duration.zero;
                                final duration = _service.duration;
                                final value = duration.inMilliseconds > 0
                                    ? (dragValue ?? position.inMilliseconds / duration.inMilliseconds)
                                    : 0.0;

                                return Column(
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: NeutralColorsDark.divider,
                                    thumbColor: Colors.white,
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: SliderComponentShape.noOverlay,
                                  ),
                                  child: Slider(
                                    value: value.clamp(0.0, 1.0),
                                    onChangeStart: (_) => _dragValueNotifier.value = value,
                                    onChanged: (v) => _dragValueNotifier.value = v,
                                    onChangeEnd: (v) {
                                      _dragValueNotifier.value = null;
                                      _service.seek(Duration(
                                        milliseconds: (v * duration.inMilliseconds).toInt(),
                                      ));
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: TextStyle(
                                          color: NeutralColorsDark.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: TextStyle(
                                          color: NeutralColorsDark.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                      // 主控制按钮（上一首 / 播放暂停 / 下一首）
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // 上一首
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _service.previous,
                              child: const Icon(
                                CupertinoIcons.backward_fill,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            // 播放/暂停
                            StreamBuilder<bool>(
                              stream: _service.playingStream,
                              builder: (context, snapshot) {
                                final isPlaying = snapshot.data ?? false;
                                return CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: _service.togglePlay,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? CupertinoIcons.pause_fill
                                          : CupertinoIcons.play_fill,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                );
                              },
                            ),
                            // 下一首
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _service.next,
                              child: const Icon(
                                CupertinoIcons.forward_fill,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // 辅助控制按钮（词 / 播放顺序 / 音量 / 更多）— 均分整行宽度
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _service.togglePlayMode();
                                  _showModeToast();
                                },
                                child: Icon(
                                  _getModeIcon(),
                                  color: Colors.white.withOpacity(0.7),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _showQueue,
                                child: Icon(
                                  CupertinoIcons.list_bullet,
                                  color: Colors.white.withOpacity(0.7),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: _buildFavoriteButton(),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: _toggleLyrics,
                                child: Text(
                                  '词',
                                  style: TextStyle(
                                    color: _showLyrics
                                        ? AppColors.primary
                                        : Colors.white.withOpacity(0.7),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),

              // Layer 2: 底部渐变遮罩（确保控制按钮可读，不拦截触摸）
              if (!_showLyrics)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 200,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            NeutralColorsDark.surface.withOpacity(0.0),
                            NeutralColorsDark.surface.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBackground() {
    return CoverDrivenBackground(
      key: ValueKey(_bgMode),
      coverPath: _service.currentSong?.coverPath,
      mode: _bgMode,
    );
  }

  Widget _buildCover(Song? song) {
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _isVinylMode
            ? _buildVinylRecord(song, key: ValueKey('vinyl_${song?.filePath ?? 'empty'}'))
            : _buildSquareCover(song, key: ValueKey('square_${song?.filePath ?? 'empty'}')),
      ),
    );
  }

  Widget _buildSquareCover(Song? song, {required Key key}) {
    Widget cover;
    if (song?.coverPath != null) {
      cover = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Image.file(
          File(song!.coverPath!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: 600,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: NeutralPalette.dark.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Center(
              child: Icon(CupertinoIcons.music_note, color: NeutralColorsDark.textPrimary.withOpacity(0.38), size: 80),
            ),
          ),
        ),
      );
    } else {
      cover = Container(
        decoration: BoxDecoration(
          color: NeutralPalette.dark.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Center(
          child: Icon(CupertinoIcons.music_note, color: NeutralColorsDark.textPrimary.withOpacity(0.38), size: 80),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: key,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.medium)),
        boxShadow: isDark ? null : [AppShadows.cover],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: cover,
      ),
    );
  }

  Widget _buildVinylRecord(Song? song, {required Key key}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget coverImage;
    if (song?.coverPath != null) {
      coverImage = Image.file(
        File(song!.coverPath!),
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: (_, __, ___) => Container(
          color: NeutralColorsDark.surfaceElevated,
          child: Icon(CupertinoIcons.music_note, color: NeutralColorsDark.textPrimary.withOpacity(0.38), size: 48),
        ),
      );
    } else {
      coverImage = Container(
        color: NeutralColorsDark.surfaceElevated,
        child: Center(
          child: Icon(CupertinoIcons.music_note, color: NeutralColorsDark.textPrimary.withOpacity(0.38), size: 48),
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotationController.value * 2 * pi,
            child: child!,
          );
        },
        child: Container(
        key: key,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isDark
              ? null
              : [
                  AppShadows.cover,
                ],
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: VinylDiscPainter()),
              ),
              FractionallySizedBox(
                widthFactor: 0.50,
                heightFactor: 0.50,
                child: ClipOval(child: coverImage),
              ),
              if (_showVinylCenterDot)
                FractionallySizedBox(
                  widthFactor: 0.0625,
                  heightFactor: 0.0625,
                  child: Container(
                    decoration: BoxDecoration(
                      color: NeutralColorsDark.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: NeutralColorsDark.divider, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildToneArm() {
    const armSize = Size(150, 200);
    return Positioned(
      top: -18,
      right: -18,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_toneArmAngle, _toneArmTrackOffset]),
          builder: (context, child) {
            final angle = _toneArmAngle.value + _toneArmTrackOffset.value;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _service.togglePlay(),
              onPanStart: (_) {
                _toneArmDragStart = _toneArmController.value;
                _toneArmDragCurrent = _toneArmDragStart;
              },
              onPanUpdate: (details) {
                _toneArmDragCurrent += details.delta.dy / 100;
                _toneArmDragCurrent = _toneArmDragCurrent.clamp(0.0, 1.0);
                _toneArmController.value = _toneArmDragCurrent;
              },
              onPanEnd: (_) {
                if (_toneArmDragCurrent > 0.5) {
                  _toneArmController.forward();
                  if (!_service.isPlaying) _service.play();
                } else {
                  _toneArmController.reverse();
                  if (_service.isPlaying) _service.pause();
                }
              },
              child: SizedBox(
                width: armSize.width,
                height: armSize.height,
                child: CustomPaint(
                  size: armSize,
                  painter: _ToneArmPainter(angle: angle),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 简约白色系唱针 — Apple 风格
class _ToneArmPainter extends CustomPainter {
  final double angle;

  const _ToneArmPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width * 0.82, size.height * 0.06);

    canvas.save();
    // 绕枢轴点旋转：先移到原点 → 旋转 → 移回来
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    canvas.translate(-pivot.dx, -pivot.dy);

    // 1. 枢轴外圈（柔和白）
    canvas.drawCircle(
      pivot,
      14,
      Paint()
        ..color = const Color(0xFFE5E5EA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 2. 枢轴主体
    canvas.drawCircle(
      pivot,
      11,
      Paint()..color = const Color(0xFFF2F2F7),
    );

    // 3. 枢轴内凹
    canvas.drawCircle(
      pivot,
      5,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // 4. 唱臂路径 — 从枢轴到唱头
    final armLength = size.width * 0.78;
    const armAngle = 2.18;
    final cartridgePos = Offset(
      pivot.dx + armLength * cos(armAngle),
      pivot.dy + armLength * sin(armAngle),
    );

    // 主臂：粗圆角白线
    final armPaint = Paint()
      ..color = const Color(0xFFF2F2F7)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, cartridgePos, armPaint);

    // 臂内高光（增加立体感）
    final armHighlightPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final hOffset = const Offset(-1.5, -1.5);
    canvas.drawLine(pivot + hOffset, cartridgePos + hOffset, armHighlightPaint);

    // 5. 唱头外壳
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: cartridgePos, width: 12, height: 16),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFE5E5EA),
    );

    // 唱头内壳
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: cartridgePos, width: 7, height: 11),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // 6. 唱针尖端（微小白点）
    final needleTip = Offset(
      cartridgePos.dx + 7 * cos(armAngle + pi / 2),
      cartridgePos.dy + 7 * sin(armAngle + pi / 2),
    );
    canvas.drawCircle(
      needleTip,
      2.5,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ToneArmPainter old) => old.angle != angle;
}
