import 'package:local_library/design_tokens/app_radius.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../models/song.dart';
import '../../../services/music_player_service.dart';
import '../../../services/lyrics_parser.dart';
import '../../../services/lyrics_service.dart';

class MusicLyricsView extends StatefulWidget {
  final Song song;

  const MusicLyricsView({super.key, required this.song});

  @override
  State<MusicLyricsView> createState() => _MusicLyricsViewState();
}

class _MusicLyricsViewState extends State<MusicLyricsView>
    with SingleTickerProviderStateMixin {
  final MusicPlayerService _service = MusicPlayerService.instance;
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  bool _hasLyrics = false;
  int _currentLine = -1;
  StreamSubscription<Duration>? _positionSub;
  bool _userScrolling = false;
  Timer? _scrollResetTimer;

  // 当前行呼吸动画
  late AnimationController _breatheController;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
    _startPositionListener();
    _positionsListener.itemPositions.addListener(_onPositionsChanged);

    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _scrollResetTimer?.cancel();
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    _breatheController.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final target = positions.firstWhere(
        (p) => p.index == _currentLine,
        orElse: () => positions.first,
      );
      if ((target.itemLeadingEdge < -0.1 || target.itemTrailingEdge > 1.1) && _currentLine >= 0) {
        _userScrolling = true;
        _scrollResetTimer?.cancel();
        _scrollResetTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _userScrolling = false);
        });
      }
    }
  }

  Future<void> _loadLyrics() async {
    setState(() => _isLoading = true);
    final lines = await LyricsService.instance.parseLyrics(widget.song.filePath);
    if (mounted) {
      setState(() {
        _lyrics = lines ?? [];
        _hasLyrics = lines != null && lines.isNotEmpty;
        _isLoading = false;
      });
    }
  }

  DateTime _lastScrollUpdate = DateTime.now();

  void _startPositionListener() {
    _positionSub = _service.positionStream.listen((position) {
      if (_lyrics.isEmpty || _userScrolling) return;
      final index = LyricsParser.getCurrentLineIndex(_lyrics, position);
      if (index != _currentLine && index >= 0) {
        setState(() => _currentLine = index);
        final now = DateTime.now();
        if (now.difference(_lastScrollUpdate).inMilliseconds > 500) {
          _lastScrollUpdate = now;
          _scrollToLine(index);
        }
      }
    });
  }

  void _scrollToLine(int index) {
    if (!_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.40,
    );
  }

  void _onLineTap(int index) {
    if (index < 0 || index >= _lyrics.length) return;
    _service.seek(_lyrics[index].time);
    setState(() {
      _currentLine = index;
      _userScrolling = false;
    });
    _scrollToLine(index);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (!_hasLyrics) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.text_alignleft, color: Colors.white, size: 56),
            const SizedBox(height: 20),
            const Text(
              '暂无歌词',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              '将 .lrc 文件放在歌曲同文件夹下即可加载',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ScrollablePositionedList.builder(
      itemCount: _lyrics.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).size.height * 0.38,
        bottom: MediaQuery.of(context).size.height * 0.42,
      ),
      itemBuilder: (context, index) {
        final line = _lyrics[index];
        final isCurrent = index == _currentLine;
        final distance = (index - _currentLine).abs();

        // 透明度：聚光灯梯度，当前行最亮，越远越淡
        final opacity = isCurrent
            ? 1.0
            : distance == 1
                ? 0.55
                : 0.38;

        // 字号：当前行 28，临近行 26，相邻行 24，更远的 20
        final fontSize = isCurrent
            ? 30.0
            : distance == 1
                ? 26.0
                : distance == 2
                    ? 24.0
                    : 24.0;

        // 字重：全部加粗，当前行最粗
        final fontWeight = isCurrent
            ? FontWeight.w700
            : FontWeight.w600;

        // 垂直间距：当前行更多呼吸空间
        final verticalPadding = isCurrent
            ? 20.0
            : distance == 1
                ? 14.0
                : distance == 2
                    ? 10.0
                    : 10.0;

        Widget textWidget = AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: Colors.white.withOpacity(opacity),
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: isCurrent ? 1.4 : 1.6,
            shadows: isCurrent ? [
              // 白色 glow，让文字在暗背景上更亮
              Shadow(
                color: Colors.white.withOpacity(0.25),
                blurRadius: 24,
                offset: Offset.zero,
              ),
              // 底色阴影，增加字重感
              Shadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );

        // 当前行加呼吸动画
        if (isCurrent) {
          textWidget = AnimatedBuilder(
            animation: _breatheController,
            builder: (context, child) {
              final breatheOpacity = 0.92 + _breatheController.value * 0.08;
              return Opacity(
                opacity: breatheOpacity,
                child: child,
              );
            },
            child: textWidget,
          );
        }

        return GestureDetector(
          onTap: () => _onLineTap(index),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: verticalPadding),
            alignment: Alignment.center,
            decoration: isCurrent
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    color: Colors.black.withOpacity(0.18),
                  )
                : null,
            child: textWidget,
          ),
        );
      },
    );
  }
}
