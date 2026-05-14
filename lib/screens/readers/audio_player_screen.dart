import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/library_item.dart';
import '../../models/reading_progress.dart';
import '../../database/library_dao.dart';

class AudioPlayerScreen extends StatefulWidget {
  final LibraryItem item;

  const AudioPlayerScreen({super.key, required this.item});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  late final Player _player;
  late final LibraryDao _dao = LibraryDao();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _player = Player();
    _player.setVolume(100);
    _player.open(Media(widget.item.filePath));

    _positionSub = _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
  }

  @override
  void dispose() {
    _saveProgress();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    try {
      _player.dispose();
    } catch (_) {}
    WakelockPlus.disable();
    super.dispose();
  }

  void _saveProgress() {
    final percentage = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;
    _dao.saveProgress(ReadingProgress(
      itemId: widget.item.id!,
      position: _position.inSeconds,
      positionText: _formatDuration(_position),
      percentage: percentage,
      lastReadAt: DateTime.now(),
      chapterIndex: -1,
      chapterOffset: percentage,
    )).catchError((_) {});
    _dao.updateLastOpened(widget.item.id!).catchError((_) {});
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _togglePlay() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _seekTo(Duration position) {
    _player.seek(position);
  }

  void _changeSpeed() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    setState(() => _playbackSpeed = speeds[nextIndex]);
    _player.setRate(_playbackSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: NeutralColorsDark.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_down, color: NeutralColorsDark.textPrimary),
        ),
        title: Text(
          widget.item.title,
          style: TextStyle(color: NeutralColorsDark.textPrimary, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.large),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: widget.item.coverPath != null
                      ? Image.file(
                          File(widget.item.coverPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildDefaultCover(),
                        )
                      : _buildDefaultCover(),
                ),
              ),
              const Spacer(flex: 1),
              // 标题和作者
              Text(
                widget.item.title,
                style: TextStyle(
                  color: NeutralColorsDark.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.item.author != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.item.author!,
                  style: TextStyle(
                    color: NeutralColorsDark.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ],
              const Spacer(flex: 1),
              // 进度条
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: NeutralColorsDark.divider,
                  thumbColor: AppColors.primary,
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _duration.inSeconds > 0
                      ? _position.inSeconds / _duration.inSeconds
                      : 0,
                  onChanged: (value) {
                    final newPosition = Duration(
                      seconds: (value * _duration.inSeconds).toInt(),
                    );
                    _seekTo(newPosition);
                  },
                ),
              ),
              // 时间显示
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        color: NeutralColorsDark.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        color: NeutralColorsDark.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 控制按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 倍速
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _changeSpeed,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: NeutralColorsDark.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${_playbackSpeed}x',
                        style: TextStyle(
                          color: NeutralColorsDark.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // 播放/暂停
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _togglePlay,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: NeutralColorsDark.textPrimary,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // 进度跳转（前进15秒）
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      final newPos = _position + const Duration(seconds: 15);
                      _seekTo(newPos < _duration ? newPos : _duration);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: NeutralColorsDark.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        CupertinoIcons.goforward_15,
                        color: NeutralColorsDark.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      color: NeutralColorsDark.surfaceElevated,
      child: Center(
        child: Icon(
          CupertinoIcons.music_note,
          color: NeutralColorsDark.textTertiary,
          size: 80,
        ),
      ),
    );
  }
}
