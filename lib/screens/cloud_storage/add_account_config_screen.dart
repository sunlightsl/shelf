import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../design_tokens/app_colors.dart';
import '../../design_tokens/app_radius.dart';
import '../../design_tokens/app_spacing.dart';
import '../../services/cloud_storage/cloud_account.dart';
import '../../services/cloud_storage/cloud_account_manager.dart';
import '../../services/cloud_storage/cloud_storage_factory.dart';
import '../../widgets/pressable.dart';
import 'aliyundrive_auth_screen.dart';

/// 添加/编辑账户 — 配置编辑页
///
/// 展示对应协议的表单字段，支持测试连接并保存。
class AddAccountConfigScreen extends StatefulWidget {
  final String protocol;
  final CloudAccount? account;
  final String? initialPassword;

  const AddAccountConfigScreen({
    super.key,
    required this.protocol,
    this.account,
    this.initialPassword,
  });

  @override
  State<AddAccountConfigScreen> createState() => _AddAccountConfigScreenState();
}

class _AddAccountConfigScreenState extends State<AddAccountConfigScreen> {
  late final _nameCtrl = TextEditingController();
  late final _rootPathCtrl = TextEditingController(text: '/');
  final Map<String, TextEditingController> _fieldControllers = {};
  final Map<String, bool> _fieldObscure = {};
  bool _isTesting = false;

