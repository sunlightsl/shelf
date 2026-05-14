import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../services/music_player_settings.dart';
import '../../../services/music_player_service.dart';

class EqSettingsSheet extends StatefulWidget {
  const EqSettingsSheet({super.key});

  @override
  State<EqSettingsSheet> createState() => _EqSettingsSheetState();
}

class _EqSettingsSheetState extends State<EqSettingsSheet>
    with TickerProviderStateMixin {
  bool _enabled = false;
  EqPreset _preset = EqPreset.off;
  late final List<ValueNotifier<double>> _gainNotifiers;
  bool _isLoading = true;

  List<double> get _gainValues => _gainNotifiers.map((n) => n.value).toList();
  double _dragOffset = 0.0;
  double _snapStartOffset = 0.0;
  late AnimationController _snapController;

  late AnimationController _spectrumController;
  final List<AnimationController> _barControllers = [];

  @override
  void initState() {
    super.initState();
    _gainNotifiers = List.generate(5, (_) => ValueNotifier<double>(0));
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _snapController.addListener(_onSnapTick);
    _spectrumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadSettings();
  }

  @override
  void dispose() {
    _snapController.removeListener(_onSnapTick);
    _snapController.dispose();
    _spectrumController.dispose();
    for (final c in _barControllers) {
      c.dispose();
    }
    for (final n in _gainNotifiers) {
      n.dispose();
    }
    super.dispose();
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

  Future<void> _loadSettings() async {
    final enabled = await MusicPlayerSettings.getEqEnabled();
    final preset = await MusicPlayerSettings.getEqPreset();
    final gains = await MusicPlayerSettings.getEqGains();
    final values = gains.length == 5 ? gains : List.from(MusicPlayerSettings.getPresetGains(preset));
    for (var i = 0; i < 5; i++) {
      _gainNotifiers[i].value = values[i];
    }
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _preset = preset;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    await MusicPlayerSettings.setEqEnabled(_enabled);
    await MusicPlayerSettings.setEqPreset(_preset);
    await MusicPlayerSettings.setEqGains(_gainValues);
    await _applyToPlayer();
  }

  Future<void> _applyToPlayer() async {
    final service = MusicPlayerService.instance;
    if (_enabled && _preset != EqPreset.off) {
      await service.applyEqualizer(true, _gainValues);
    } else {
      await service.applyEqualizer(false, [0, 0, 0, 0, 0]);
    }
  }

  void _applyPreset(EqPreset preset) {
    final values = List.from(MusicPlayerSettings.getPresetGains(preset));
    for (var i = 0; i < 5; i++) {
      _gainNotifiers[i].value = values[i];
    }
    setState(() {
      _preset = preset;
      if (preset != EqPreset.off) {
        _enabled = true;
      }
    });
    _save();
  }

  void _setGain(int index, double value) {
    _gainNotifiers[index].value = value;
    setState(() {
      _preset = EqPreset.custom;
      _enabled = true;
    });
    _save();
  }

  void _reset() {
    for (final n in _gainNotifiers) {
      n.value = 0;
    }
    setState(() {
      _preset = EqPreset.off;
      _enabled = false;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = neutral.surface;
    final textColor = neutral.textPrimary;
    final cardColor = isDark ? neutral.surfaceElevated : neutral.background;
    final subTextColor = neutral.textSecondary;

    if (_isLoading) {
      return SizedBox(
        height: 400,
        child: Center(
          child: CupertinoActivityIndicator(
            color: isDark ? neutral.textPrimary : neutral.textTertiary,
          ),
        ),
      );
    }

    return Transform.translate(
      offset: Offset(0, _dragOffset),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              GestureDetector(
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
            const SizedBox(height: 16),
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '均衡器',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  CupertinoSwitch(
                    value: _enabled,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _save();
                    },
                    activeTrackColor: FunctionalColors.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 频谱可视化
            SizedBox(
              height: 120,
              child: _buildSpectrumVisualizer(isDark: isDark),
            ),
            const SizedBox(height: 24),
            // 频段滑块
            SizedBox(
              height: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (i) => _buildBandSlider(i, isDark: isDark)),
              ),
            ),
            const SizedBox(height: 8),
            // 预设选择
            SizedBox(
              height: 44,
              child: ListView.separated(
                cacheExtent: 200.0,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: EqPreset.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final preset = EqPreset.values[index];
                  final selected = _preset == preset;
                  return GestureDetector(
                    onTap: () => _applyPreset(preset),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary
                            : cardColor,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                      child: Text(
                        MusicPlayerSettings.presetLabel(preset),
                        style: TextStyle(
                          color: selected ? Colors.white : subTextColor,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // 重置按钮
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _reset,
              child: Text(
                '重置',
                style: TextStyle(
                  color: neutral.textTertiary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildSpectrumVisualizer({required bool isDark}) {
    return AnimatedBuilder(
      animation: _spectrumController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _SpectrumPainter(
            gains: _gainValues,
            enabled: _enabled,
            animationValue: _spectrumController.value,
            isDark: isDark,
          ),
        );
      },
    );
  }

  Widget _buildBandSlider(int index, {required bool isDark}) {
    final neutral = NeutralPalette.of(context);
    final label = MusicPlayerSettings.eqBandLabels[index];
    final trackBg = isDark ? neutral.surfaceElevated : neutral.divider;
    final centerLineColor = neutral.textTertiary;
    final labelColor = neutral.textSecondary;

    return ValueListenableBuilder<double>(
      valueListenable: _gainNotifiers[index],
      builder: (context, gain, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              gain > 0 ? '+${gain.toStringAsFixed(1)}' : gain.toStringAsFixed(1),
              style: TextStyle(
                color: _enabled ? FunctionalColors.success : neutral.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackHeight = constraints.maxHeight;
                  return GestureDetector(
                    onVerticalDragUpdate: (details) {
                      if (!_enabled) return;
                      final delta = -details.primaryDelta! / trackHeight * 24;
                      final newGain = (gain + delta).clamp(-12.0, 12.0);
                      if ((newGain - gain).abs() > 0.1) {
                        _gainNotifiers[index].value = newGain;
                        _preset = EqPreset.custom;
                      }
                    },
                    onVerticalDragEnd: (_) => _save(),
                    onTapUp: (details) {
                      if (!_enabled) return;
                      final tapY = details.localPosition.dy;
                      final ratio = 1 - (tapY / trackHeight).clamp(0.0, 1.0);
                      final newGain = (ratio * 24 - 12).clamp(-12.0, 12.0);
                      _gainNotifiers[index].value = newGain;
                      _preset = EqPreset.custom;
                      _save();
                    },
                    child: Container(
                      width: 44,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: trackBg,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // 中心线（0dB）
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: trackHeight * 0.5 - 0.5,
                            child: Container(
                              height: 1,
                              color: centerLineColor,
                            ),
                          ),
                          // 增益指示
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: 44,
                            height: trackHeight * ((gain + 12) / 24).clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: _enabled
                                    ? [
                                        AppColors.primary.withOpacity(0.8),
                                        FunctionalColors.success.withOpacity(0.6),
                                      ]
                                    : [
                                        neutral.textTertiary.withOpacity(0.3),
                                        neutral.textSecondary.withOpacity(0.2),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                          ),
                          // 当前值指示点
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: trackHeight * ((gain + 12) / 24).clamp(0.0, 1.0) - 6,
                            child: Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _enabled
                                      ? FunctionalColors.success
                                      : neutral.textTertiary,
                                  shape: BoxShape.circle,
                                  boxShadow: _enabled
                                      ? [
                                          BoxShadow(
                                            color: FunctionalColors.success.withOpacity(0.4),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final List<double> gains;
  final bool enabled;
  final double animationValue;
  final bool isDark;

  _SpectrumPainter({
    required this.gains,
    required this.enabled,
    required this.animationValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) {
      _drawFlatLine(canvas, size);
      return;
    }

    final barCount = 32;
    final barWidth = size.width / barCount * 0.6;
    final gap = size.width / barCount * 0.4;
    final random = Random(42);

    for (int i = 0; i < barCount; i++) {
      // 根据频段映射增益影响
      final bandIndex = (i / barCount * 5).floor().clamp(0, 4);
      final gain = gains[bandIndex];
      final baseHeight = size.height * 0.1 + (gain + 12) / 24 * size.height * 0.5;

      // 添加动画波动
      final phase = i * 0.3 + animationValue * pi * 2;
      final wave = sin(phase) * 0.3 + 0.7;
      final noise = random.nextDouble() * 0.15;
      final barHeight = (baseHeight * wave + size.height * noise).clamp(4.0, size.height);

      final x = i * (barWidth + gap) + gap / 2;
      final y = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(2),
      );

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.primary.withOpacity(0.8),
            FunctionalColors.success.withOpacity(0.6),
          ],
        ).createShader(Rect.fromLTWH(x, 0, barWidth, size.height));

      canvas.drawRRect(rect, paint);
    }
  }

  void _drawFlatLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? NeutralColorsDark.divider : NeutralColorsLight.textTertiary).withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i <= 32; i++) {
      final x = i * (size.width / 32);
      final y = size.height * 0.5 + sin(i * 0.5 + animationValue * pi) * 3;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.enabled != enabled ||
      oldDelegate.gains != gains ||
      oldDelegate.isDark != isDark;
}
