import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'dart:math' show pi;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../services/music_player_service.dart';
import '../../../services/reading_settings_service.dart';
import 'music_player_screen.dart';
import 'music_queue_screen.dart';

class MiniPlayer extends StatefulWidget {
  final bool compact;
  const MiniPlayer({super.key, this.compact = false});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  final MusicPlayerService _service = MusicPlayerService.instance;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _service.addListener(_onUpdate);
    _updateRotation();
  }

  @override
  void dispose() {
    _service.removeListener(_onUpdate);
    _rotationController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) {
      _updateRotation();
      setState(() {});
    }
  }

  void _updateRotation() {
    if (!mounted || _rotationController.isDismissed) return;
    if (_service.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      _rotationController.stop();
    }
  }

  void _openFullPlayer() {
    if (MusicPlayerScreen.isOpen) return;
    Navigator.of(context).push(MusicPlayerScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final song = _service.currentSong;
    if (song == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;
    final bgColor = widget.compact
        ? Colors.transparent
        : (isDark
            ? neutral.surfaceElevated
            : neutral.surface.withOpacity(0.85));
    final titleColor = neutral.textPrimary;
    final artistColor = neutral.textSecondary;
    final iconColor = neutral.textPrimary;
    final progressBg = neutral.divider;
    final placeholderBg = isDark ? neutral.divider : neutral.background;
    final placeholderIconColor = neutral.textTertiary;

    final content = Container(
      height: widget.compact ? 68 : 64,
      margin: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: widget.compact ? null : BorderRadius.circular(AppRadius.medium),
        border: widget.compact
            ? Border(
                top: BorderSide(
                  color: neutral.textPrimary.withOpacity(0.05),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // 旋转封面
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationController.value * 2 * pi,
                child: child,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: song.coverPath != null
                  ? Image.file(
                      File(song.coverPath!),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      cacheWidth: 150,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: placeholderBg,
                        child: Icon(
                          CupertinoIcons.music_note,
                          color: placeholderIconColor,
                          size: 20,
                        ),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: placeholderBg,
                      child: Icon(
                        CupertinoIcons.music_note,
                        color: placeholderIconColor,
                        size: 20,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // 歌曲信息
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.displayTitle,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  song.displayArtist,
                  style: TextStyle(
                    color: artistColor,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 播放/暂停按钮
          StreamBuilder<bool>(
            stream: _service.playingStream,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;
              return CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _service.togglePlay,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: iconColor,
                      size: 18,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // 播放列表按钮
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () {
              showCupertinoModalPopup(
                context: context,
                builder: (_) => const MusicQueueScreen(),
              );
            },
            child: Icon(
              CupertinoIcons.list_bullet,
              color: iconColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );

    final child = Stack(
      children: [
        content,
        Positioned(
          bottom: widget.compact ? 0 : 8,
          left: widget.compact ? 0 : 12,
          right: widget.compact ? 0 : 12,
          child: StreamBuilder<Duration>(
            stream: _service.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = _service.duration;
              final progress = duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0;
              return Container(
                height: 2,
                decoration: BoxDecoration(
                  color: progressBg,
                  borderRadius: BorderRadius.circular(1),
                ),
                clipBehavior: Clip.hardEdge,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    return RepaintBoundary(
      child: GestureDetector(
        onTap: _openFullPlayer,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
            _openFullPlayer();
          }
        },
        child: isDark
            ? child
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: child,
                ),
              ),
      ),
    );
  }
}
