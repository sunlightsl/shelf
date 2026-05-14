import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../models/song.dart';
import '../../../services/music_player_service.dart';

class MusicQueueScreen extends StatefulWidget {
  const MusicQueueScreen({super.key});

  @override
  State<MusicQueueScreen> createState() => _MusicQueueScreenState();
}

class _MusicQueueScreenState extends State<MusicQueueScreen>
    with SingleTickerProviderStateMixin {
  final MusicPlayerService _service = MusicPlayerService.instance;
  double _dragOffset = 0.0;
  double _snapStartOffset = 0.0;
  late AnimationController _snapController;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onUpdate);
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _snapController.addListener(_onSnapTick);
  }

  @override
  void dispose() {
    _service.removeListener(_onUpdate);
    _snapController.removeListener(_onSnapTick);
    _snapController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _onSnapTick() {
    if (!mounted) return;
    setState(() {
      _dragOffset = _snapStartOffset * (1 - _snapController.value);
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy > 0) {
      setState(() {
        _dragOffset += details.delta.dy;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (_dragOffset > 80 || velocity > 200) {
      Navigator.pop(context);
      return;
    }

    _snapStartOffset = _dragOffset;
    _snapController.value = 0.0;
    _snapController.animateTo(1.0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _service.queue;
    final currentIndex = _service.currentIndex;
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: neutral.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
          ),
          child: Column(
            children: [
              // 顶部把手和标题（可拖拽关闭）
              GestureDetector(
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: neutral.textTertiary,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '播放队列 (${queue.length})',
                            style: TextStyle(
                              color: neutral.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (queue.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                minSize: 0,
                                onPressed: () {
                                  _service.clearQueue();
                                  Navigator.pop(context);
                                },
                                child: Icon(
                                  CupertinoIcons.trash,
                                  color: neutral.textTertiary,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 队列列表
              Expanded(
                child: ReorderableListView.builder(
                  cacheExtent: 200.0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: queue.length,
                  onReorder: (oldIndex, newIndex) {
                    _service.moveQueueItem(oldIndex, newIndex);
                  },
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        return Material(
                          color: Colors.transparent,
                          elevation: 0,
                          child: child,
                        );
                      },
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final song = queue[index];
                    final isCurrent = index == currentIndex;

                    return _QueueTile(
                      key: ValueKey(song.id ?? song.filePath),
                      index: index,
                      song: song,
                      isCurrent: isCurrent,
                      onTap: () {
                        _service.playSong(song);
                      },
                      onRemove: () {
                        _service.removeFromQueue(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final int index;
  final Song song;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueTile({
    required super.key,
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: song.coverPath != null
              ? Image.file(
                  File(song.coverPath!),
                  fit: BoxFit.cover,
                  cacheWidth: 150,
                  errorBuilder: (_, __, ___) => Container(
                    color: isDark ? neutral.surfaceElevated : neutral.divider,
                    child: Icon(CupertinoIcons.music_note, color: isDark ? NeutralColorsDark.textPrimary.withOpacity(0.38) : neutral.textSecondary, size: 20),
                  ),
                )
              : Container(
                  color: isDark ? neutral.surfaceElevated : neutral.divider,
                  child: Icon(CupertinoIcons.music_note, color: isDark ? NeutralColorsDark.textPrimary.withOpacity(0.38) : neutral.textSecondary, size: 20),
                ),
        ),
      ),
      title: Text(
        song.displayTitle,
        style: TextStyle(
          color: isCurrent ? AppColors.primary : (neutral.textPrimary),
          fontSize: 15,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.displayArtist,
        style: TextStyle(
          color: neutral.textSecondary,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent)
            const Icon(
              CupertinoIcons.volume_up,
              color: AppColors.primary,
              size: 16,
            )
          else
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: onRemove,
              child: Icon(CupertinoIcons.xmark, color: neutral.textSecondary, size: 16),
            ),
          const SizedBox(width: 8),
          ReorderableDragStartListener(
            index: index,
            child: Icon(CupertinoIcons.bars, color: neutral.textTertiary, size: 18),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
