import 'dart:math';
import 'package:flutter/material.dart';

class VinylDiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. 黑色底色
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF0A0A0A),
    );

    // 2. 同心圆沟槽（从标签外边缘到唱片外边缘内侧）
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final labelRadius = radius * 0.28; // 标签区域半径
    final startRadius = labelRadius + 4;
    final endRadius = radius * 0.96;
    final grooveCount = 70;
    final grooveSpacing = (endRadius - startRadius) / grooveCount;

    for (int i = 0; i <= grooveCount; i++) {
      final r = startRadius + i * grooveSpacing;
      final t = i / grooveCount;
      // 沟槽亮度：内圈略暗，外圈略亮，形成微妙的层次感
      final brightness = 0.06 + t * 0.06;
      groovePaint.color = Colors.grey.shade400.withOpacity(brightness);
      canvas.drawCircle(center, r, groovePaint);
    }

    // 3. 中央标签区域（深色圆环，与封面和沟槽形成过渡）
    final labelPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF141414);
    canvas.drawCircle(center, labelRadius + 2, labelPaint);

    // 4. 光泽反射（弧形高光）
    final shinePaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: -pi / 2.2,
        endAngle: -pi / 8,
        colors: [
          Colors.white.withOpacity(0.18),
          Colors.white.withOpacity(0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shinePaint);

    // 5. 外边缘高光环
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.grey.shade600.withOpacity(0.25);
    canvas.drawCircle(center, radius * 0.98, edgePaint);

    // 6. 内边缘微光环（标签与沟槽过渡处）
    final innerEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.grey.shade500.withOpacity(0.15);
    canvas.drawCircle(center, labelRadius + 3, innerEdgePaint);

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
