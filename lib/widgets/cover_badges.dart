import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';

/// 封面底部进度条（3pt 高）
class CoverProgressBar extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0

  const CoverProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.medium),
          bottomRight: Radius.circular(AppRadius.medium),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            heightFactor: 1.0,
            child: Container(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// 状态角标：私密锁 / 云端来源 / 已下载 / 已看完 / 更新角标
///
/// 位置规则：
/// - 左上角：私密锁
/// - 右上角：云端 / 已下载 / 更新 / 集数
/// - 底部：进度条
/// - 右下角：已看完勾选
class StatusBadge extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String? label;
  final double size;

  const StatusBadge._({
    super.key,
    this.icon,
    required this.color,
    this.label,
    this.size = 20,
  });

  /// 私密锁 - 左上角
  const StatusBadge.lock({Key? key})
      : this._(
          key: key,
          icon: CupertinoIcons.lock_fill,
          color: Colors.white,
          size: 20,
        );

  /// 云端已下载（绿色对勾）- 右上角
  const StatusBadge.cloudDownloaded({Key? key})
      : this._(
          key: key,
          icon: CupertinoIcons.checkmark_circle_fill,
          color: FunctionalColors.success,
          size: 20,
        );

  /// 云端未下载（蓝色云）- 右上角
  const StatusBadge.cloudOnly({Key? key})
      : this._(
          key: key,
          icon: CupertinoIcons.cloud_fill,
          color: CupertinoColors.activeBlue,
          size: 20,
        );

  /// 已看完（绿色勾选）- 右下角
  const StatusBadge.watched({Key? key})
      : this._(
          key: key,
          icon: CupertinoIcons.checkmark_circle_fill,
          color: FunctionalColors.success,
          size: 22,
        );

  /// 更新角标 "+N" - 右上角
  const StatusBadge.update({Key? key, required String count})
      : this._(
          key: key,
          label: '+$count',
          color: Colors.white,
          size: 20,
        );

  /// 集数角标 - 右下角
  const StatusBadge.episodeCount({Key? key, required String count})
      : this._(
          key: key,
          label: count,
          color: Colors.white,
          size: 0,
        );

  @override
  Widget build(BuildContext context) {
    // 文字角标（更新 / 集数）
    if (label != null) {
      if (size == 0) {
        // 集数角标：黑色半透明 pill
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Text(
            label!,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      // 更新角标：橙色圆
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: FunctionalColors.warning,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Center(
          child: Text(
            label!,
            style: TextStyle(
              fontSize: label!.length > 2 ? 9 : 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // 图标角标
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// 来源角标映射：根据 sourceType 返回对应图标/颜色
class SourceBadge extends StatelessWidget {
  final String? sourceType;
  final bool isDownloaded;

  const SourceBadge({super.key, this.sourceType, this.isDownloaded = false});

  @override
  Widget build(BuildContext context) {
    // 本地文件无角标
    if (sourceType == null || sourceType == 'local') {
      return const SizedBox.shrink();
    }

    // 已下载的云端内容 = 绿色对勾
    if (isDownloaded) {
      return const StatusBadge.cloudDownloaded();
    }

    // 纯云端引用 = 蓝色云
    return const StatusBadge.cloudOnly();
  }
}
