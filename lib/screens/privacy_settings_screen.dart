import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../design_tokens/app_colors.dart';
import '../design_tokens/app_radius.dart';
import '../design_tokens/app_shadows.dart';
import '../design_tokens/app_spacing.dart';
import '../services/privacy_service.dart';
import '../widgets/pressable.dart';
import 'private_space_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    PrivacyService.instance.init();
    PrivacyService.instance.addListener(_onPrivacyServiceChanged);
  }

  @override
  void dispose() {
    PrivacyService.instance.removeListener(_onPrivacyServiceChanged);
    super.dispose();
  }

  void _onPrivacyServiceChanged() {
    if (mounted) setState(() {});
  }

  void _showTip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('私密安全'),
        border: null,
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.s20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 私密模式开关
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Pressable(
                      onTap: () async => _togglePrivacyMode(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                              ),
                              child: Icon(
                                CupertinoIcons.lock_fill,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '开启私密模式',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: neutral.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '标记为私密的资源将被隐藏',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: neutral.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoSwitch(
                              value: PrivacyService.instance.isPrivacyModeEnabled,
                              onChanged: (v) async => _togglePrivacyMode(),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 在设置页面显示私密空间入口
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Pressable(
                      onTap: () async {
                        await PrivacyService.instance.setShowPrivateSpaceInSettings(
                          !PrivacyService.instance.showPrivateSpaceInSettings,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                              ),
                              child: Icon(
                                CupertinoIcons.eye_fill,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '在设置页面显示私密空间',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: neutral.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '开启后在设置主页显示快捷入口',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: neutral.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoSwitch(
                              value: PrivacyService.instance.showPrivateSpaceInSettings,
                              onChanged: (v) async {
                                await PrivacyService.instance.setShowPrivateSpaceInSettings(v);
                              },
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 私密空间入口
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Pressable(
                      onTap: () async {
                        if (PrivacyService.instance.isUnlocked) {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => const PrivateSpaceScreen(),
                            ),
                          );
                        } else {
                          final success = await PrivacyService.instance.unlock();
                          if (success && mounted) {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => const PrivateSpaceScreen(),
                              ),
                            );
                          } else if (mounted) {
                            _showTip('认证失败，无法进入私密空间');
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: FunctionalColors.error.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                              ),
                              child: Icon(
                                CupertinoIcons.lock_shield_fill,
                                color: FunctionalColors.error,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '私密空间',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: neutral.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '查看已标记为私密的资源',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: neutral.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              color: neutral.textTertiary,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 自动锁定
                  Text(
                    '自动锁定',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: neutral.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Column(
                      children: [
                        _LockOptionRow(
                          label: '屏幕关闭后',
                          selected: PrivacyService.instance.lockMode == 0,
                          onTap: () async {
                            await PrivacyService.instance.setLockMode(0);
                          },
                        ),
                        Divider(height: 1, color: neutral.divider),
                        _LockOptionRow(
                          label: '离开应用5分钟后',
                          selected: PrivacyService.instance.lockMode == 1,
                          onTap: () async {
                            await PrivacyService.instance.setLockMode(1);
                          },
                        ),
                        Divider(height: 1, color: neutral.divider),
                        _LockOptionRow(
                          label: '离开应用后立即锁定',
                          selected: PrivacyService.instance.lockMode == 2,
                          onTap: () async {
                            await PrivacyService.instance.setLockMode(2);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 立即锁定
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    child: Pressable(
                      onTap: () {
                        PrivacyService.instance.lock();
                        Navigator.of(context).pop('locked');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: FunctionalColors.error.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.small),
                              ),
                              child: Icon(
                                CupertinoIcons.lock_fill,
                                color: FunctionalColors.error,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '立即锁定',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: FunctionalColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 说明
                  Text(
                    '私密模式说明',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: neutral.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: neutral.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      boxShadow: isDark ? null : [AppShadows.ambient],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '· 标记为私密的资源在未解锁状态下完全隐藏\n'
                      '· 解锁使用系统生物认证或设备密码\n'
                      '· 解锁状态仅在当前会话有效，杀进程后自动锁定\n'
                      '· 自动锁定后需要重新验证身份',
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePrivacyMode() async {
    final currentlyEnabled = PrivacyService.instance.isPrivacyModeEnabled;
    if (!currentlyEnabled) {
      _showTip('正在调起系统认证…');
      final success = await PrivacyService.instance.unlock();
      if (success && mounted) {
        await PrivacyService.instance.setPrivacyModeEnabled(true);
        _showTip('私密模式已开启');
      } else if (mounted) {
        _showTip('认证失败或未通过，请检查设备是否已设置锁屏密码/指纹/面容');
      }
    } else {
      _showTip('正在验证身份…');
      final success = await PrivacyService.instance.unlock();
      if (success && mounted) {
        await PrivacyService.instance.setPrivacyModeEnabled(false);
        PrivacyService.instance.lock();
        _showTip('私密模式已关闭');
      } else if (mounted) {
        _showTip('认证失败，无法关闭私密模式');
      }
    }
  }
}

class _LockOptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LockOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: neutral.textPrimary,
                ),
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.checkmark_alt,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
