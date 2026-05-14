import 'package:local_library/design_tokens/app_colors.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/library_item.dart';
import '../../models/reading_progress.dart';
import '../../database/library_dao.dart';
import '../../services/video_filename_parser.dart';

class VideoPlayerScreen extends StatefulWidget {
  final LibraryItem item;

  /// 云端串流 URL，传入后优先用 URL 播放，不走本地文件逻辑
  final String? streamUrl;

  /// 同系列剧集列表（用于选集），传入后优先使用该列表
  final List<LibraryItem>? episodes;

  const VideoPlayerScreen({super.key, required this.item, this.streamUrl, this.episodes});

  bool get _isStreaming => streamUrl != null && streamUrl!.isNotEmpty;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

/// 用于 isolate 中过滤剧集的参数
class _EpisodeFilterArgs {
  final String currentFilePath;
  final List<LibraryItem> allItems;

  _EpisodeFilterArgs({required this.currentFilePath, required this.allItems});
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  Player? _player;
  VideoController? _controller;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLocked = false;
  final LibraryDao _dao = LibraryDao();
  List<String> _subtitleFiles = [];
  int _currentSubtitleIndex = -1;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<bool>? _completedSub;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  // 同系列剧集
  List<LibraryItem> _seriesEpisodes = [];
  int _currentEpisodeIndex = 0;
  late LibraryItem _currentItem;

  // 播放设置
  double _playbackRate = 1.0;
  double _normalRate = 1.0;
  bool _isLongPressSpeed = false;
  BoxFit _videoFit = BoxFit.contain;
  _LoopMode _loopMode = _LoopMode.none;

  // 音轨/字幕轨道
  List<AudioTrack> _audioTracks = [];
  int _currentAudioIndex = -1;
  List<SubtitleTrack> _embeddedSubtitles = [];

  // 手势控制状态
  double _dragStartX = 0;
  double _dragStartY = 0;
  double _gestureStartBrightness = 0.5;
  double _gestureStartVolume = 0.5;
  Duration _gestureStartPosition = Duration.zero;
  _GestureType _currentGesture = _GestureType.none;
  double _gestureValue = 0; // 亮度/音量/进度变化值
  bool _showGestureIndicator = false;
  Timer? _gestureIndicatorTimer;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;

  // 待恢复的播放进度（等视频加载完成后再 seek）
  Duration? _pendingSeekPosition;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    WakelockPlus.enable();
    _initializePlayer();
    _initGestureValues();
  }

  Future<void> _initGestureValues() async {
    try {
      final brightness = await ScreenBrightness().current;
      final volume = await VolumeController.instance.getVolume();
      if (mounted) {
        setState(() {
          _currentBrightness = brightness.clamp(0.0, 1.0);
          _currentVolume = volume.clamp(0.0, 1.0);
        });
      }
    } catch (e) {
      debugPrint('初始化亮度/音量失败: $e');
    }
  }

