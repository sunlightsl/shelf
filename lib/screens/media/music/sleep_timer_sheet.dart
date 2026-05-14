import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../services/sleep_timer_service.dart';

class SleepTimerSheet extends StatefulWidget {
  const SleepTimerSheet({super.key});

  @override
  State<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends State<SleepTimerSheet>
    with SingleTickerProviderStateMixin {
  final SleepTimerService _service = SleepTimerService.instance;
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

  String _formatRemaining(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _service.isActive;
    final remaining = _service.remaining;
    final bgColor = neutral.surface;
    final textColor = neutral.textPrimary;
    final subTextColor = neutral.textSecondary;
    final dividerColor = isDark ? neutral.surfaceElevated : neutral.divider;
    final buttonBg = isDark ? neutral.surfaceElevated : neutral.background;

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              behavior: HitTestBehavior.translucent,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: neutral.textTertiary,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                ),
              ),
            ),
            Text(
              '定时关闭',
              style: TextStyle(
                color: textColor,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 8),
          if (isActive && remaining != null)
            Text(
              '剩余时间 ${_formatRemaining(remaining)}',
              style: TextStyle(
                color: subTextColor,
                fontSize: 14,
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              cacheExtent: 200.0,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildTimeOption('关闭', 0, isActiveOverride: false, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('10 分钟', 10, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('15 分钟', 15, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('30 分钟', 30, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('45 分钟', 45, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('60 分钟', 60, textColor: textColor, dividerColor: dividerColor),
                Divider(height: 1, color: dividerColor),
                _buildTimeOption('播完当前关闭', -1, textColor: textColor, dividerColor: dividerColor),
              ],
            ),
          ),
          if (isActive)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s20),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: buttonBg,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  onPressed: () {
                    _service.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    '取消定时',
                    style: TextStyle(color: FunctionalColors.error),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildTimeOption(String label, int minutes, {bool? isActiveOverride, required Color textColor, required Color dividerColor}) {
    final isActive = isActiveOverride ??
        (_service.type == SleepTimerType.byDuration &&
            _service.remaining != null &&
            _service.remaining!.inMinutes == minutes);

    return GestureDetector(
      onTap: () {
        if (minutes == 0) {
          _service.cancel();
        } else if (minutes == -1) {
          _service.stopAfterCurrent();
        } else {
          _service.startByDuration(minutes);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : textColor,
                fontSize: 16,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const Spacer(),
            if (isActive)
              const Icon(
                CupertinoIcons.checkmark,
                color: AppColors.primary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