  bool get _isEditMode => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _nameCtrl.text = widget.account!.displayName;
      _rootPathCtrl.text = widget.account!.rootPath;
    }
    _initFieldControllers();
  }

  void _initFieldControllers() {
    for (final field in CloudStorageFactory.getProtocolFields(widget.protocol)) {
      final ctrl = TextEditingController();
      if (_isEditMode) {
        ctrl.text = widget.account!.config[field.key] ?? '';
        if (widget.initialPassword != null &&
            field.isSecret &&
            (field.key == 'password' ||
                field.key == 'secretKey' ||
                field.key == 'apiKey' ||
                field.key == 'refreshToken')) {
          ctrl.text = widget.initialPassword!;
        }
      }
      _fieldControllers[field.key] = ctrl;
      _fieldObscure[field.key] = field.isSecret;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rootPathCtrl.dispose();
    for (final ctrl in _fieldControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final fields = CloudStorageFactory.getProtocolFields(widget.protocol);
    final credentials = <String, String>{};
    final config = <String, String>{};

    for (final field in fields) {
      final value = _fieldControllers[field.key]?.text.trim() ?? '';
      if (value.isEmpty) {
        _showError('请填写 ${field.label}');
        return;
      }
      credentials[field.key] = value;
      if (!field.isSecret) {
        config[field.key] = value;
      }
    }

    final name = _nameCtrl.text.trim();
    final rootPath = _rootPathCtrl.text.trim();

    setState(() => _isTesting = true);

    try {
      final storage = CloudStorageFactory.create(widget.protocol);
      final ok = await storage.connect(credentials);

      if (!ok) {
        _showError('连接失败，请检查配置信息');
        setState(() => _isTesting = false);
        return;
      }

      await storage.disconnect();

      final displayName = name.isNotEmpty ? name : _generateDefaultName(credentials);

      if (_isEditMode) {
        final updatedAccount = widget.account!.copyWith(
          displayName: displayName,
          config: config,
          rootPath: rootPath.isNotEmpty ? rootPath : '/',
        );
        await CloudAccountManager.instance.updateAccount(updatedAccount);
        await CloudAccountManager.instance.updateCredentials(widget.account!.id, credentials);
      } else {
        final account = CloudAccount(
          id: const Uuid().v4(),
          protocol: widget.protocol,
          displayName: displayName,
          config: config,
          rootPath: rootPath.isNotEmpty ? rootPath : '/',
        );
        await CloudAccountManager.instance.addAccount(account, credentials);
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('连接异常: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  String _generateDefaultName(Map<String, String> credentials) {
    return switch (widget.protocol) {
      'webdav' => '${credentials['username']}@${Uri.tryParse(credentials['serverUrl'] ?? '')?.host ?? credentials['serverUrl']}',
      's3' => '${credentials['accessKey']}@${credentials['endPoint']}',
      'pan123' => '123云盘 ${credentials['clientId']?.substring(0, 6) ?? ''}...',
      'aliyundrive' => '阿里云盘 ${credentials['refreshToken']?.substring(0, 6) ?? ''}...',
      'jellyfin' => 'Jellyfin ${Uri.tryParse(credentials['serverUrl'] ?? '')?.host ?? ''}',
      'emby' => 'Emby ${Uri.tryParse(credentials['serverUrl'] ?? '')?.host ?? ''}',
      'fnos' => '飞牛OS ${Uri.tryParse(credentials['serverUrl'] ?? '')?.host ?? ''}',
      _ => '未命名',
    };
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('连接失败'),
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  IconData _iconForField(String key) {
    return switch (key) {
      'serverUrl' || 'endPoint' => CupertinoIcons.link,
      'username' || 'accessKey' || 'clientId' => CupertinoIcons.person,
      'password' || 'secretKey' || 'clientSecret' || 'refreshToken' => CupertinoIcons.lock,
      'bucket' => CupertinoIcons.archivebox,
      _ => CupertinoIcons.doc_text,
    };
  }

  List<Widget> _buildFormFields() {
    final fields = CloudStorageFactory.getProtocolFields(widget.protocol);
    final widgets = <Widget>[];
    final neutral = NeutralPalette.of(context);

    for (final field in fields) {
      final ctrl = _fieldControllers[field.key];
      if (ctrl == null) continue;

      widgets.add(const SizedBox(height: AppSpacing.s12));
      widgets.add(
        CupertinoTextField(
          controller: ctrl,
          placeholder: field.placeholder,
          style: TextStyle(color: neutral.textPrimary),
          obscureText: _fieldObscure[field.key] ?? false,
          prefix: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.s12),
            child: Icon(
              _iconForField(field.key),
              size: 20,
              color: neutral.textSecondary,
            ),
          ),
          suffix: field.isSecret
              ? CupertinoButton(
                  padding: const EdgeInsets.only(right: AppSpacing.s12),
                  minimumSize: Size.zero,
                  onPressed: () {
                    setState(() {
                      _fieldObscure[field.key] = !(_fieldObscure[field.key] ?? true);
                    });
                  },
                  child: Icon(
                    (_fieldObscure[field.key] ?? true)
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                    size: 20,
                    color: neutral.textSecondary,
                  ),
                )
              : null,
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: neutral.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      );

      if (field.helperText != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.s4, top: AppSpacing.s4),
            child: Text(
              field.helperText!,
              style: TextStyle(fontSize: 12, color: neutral.textTertiary),
            ),
          ),
        );
      }
    }

    // 阿里云盘：在应用内登录按钮
    if (widget.protocol == 'aliyundrive') {
      widgets.add(const SizedBox(height: AppSpacing.s12));
      widgets.add(
        Pressable(
          onTap: () async {
            final token = await Navigator.of(context).push<String>(
              CupertinoPageRoute(
                builder: (_) => const AliyunDriveAuthScreen(),
              ),
            );
            if (token != null && token.isNotEmpty) {
              _fieldControllers['refreshToken']?.text = token;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.cloud, size: 18, color: Colors.white),
                SizedBox(width: AppSpacing.s8),
                Text(
                  '在应用内登录阿里云盘',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.s4, top: AppSpacing.s8),
          child: Text(
            '或手动粘贴 refresh_token 到上方输入框',
            style: TextStyle(fontSize: 12, color: NeutralPalette.of(context).textTertiary),
          ),
        ),
      );
    }

    // 根目录路径
    if (widget.protocol == 'webdav' ||
        widget.protocol == 'pan123' ||
        widget.protocol == 'aliyundrive' ||
        widget.protocol == 'fnos') {
      widgets.add(const SizedBox(height: AppSpacing.s12));
      widgets.add(
        CupertinoTextField(
          controller: _rootPathCtrl,
          placeholder: '根目录路径（默认 /）',
          style: TextStyle(color: NeutralPalette.of(context).textPrimary),
          prefix: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.s12),
            child: Icon(
              CupertinoIcons.folder,
              size: 20,
              color: NeutralPalette.of(context).textSecondary,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: NeutralPalette.of(context).surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      );
    }

    // 快速预设（WebDAV / 飞牛OS）
    if (widget.protocol == 'webdav' || widget.protocol == 'fnos') {
      widgets.add(const SizedBox(height: AppSpacing.s12));
      widgets.add(
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            _PresetChip(
              label: '坚果云',
              onTap: () {
                _fieldControllers['serverUrl']?.text = 'https://dav.jianguoyun.com/dav/';
                _nameCtrl.text = '坚果云';
              },
            ),
            _PresetChip(
              label: 'AList',
              onTap: () {
                _nameCtrl.text = 'AList';
              },
            ),
          ],
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final protocolName = CloudStorageFactory.getProtocolName(widget.protocol);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑 $protocolName' : '添加 $protocolName'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 显示名称
              CupertinoTextField(
                controller: _nameCtrl,
                placeholder: '显示名称（可选）',
                style: TextStyle(color: NeutralPalette.of(context).textPrimary),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s12),
                  child: Icon(
                    CupertinoIcons.tag,
                    size: 20,
                    color: NeutralPalette.of(context).textSecondary,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.s12),
                decoration: BoxDecoration(
                  color: NeutralPalette.of(context).surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
              ),
              ..._buildFormFields(),
              const SizedBox(height: AppSpacing.s24),
              Pressable(
                onTap: _isTesting ? null : _testAndSave,
                scale: 0.98,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                  decoration: BoxDecoration(
                    color: _isTesting ? AppColors.primary.withOpacity(0.5) : AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Center(
                    child: _isTesting
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : Text(
                            _isEditMode ? '保存修改' : '连接并保存',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