  Future<void> _initializePlayer() async {
    _player = Player();
    _controller = VideoController(_player!);

    final mediaSource = widget.streamUrl ?? widget.item.filePath;
    await _player!.open(Media(mediaSource));

    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      // 传入的剧集列表（云端电视剧等场景）
      _seriesEpisodes = List.from(widget.episodes!);
      _currentEpisodeIndex = _seriesEpisodes.indexWhere(
        (e) => e.filePath == widget.item.filePath,
      );
      if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    } else if (widget.streamUrl == null) {
      // 本地文件逻辑：查找同系列、字幕、恢复进度
      await _findSeriesEpisodes();
      await _findSubtitleFiles();
      if (_subtitleFiles.isNotEmpty) {
        await _loadSubtitle(_subtitleFiles.first);
      }

      final progress = await _dao.getProgress(widget.item.id!);
      debugPrint('[VideoPlayer] 恢复进度: itemId=${widget.item.id}, progress=$progress');
      if (progress != null && progress.position > 0) {
        _pendingSeekPosition = Duration(seconds: progress.position);
        debugPrint('[VideoPlayer] 设置待恢复位置: ${_pendingSeekPosition!.inSeconds}s');
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    // 监听播放进度并保存（仅本地文件）
    _positionSub = _player!.stream.position.listen((position) {
      if (widget.streamUrl != null) return;
      if (position.inSeconds > 0 && position.inSeconds % 5 == 0) {
        debugPrint('[VideoPlayer] 定期保存进度: ${position.inSeconds}s');
        _saveProgress(position);
      }
    });

    // 缓存 duration
    _durationSub = _player!.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
      // 本地文件：恢复 seek
      if (widget.streamUrl == null &&
          duration.inMilliseconds > 0 &&
          _pendingSeekPosition != null) {
        debugPrint('[VideoPlayer] duration=$duration, 准备seek到 ${_pendingSeekPosition!.inSeconds}s');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_player != null && _pendingSeekPosition != null) {
            _player!.seek(_pendingSeekPosition!);
            debugPrint('[VideoPlayer] 已执行seek到 ${_pendingSeekPosition!.inSeconds}s');
            _pendingSeekPosition = null;
          }
        });
      }
      // 本地文件：保存总时长
      if (widget.streamUrl == null &&
          duration.inSeconds > 0 &&
          _currentItem.totalProgress == null) {
        _dao.updateItemTotalProgress(_currentItem.id!, duration.inSeconds);
        _currentItem = _currentItem.copyWith(totalProgress: duration.inSeconds);
      }
    });

    // 监听缓冲进度
    _bufferSub = _player!.stream.buffer.listen((buffer) {
      if (mounted) setState(() => _buffer = buffer);
    });

    // 监听轨道变化（音轨/字幕轨）
    _tracksSub = _player!.stream.tracks.listen((tracks) {
      if (!mounted) return;
      setState(() {
        _audioTracks = tracks.audio.where((t) => t.id != 'no').toList();
        _embeddedSubtitles = tracks.subtitle.where((t) => t.id != 'no').toList();
      });
    });

    // 监听播放完成，处理连播/循环（仅本地文件）
    _completedSub = _player!.stream.completed.listen((completed) {
      if (completed && mounted && widget.streamUrl == null) {
        _onPlaybackCompleted();
      }
    });
  }

  Future<void> _findSubtitleFiles() async {
    final file = File(widget.item.filePath);
    if (!await file.exists()) return;

    final dir = file.parent;
    if (!await dir.exists()) return;

    final baseName = path.basenameWithoutExtension(widget.item.filePath);
    final extensions = ['.srt', '.ass', '.ssa', '.vtt'];
    final subtitles = <String>[];

    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        final entityBaseName = path.basenameWithoutExtension(entity.path);
        if (extensions.contains(ext) && entityBaseName.startsWith(baseName)) {
          subtitles.add(entity.path);
        }
      }
    }

    if (!mounted) return;
    setState(() => _subtitleFiles = subtitles);
  }

  Future<void> _findSeriesEpisodes() async {
    final allItems = await _dao.getItemsByType(MediaType.video);
    final episodes = await compute(_filterEpisodesInIsolate, _EpisodeFilterArgs(
      currentFilePath: widget.item.filePath,
      allItems: allItems,
    ));
    final currentIndex = episodes.indexWhere((e) => e.filePath == widget.item.filePath);
    if (!mounted) return;
    setState(() {
      _seriesEpisodes = episodes;
      _currentEpisodeIndex = currentIndex >= 0 ? currentIndex : 0;
    });
  }

  static List<LibraryItem> _filterEpisodesInIsolate(_EpisodeFilterArgs args) {
    final currentParse = VideoFilenameParser.parse(args.currentFilePath);
    if (!currentParse.hasEpisodeInfo) return [];
    final seriesName = currentParse.seriesName.trim();
    if (seriesName.isEmpty) return [];

    final episodes = args.allItems.where((item) {
      final parse = VideoFilenameParser.parse(item.filePath);
      return parse.seriesName.trim() == seriesName && parse.hasEpisodeInfo;
    }).toList();

    episodes.sort((a, b) {
      final pa = VideoFilenameParser.parse(a.filePath);
      final pb = VideoFilenameParser.parse(b.filePath);
      final sa = pa.seasonNumber ?? 1;
      final sb = pb.seasonNumber ?? 1;
      if (sa != sb) return sa.compareTo(sb);
      final ea = pa.episodeNumber ?? 0;
      final eb = pb.episodeNumber ?? 0;
      return ea.compareTo(eb);
    });

    return episodes;
  }

  Future<void> _loadSubtitle(String subtitlePath) async {
    try {
      await _player!.setSubtitleTrack(
        SubtitleTrack.uri(subtitlePath),
      );
    } catch (_) {
      // 字幕加载失败不影响播放
    }
  }

  void _showSubtitleSelector() {
    final hasAnySubtitle = _subtitleFiles.isNotEmpty || _embeddedSubtitles.isNotEmpty;
    if (!hasAnySubtitle) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('字幕'),
          content: const Text('未找到字幕\n\n该视频不含内嵌字幕，也未找到同目录外挂字幕文件'),
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

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择字幕'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              await _player!.setSubtitleTrack(SubtitleTrack.no());
              setState(() => _currentSubtitleIndex = -1);
              Navigator.pop(context);
            },
            child: const Text('关闭字幕'),
          ),
          // 内嵌字幕轨
          if (_embeddedSubtitles.isNotEmpty) ...[
            ..._embeddedSubtitles.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final label = track.title?.isNotEmpty == true
                  ? track.title!
                  : track.language?.isNotEmpty == true
                      ? '[${track.language}] 内嵌字幕'
                      : '内嵌字幕 ${index + 1}';
              final globalIndex = index; // 内嵌字幕用负索引区分：-1 - index
              return CupertinoActionSheetAction(
                onPressed: () async {
                  await _player!.setSubtitleTrack(track);
                  setState(() => _currentSubtitleIndex = -2 - globalIndex);
                  Navigator.pop(context);
                },
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: (-2 - index) == _currentSubtitleIndex
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              );
            }),
          ],
          // 外挂字幕文件
          ..._subtitleFiles.asMap().entries.map((entry) {
            final index = entry.key;
            final filePath = entry.value;
            final fileName = path.basename(filePath);
            // 外挂字幕索引从 0 开始，正值
            return CupertinoActionSheetAction(
              onPressed: () async {
                await _loadSubtitle(filePath);
                setState(() => _currentSubtitleIndex = index);
                Navigator.pop(context);
              },
              child: Text(
                fileName,
                style: TextStyle(
                  fontWeight: index == _currentSubtitleIndex
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            );
          }),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showEpisodeSelector() {
    if (_seriesEpisodes.isEmpty) return;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选集'),
        actions: _seriesEpisodes.asMap().entries.map((entry) {
          final index = entry.key;
          final episode = entry.value;
          // 云端条目用 title，本地文件用文件名解析
          final label = episode.streamUrl != null
              ? episode.title
              : VideoFilenameParser.parse(episode.filePath).displayLabel;
          final isCurrent = index == _currentEpisodeIndex;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              if (!isCurrent) {
                _switchToEpisode(episode);
              }
            },
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                color: isCurrent ? AppColors.primary : null,
              ),
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

  Future<void> _switchToEpisode(LibraryItem episode) async {
    // 保存当前进度（仅本地文件）
    if (widget.streamUrl == null) {
      try {
        await _saveProgress(_player!.state.position);
      } catch (e) {
        debugPrint('切换剧集时保存进度失败: $e');
      }
    }

    // 重置待恢复进度
    _pendingSeekPosition = null;

    // 重新加载播放器
    setState(() => _isLoading = true);

    final mediaSource = episode.streamUrl ?? episode.filePath;
    await _player!.open(Media(mediaSource));

    // 恢复播放设置
    await _player!.setRate(_playbackRate);

    // 本地文件：查找新视频的字幕和音轨
    if (episode.streamUrl == null) {
      _subtitleFiles = [];
      _currentSubtitleIndex = -1;
      _currentAudioIndex = -1;
      await _findSubtitleFiles();
      if (_subtitleFiles.isNotEmpty) {
        await _loadSubtitle(_subtitleFiles.first);
      }

      // 恢复播放进度（等视频加载完成后再 seek）
      final progress = await _dao.getProgress(episode.id!);
      if (progress != null && progress.position > 0) {
        _pendingSeekPosition = Duration(seconds: progress.position);
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _currentItem = episode;
      _currentEpisodeIndex = _seriesEpisodes.indexWhere((e) => e.filePath == episode.filePath);
    });
  }

  // ===================== 倍速播放 =====================

  void _showPlaybackRateSelector() {
    final rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('播放速度'),
        actions: rates.map((rate) {
          final label = rate == 1.0 ? '正常' : '${rate}x';
          final isCurrent = (_playbackRate - rate).abs() < 0.01;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _setPlaybackRate(rate);
            },
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                color: isCurrent ? AppColors.primary : null,
              ),
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

  void _setPlaybackRate(double rate) {
    _player?.setRate(rate);
    setState(() {
      _playbackRate = rate;
      _normalRate = rate;
    });
  }

  void _onLongPressStart() {
    if (_player == null) return;
    _isLongPressSpeed = true;
    _player!.setRate(2.0);
    _gestureIndicatorTimer?.cancel();
    setState(() => _showGestureIndicator = true);
  }

  void _onLongPressEnd() {
    if (_player == null) return;
    _isLongPressSpeed = false;
    _player!.setRate(_normalRate);
    _gestureIndicatorTimer?.cancel();
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showGestureIndicator = false);
    });
    setState(() {});
  }

  // ===================== 画面比例 =====================

  void _showVideoFitSelector() {
    final fits = [
      (BoxFit.contain, '适应', '保持比例，完整显示'),
      (BoxFit.cover, '填充', '填满屏幕，可能裁剪'),
      (BoxFit.fill, '拉伸', '强制铺满，可能变形'),
    ];
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('画面比例'),
        actions: fits.map((fit) {
          final isCurrent = _videoFit == fit.$1;
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _videoFit = fit.$1);
            },
            child: Text(
              fit.$2,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                color: isCurrent ? AppColors.primary : null,
              ),
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

  // ===================== 音轨切换 =====================

  void _showAudioTrackSelector() {
    if (_audioTracks.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('音轨'),
          content: const Text('该视频只有单一音轨'),
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

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择音轨'),
        actions: _audioTracks.asMap().entries.map((entry) {
          final index = entry.key;
          final track = entry.value;
          final label = track.title?.isNotEmpty == true
              ? track.title!
              : track.language?.isNotEmpty == true
                  ? track.language!
                  : '音轨 ${index + 1}';
          return CupertinoActionSheetAction(
            onPressed: () {
              _player?.setAudioTrack(track);
              setState(() => _currentAudioIndex = index);
              Navigator.pop(context);
            },
            child: Text(
              label,
              style: TextStyle(
                fontWeight: index == _currentAudioIndex
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: index == _currentAudioIndex ? AppColors.primary : null,
              ),
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

  Future<void> _saveProgress(Duration position) async {
    final duration = _player?.state.duration ?? Duration.zero;
    final percentage = duration.inSeconds > 0
        ? position.inSeconds / duration.inSeconds
        : 0.0;

    try {
      await _dao.saveProgress(ReadingProgress(
        itemId: _currentItem.id!,
        position: position.inSeconds,
        positionText: _formatDuration(position),
        percentage: percentage,
        lastReadAt: DateTime.now(),
        chapterIndex: -1,
        chapterOffset: percentage,
      ));
      await _dao.updateLastOpened(_currentItem.id!);
      debugPrint('[VideoPlayer] 保存进度成功: itemId=${_currentItem.id}, position=${position.inSeconds}s');
    } catch (e) {
      debugPrint('[VideoPlayer] 保存进度失败: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    // 同步提取当前播放数据，必须在 player dispose 之前完成
    final position = _player?.state.position ?? Duration.zero;
    final duration = _player?.state.duration ?? Duration.zero;
    final percentage = duration.inSeconds > 0
        ? position.inSeconds / duration.inSeconds
        : 0.0;

    debugPrint('[VideoPlayer] dispose: itemId=${_currentItem.id}, position=${position.inSeconds}s, duration=${duration.inSeconds}s');

    // fire-and-forget 保存进度（仅本地文件）
    if (widget.streamUrl == null && _currentItem.id != null && position.inSeconds > 0) {
      unawaited(_dao.saveProgress(ReadingProgress(
        itemId: _currentItem.id!,
        position: position.inSeconds,
        positionText: _formatDuration(position),
        percentage: percentage,
        lastReadAt: DateTime.now(),
        chapterIndex: -1,
        chapterOffset: percentage,
      )).then((_) {
        debugPrint('[VideoPlayer] dispose保存进度成功');
      }).catchError((e) {
        debugPrint('[VideoPlayer] dispose保存进度失败: $e');
      }));
      unawaited(_dao.updateLastOpened(_currentItem.id!));
    } else {
      debugPrint('[VideoPlayer] dispose: 跳过保存 (stream=${widget.streamUrl != null}, id=${_currentItem.id}, position=${position.inSeconds}s)');
    }

    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _tracksSub?.cancel();
    _completedSub?.cancel();
    _player?.dispose();
    _gestureIndicatorTimer?.cancel();
    WakelockPlus.disable();
    // 恢复屏幕方向
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // ===================== 手势控制 =====================

  void _onPanStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
    _dragStartY = details.globalPosition.dy;
    _gestureStartPosition = _player?.state.position ?? Duration.zero;
    _gestureStartBrightness = _currentBrightness;
    _gestureStartVolume = _currentVolume;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final dx = details.globalPosition.dx - _dragStartX;
    final dy = details.globalPosition.dy - _dragStartY;
    final absDx = dx.abs();
    final absDy = dy.abs();

    // 手势阈值：至少移动 10 像素才判定为有效手势
    if (absDx < 10 && absDy < 10) return;

    // 首次判定手势方向
    if (_currentGesture == _GestureType.none) {
      if (absDx > absDy) {
        _currentGesture = _GestureType.seek;
      } else {
        // 左侧上下 = 亮度，右侧上下 = 音量
        if (_dragStartX < screenWidth / 2) {
          _currentGesture = _GestureType.brightness;
        } else {
          _currentGesture = _GestureType.volume;
        }
      }
    }

    switch (_currentGesture) {
      case _GestureType.seek:
        final ratio = dx / screenWidth;
        final deltaMs = (_duration.inMilliseconds * ratio * 0.5).toInt();
        _gestureValue = deltaMs.toDouble();
        break;
      case _GestureType.brightness:
        final ratio = -dy / screenHeight;
        final newValue = (_gestureStartBrightness + ratio).clamp(0.0, 1.0);
        _gestureValue = newValue;
        ScreenBrightness().setScreenBrightness(newValue);
        _currentBrightness = newValue;
        break;
      case _GestureType.volume:
        final ratio = -dy / screenHeight;
        final newValue = (_gestureStartVolume + ratio).clamp(0.0, 1.0);
        _gestureValue = newValue;
        VolumeController.instance.setVolume(newValue);
        _currentVolume = newValue;
        break;
      case _GestureType.none:
        break;
    }

    setState(() => _showGestureIndicator = true);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentGesture == _GestureType.seek) {
      final newPosition = _gestureStartPosition + Duration(milliseconds: _gestureValue.toInt());
      final clamped = Duration(
        milliseconds: newPosition.inMilliseconds.clamp(0, _duration.inMilliseconds),
      );
      _player?.seek(clamped);
    }

    _currentGesture = _GestureType.none;
    _gestureValue = 0;

    _gestureIndicatorTimer?.cancel();
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showGestureIndicator = false);
    });
  }

  void _onDoubleTap() {
    if (_player == null) return;
    if (_player!.state.playing) {
      _player!.pause();
    } else {
      _player!.play();
    }
    setState(() {});
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
      }
    });
  }

  void _onPlaybackCompleted() {
    switch (_loopMode) {
      case _LoopMode.single:
        _player?.seek(Duration.zero);
        _player?.play();
        break;
      case _LoopMode.series:
        if (_seriesEpisodes.length > 1) {
          final nextIndex = (_currentEpisodeIndex + 1) % _seriesEpisodes.length;
          _switchToEpisode(_seriesEpisodes[nextIndex]);
        } else {
          _player?.seek(Duration.zero);
          _player?.play();
        }
        break;
      case _LoopMode.none:
        // 不循环，停在结尾
        break;
    }
  }

  void _cycleLoopMode() {
    setState(() {
      _loopMode = _LoopMode.values[(_loopMode.index + 1) % _LoopMode.values.length];
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _isLocked
            ? null
            : () {
                setState(() => _showControls = !_showControls);
              },
        onPanStart: _isLocked ? null : _onPanStart,
        onPanUpdate: _isLocked ? null : _onPanUpdate,
        onPanEnd: _isLocked ? null : _onPanEnd,
        onDoubleTap: _isLocked ? null : _onDoubleTap,
        onLongPressStart: _isLocked ? null : (_) => _onLongPressStart(),
        onLongPressEnd: _isLocked ? null : (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (_controller != null)
              Video(
                controller: _controller!,
                fit: _videoFit,
                controls: NoVideoControls,
              )
            else
              Center(
                child: Text(
                  '无法播放此视频',
                  style: TextStyle(color: NeutralColorsDark.textPrimary.withOpacity(0.7)),
                ),
              ),
            if (_showControls && !_isLocked) ...[
              _buildAppBar(),
              _buildInfoPills(),
              _buildBottomBar(),
            ],
            if (_showGestureIndicator) _buildGestureIndicator(),
            // 锁定/解锁按钮（控制显示时或锁定状态下始终可见）
            if (_showControls || _isLocked) _buildLockButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]);
                    Navigator.pop(context);
                  },
                  child: const Icon(
                    CupertinoIcons.chevron_back,
                    color: NeutralColorsDark.textPrimary,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Text(
                    _currentItem.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: NeutralColorsDark.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 更多操作（三个点）
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _showMoreMenu,
                  child: const Icon(
                    CupertinoIcons.ellipsis_vertical,
                    color: NeutralColorsDark.textPrimary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部快速面板：音轨、字幕、画面比例、倍速、循环、播放信息一行直达
  void _showMoreMenu() {
    final neutral = NeutralPalette.of(context);
    final loopLabel = switch (_loopMode) {
      _LoopMode.none => '顺序播放',
      _LoopMode.single => '单曲循环',
      _LoopMode.series => '连播',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: neutral.surfaceElevated,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.large),
            topRight: Radius.circular(AppRadius.large),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部指示条
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: neutral.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // 快捷操作网格
              Wrap(
                spacing: 12,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _QuickPanelButton(
                    icon: CupertinoIcons.speaker_2,
                    label: '音轨',
                    badge: _audioTracks.length > 1 ? '${_audioTracks.length}' : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAudioTrackSelector();
                    },
                  ),
                  _QuickPanelButton(
                    icon: CupertinoIcons.text_bubble,
                    label: '字幕',
                    active: _subtitleFiles.isNotEmpty || _embeddedSubtitles.isNotEmpty,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showSubtitleSelector();
                    },
                  ),
                  _QuickPanelButton(
                    icon: Icons.aspect_ratio,
                    label: '画面',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showVideoFitSelector();
                    },
                  ),
                  _QuickPanelButton(
                    icon: CupertinoIcons.speedometer,
                    label: '${_playbackRate}x',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPlaybackRateSelector();
                    },
                  ),
                  _QuickPanelButton(
                    icon: _loopMode == _LoopMode.single
                        ? CupertinoIcons.repeat_1
                        : _loopMode == _LoopMode.series
                            ? CupertinoIcons.arrow_2_circlepath
                            : CupertinoIcons.arrow_right,
                    label: loopLabel,
                    onTap: () {
                      Navigator.pop(ctx);
                      _cycleLoopMode();
                    },
                  ),
                  _QuickPanelButton(
                    icon: CupertinoIcons.info_circle,
                    label: '信息',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showMediaInfo();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  color: neutral.surface,
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '关闭',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
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

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条（带缓存指示）
                StreamBuilder<Duration>(
                  stream: _player!.stream.position,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = _duration;
                    final buffer = _buffer;
                    final maxMs = duration.inMilliseconds.toDouble().max(1);
                    final bufferPercent = buffer.inMilliseconds.toDouble().clamp(0, maxMs) / maxMs;
                    return Column(
                      children: [
                        Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // 总时长背景
                            Container(
                              height: 4,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: NeutralColorsDark.textPrimary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // 缓冲进度
                            FractionallySizedBox(
                              widthFactor: bufferPercent,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: NeutralColorsDark.textPrimary.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            // 播放进度（Slider，inactive 轨道透明）
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: Colors.transparent,
                                thumbColor: NeutralColorsDark.textPrimary,
                              ),
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(
                                  0,
                                  maxMs,
                                ),
                                max: maxMs,
                                onChanged: (value) {
                                  _player!.seek(
                                    Duration(milliseconds: value.toInt()),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: TextStyle(
                                color: NeutralColorsDark.textPrimary.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: TextStyle(
                                color: NeutralColorsDark.textPrimary.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                // 播放控制
                Row(
                  children: [
                    // 左侧：选集入口
                    Expanded(
                      child: Row(
                        children: [
                          if (_seriesEpisodes.length > 1)
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _showEpisodeSelector,
                              child: const Icon(
                                CupertinoIcons.list_bullet,
                                color: NeutralColorsDark.textPrimary,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 中间：播放/暂停/前进后退（始终居中）
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 后退10秒
                        IconButton(
                          onPressed: () {
                            _player!.seek(
                              _player!.state.position - const Duration(seconds: 10),
                            );
                          },
                          icon: const Icon(
                            CupertinoIcons.chevron_left,
                            color: NeutralColorsDark.textPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 20),
                        StreamBuilder<bool>(
                          stream: _player!.stream.playing,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return IconButton(
                              onPressed: () {
                                if (isPlaying) {
                                  _player!.pause();
                                } else {
                                  _player!.play();
                                }
                              },
                              icon: Icon(
                                isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: NeutralColorsDark.textPrimary,
                                size: 32,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 20),
                        // 前进10秒
                        IconButton(
                          onPressed: () {
                            _player!.seek(
                              _player!.state.position + const Duration(seconds: 10),
                            );
                          },
                          icon: const Icon(
                            CupertinoIcons.chevron_right,
                            color: NeutralColorsDark.textPrimary,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                    // 右侧：全屏按钮
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: _toggleFullscreen,
                            child: Icon(
                              _isFullscreen
                                  ? CupertinoIcons.arrow_down_right_arrow_up_left
                                  : CupertinoIcons.arrow_up_left_arrow_down_right,
                              color: NeutralColorsDark.textPrimary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureIndicator() {
    String text;
    IconData icon;

    // 长按倍速优先显示
    if (_isLongPressSpeed) {
      text = '2.0x';
      icon = CupertinoIcons.forward_fill;
    } else {
      switch (_currentGesture) {
        case _GestureType.brightness:
          final value = (_gestureValue * 100).toInt();
          text = '亮度 $value%';
          icon = CupertinoIcons.sun_max;
          break;
        case _GestureType.volume:
          final value = (_gestureValue * 100).toInt();
          text = '音量 $value%';
          icon = value == 0
              ? CupertinoIcons.speaker_slash
              : CupertinoIcons.speaker_2;
          break;
        case _GestureType.seek:
          final delta = Duration(milliseconds: _gestureValue.toInt());
          final sign = _gestureValue >= 0 ? '+' : '';
          text = '$sign${_formatDuration(delta)}';
          icon = _gestureValue >= 0
              ? CupertinoIcons.goforward
              : CupertinoIcons.gobackward;
          break;
        case _GestureType.none:
          return const SizedBox.shrink();
      }
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部信息 Pill 标签（分辨率 / 音轨 / 字幕）
  Widget _buildInfoPills() {
    final state = _player?.state;
    final width = state?.width ?? 0;
    final height = state?.height ?? 0;

    final pills = <Widget>[];

    // 分辨率
    if (width > 0 && height > 0) {
      final is4K = width >= 3840 || height >= 2160;
      final isHDR = _isHDR();
      pills.add(_InfoPill(
        label: is4K ? '4K' : '${height}p',
        suffix: isHDR ? ' HDR' : null,
      ));
    }

    // 当前音轨
    if (_audioTracks.isNotEmpty && _currentAudioIndex >= 0) {
      final track = _audioTracks[_currentAudioIndex];
      final lang = track.language ?? track.title ?? '音轨${_currentAudioIndex + 1}';
      pills.add(_InfoPill(label: lang));
    }

    // 字幕状态
    if (_currentSubtitleIndex >= 0 || (_currentSubtitleIndex <= -2 && _embeddedSubtitles.isNotEmpty)) {
      pills.add(const _InfoPill(label: '字幕'));
    }

    if (pills.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 56,
      left: 12,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Row(
          children: pills.map((p) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: p,
          )).toList(),
        ),
      ),
    );
  }

  bool _isHDR() {
    try {
      final vp = (_player?.state as dynamic)?.videoParams;
      if (vp != null) {
        final colorSpace = vp.colorSpace?.toString().toLowerCase() ?? '';
        final pixelFormat = vp.pixelFormat?.toString().toLowerCase() ?? '';
        return colorSpace.contains('bt.2020') ||
            colorSpace.contains('pq') ||
            colorSpace.contains('hlg') ||
            pixelFormat.contains('p10') ||
            pixelFormat.contains('p12');
      }
    } catch (_) {}
    return false;
  }

  /// 播放信息弹窗
  void _showMediaInfo() {
    final state = _player?.state;
    final width = state?.width ?? 0;
    final height = state?.height ?? 0;
    final resolution = (width > 0 && height > 0) ? '${width}x$height' : '未知';

    final videoTracks = state?.tracks.video.where((t) => t.id != 'no').length ?? 0;
    final audioTrackCount = state?.tracks.audio.where((t) => t.id != 'no').length ?? 0;
    final subTrackCount = state?.tracks.subtitle.where((t) => t.id != 'no').length ?? 0;

    // 尝试获取视频参数（不同版本 API 可能不同，用 try 保护）
    String? pixelFormat;
    String? colorSpace;
    int? displayWidth;
    int? displayHeight;
    try {
      final vp = (state as dynamic)?.videoParams;
      if (vp != null) {
        pixelFormat = vp.pixelFormat?.toString();
        colorSpace = vp.colorSpace?.toString();
        displayWidth = vp.dw as int?;
        displayHeight = vp.dh as int?;
      }
    } catch (_) {}

    // 尝试获取音频参数
    int? sampleRate;
    int? audioChannels;
    try {
      final ap = (state as dynamic)?.audioParams;
      if (ap != null) {
        sampleRate = ap.sampleRate as int?;
        audioChannels = ap.channels as int?;
      }
    } catch (_) {}

    final infoItems = <(String, String)>[
      ('分辨率', resolution),
      if (displayWidth != null && displayHeight != null)
        ('显示尺寸', '${displayWidth}x$displayHeight'),
      ('时长', _formatDuration(_duration)),
      ('当前进度', _formatDuration(state?.position ?? Duration.zero)),
      ('播放速率', '${_playbackRate}x'),
      ('视频轨道', '$videoTracks'),
      ('音频轨道', '$audioTrackCount'),
      ('字幕轨道', '$subTrackCount'),
      if (pixelFormat != null && pixelFormat.isNotEmpty) ('像素格式', pixelFormat),
      if (colorSpace != null && colorSpace.isNotEmpty) ('色彩空间', colorSpace),
      if (sampleRate != null) ('音频采样率', '${sampleRate}Hz'),
      if (audioChannels != null) ('音频声道', '$audioChannels'),
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('播放信息'),
        message: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: infoItems.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 14,
                        color: NeutralColorsDark.textPrimary.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: NeutralColorsDark.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 锁定/解锁按钮（始终显示在左侧上下居中）
  Widget _buildLockButton() {
    return Positioned(
      left: 12,
      top: 0,
      bottom: 0,
      child: Center(
        child: CupertinoButton(
          padding: const EdgeInsets.all(8),
          borderRadius: BorderRadius.circular(20),
          color: Colors.black.withOpacity(0.4),
          onPressed: _toggleLock,
          child: Icon(
            _isLocked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// 顶部信息 Pill 标签
class _InfoPill extends StatelessWidget {
  final String label;
  final String? suffix;

  const _InfoPill({required this.label, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (suffix != null)
            Text(
              suffix!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.amber,
              ),
            ),
        ],
      ),
    );
  }
}

/// 播放器快速面板按钮
class _QuickPanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final String? badge;

  const _QuickPanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return SizedBox(
      width: 72,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary.withOpacity(0.15)
                        : neutral.surface,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Icon(
                    icon,
                    color: active ? AppColors.primary : neutral.textPrimary,
                    size: 24,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: neutral.textSecondary,
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


enum _GestureType { none, brightness, volume, seek }

enum _LoopMode { none, single, series }

extension on double {
  double max(double other) => this > other ? this : other;
}
