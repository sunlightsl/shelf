import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 列表入场动画包装器
///
/// 按索引自动计算延迟（每 item 40ms，前 10 个生效，最大 400ms），
/// 组合淡入 + 从下方 15% 滑入，250ms 时长，easeOutCubic 曲线。
class AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;

  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delayMs = (index * 40).clamp(0, 400);
    return child
        .animate()
        .fadeIn(duration: 250.ms, delay: delayMs.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.15,
          end: 0,
          duration: 250.ms,
          delay: delayMs.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
