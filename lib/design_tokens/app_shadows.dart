import 'package:flutter/material.dart';

/// 阴影体系：3 档标准
abstract class AppShadows {
  static const ambient = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static const elevated = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 24,
    offset: Offset(0, 8),
  );

  static const cover = BoxShadow(
    color: Color(0x26000000),
    blurRadius: 40,
    spreadRadius: -8,
    offset: Offset(0, 16),
  );
}
