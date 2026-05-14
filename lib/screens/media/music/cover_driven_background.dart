import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../design_tokens/app_colors.dart';
import '../../../services/music_player_settings.dart';

class CoverDrivenBackground extends StatefulWidget {
  final String? coverPath;
  final BackgroundMode mode;

  const CoverDrivenBackground({
    super.key,
    this.coverPath,
    required this.mode,
  });

  @override
  State<CoverDrivenBackground> createState() => _CoverDrivenBackgroundState();
}

class _CoverDrivenBackgroundState extends State<CoverDrivenBackground>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.of(context);
    if (isActive) {
      _breathController.repeat(reverse: true);
      _orbitController.repeat();
    } else {
      _breathController.stop();
      _orbitController.stop();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  static const List<double> _saturationMatrix = [
    1.5, 0.0, 0.0, 0.0, 0.0,
    0.0, 1.5, 0.0, 0.0, 0.0,
    0.0, 0.0, 1.5, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ];

  Widget _buildCoverImage() {
    return Image.file(
      File(widget.coverPath!),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 400,
    );
  }

  Widget _buildBlurLayer({
    required double sigma,
    required double scale,
    required double opacity,
    Widget? child,
  }) {
    return Opacity(
      opacity: opacity,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(_saturationMatrix),
          child: Transform.scale(
            scale: scale,
            child: child ?? _buildCoverImage(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.mode == BackgroundMode.minimal || widget.coverPath == null) {
      return Container(
        color: isDark ? neutral.surface : neutral.background,
        child: Container(
          color: Colors.black.withOpacity(0.45),
        ),
      );
    }

    final children = <Widget>[];

    // 底层：沿椭圆轨道缓慢运动的封面图 + 高斯模糊
    children.add(
      AnimatedBuilder(
        animation: Listenable.merge([_orbitController, _breathController]),
        builder: (context, child) {
          final orbit = _orbitController.value * math.pi * 2;
          // 椭圆轨迹：长轴 60，短轴 40
          final dx = 60 * math.cos(orbit);
          final dy = 40 * math.sin(orbit);
          final breath = 0.9 + _breathController.value * 0.15;
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: 1.6 * breath,
              child: _buildBlurLayer(
                sigma: widget.mode == BackgroundMode.standard ? 90 : 120,
                scale: 1.0,
                opacity: 0.45 + _breathController.value * 0.1,
              ),
            ),
          );
        },
      ),
    );

    // 极致模式追加一层更大的模糊底衬，增加深邃感
    if (widget.mode == BackgroundMode.extreme) {
      children.add(
        AnimatedBuilder(
          animation: _breathController,
          builder: (context, child) {
            final t = _breathController.value;
            return _buildBlurLayer(
              sigma: 140,
              scale: 1.3,
              opacity: 0.2 + t * 0.1,
            );
          },
        ),
      );
    }

    // 深色遮罩层：让背景更暗、更深邃
    children.add(
      AnimatedBuilder(
        animation: _breathController,
        builder: (context, child) {
          final t = _breathController.value;
          final baseDarkness = widget.mode == BackgroundMode.standard ? 0.55 : 0.35;
          final darkness = baseDarkness + t * 0.08;
          return Container(
            color: Colors.black.withOpacity(darkness),
          );
        },
      ),
    );

    // 暗角遮罩
    children.add(
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.5),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.7),
            ],
            stops: const [0.0, 0.25, 0.7, 1.0],
          ),
        ),
      ),
    );

    return RepaintBoundary(
      child: Container(
        color: isDark ? neutral.surface : neutral.background,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: children,
        ),
      ),
    );
  }
}
