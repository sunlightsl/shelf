import 'package:flutter/material.dart';

/// 字体体系：6 档标准
///
/// 系统字体栈策略：iOS 优先 SF Pro + PingFang SC，Android 优先 Roboto + Noto Sans CJK。
/// Flutter 通过 fontFamilyFallback 实现类似 CSS font-family 的回退机制。
abstract class AppTypography {
  static const List<String> _fontFamilyFallback = [
    'PingFang SC',
    'SF Pro Text',
    'SF Pro Display',
    'Helvetica Neue',
    'Roboto',
    'Noto Sans CJK SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 45 / 34,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    fontFamilyFallback: _fontFamilyFallback,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
    fontFamilyFallback: _fontFamilyFallback,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFamilyFallback: _fontFamilyFallback,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    fontFamilyFallback: _fontFamilyFallback,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.2,
    fontFamilyFallback: _fontFamilyFallback,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 10,
    height: 12 / 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    fontFamilyFallback: _fontFamilyFallback,
  );
}
