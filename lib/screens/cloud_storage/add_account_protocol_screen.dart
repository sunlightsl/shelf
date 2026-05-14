import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../design_tokens/app_colors.dart';
import '../../design_tokens/app_radius.dart';
import '../../design_tokens/app_shadows.dart';
import '../../design_tokens/app_spacing.dart';
import '../../services/cloud_storage/cloud_storage_factory.dart';
import '../../widgets/pressable.dart';
import 'add_account_config_screen.dart';

/// 添加账户 — 协议选择页
///
/// 展示所有支持的云存储协议，点击后进入对应配置页。
class AddAccountProtocolScreen extends StatelessWidget {
  const AddAccountProtocolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final protocols = CloudStorageFactory.supportedProtocols;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加云存储'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.s16),
        itemCount: protocols.length,
        itemBuilder: (context, index) {
          final protocol = protocols[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: _ProtocolCard(
              protocol: protocol,
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => AddAccountConfigScreen(protocol: protocol),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  final String protocol;
  final VoidCallback onTap;

  const _ProtocolCard({required this.protocol, required this.onTap});

  IconData _iconForProtocol(String p) {
    return switch (p) {
      'webdav' => CupertinoIcons.link,
      's3' => CupertinoIcons.archivebox,
      'pan123' => CupertinoIcons.cloud,
      'aliyundrive' => CupertinoIcons.cloud_fill,
      'jellyfin' => CupertinoIcons.tv,
      'emby' => CupertinoIcons.tv,
      'fnos' => CupertinoIcons.desktopcomputer,
      _ => CupertinoIcons.folder,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = isDark ? NeutralPalette.dark : NeutralPalette.light;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: neutral.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          boxShadow: isDark ? null : [AppShadows.ambient],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(
                _iconForProtocol(protocol),
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CloudStorageFactory.getProtocolName(protocol),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    CloudStorageFactory.getProtocolDescription(protocol),
                    style: TextStyle(
                      fontSize: 13,
                      color: neutral.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: neutral.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
