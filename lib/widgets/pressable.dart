import 'package:flutter/material.dart';
import '../design_tokens/app_colors.dart';

/// 统一按压反馈包装器
///
/// 组合 scale 0.98 + 背景淡入（textPrimary.withOpacity(0.04)），
/// 时长 100ms，easeOut 曲线。
/// 适用于列表项、卡片、设置行等可点击元素。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final int durationMs;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.98,
    this.durationMs = 100,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: Duration(milliseconds: widget.durationMs),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: Duration(milliseconds: widget.durationMs),
          color: _pressed ? neutral.textPrimary.withOpacity(0.04) : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
