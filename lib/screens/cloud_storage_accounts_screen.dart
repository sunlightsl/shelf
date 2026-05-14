import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../design_tokens/app_colors.dart';
import '../services/cloud_storage/cloud_account.dart';
import '../services/cloud_storage/cloud_account_manager.dart';
import '../services/cloud_storage/cloud_storage_factory.dart';
import '../services/cloud_storage/cloud_sync_service.dart';
import '../services/cloud_media_sync_service.dart';
import 'cloud_storage_browser_screen.dart';
import 'cloud_storage/add_account_protocol_screen.dart';
import 'cloud_storage/add_account_config_screen.dart';

class CloudStorageAccountsScreen extends StatefulWidget {
  const CloudStorageAccountsScreen({super.key});

  @override
  State<CloudStorageAccountsScreen> createState() => _CloudStorageAccountsScreenState();
}

class _CloudStorageAccountsScreenState extends State<CloudStorageAccountsScreen> {
  List<CloudAccount> _accounts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await CloudAccountManager.instance.getAccounts();
    setState(() {
      _accounts = accounts;
      _isLoading = false;
    });
  }

  Future<void> _deleteAccount(String id) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除账户'),
        content: const Text('确定要删除这个云存储账户吗？'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CloudAccountManager.instance.deleteAccount(id);
      await _loadAccounts();
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openBrowser(CloudAccount account) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => CloudStorageBrowserScreen(account: account),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => const AddAccountProtocolScreen(),
      ),
    );
    await _loadAccounts();
  }

  Future<void> _showEditDialog(CloudAccount account) async {
    final creds = await CloudAccountManager.instance.getCredentials(account.id);
    if (!mounted) return;

    // 根据协议类型获取对应的密钥字段
    final secretKey = switch (account.protocol) {
      's3' => creds['secretKey'],
      'pan123' => creds['clientSecret'],
      'aliyundrive' => creds['refreshToken'],
      'jellyfin' || 'emby' => creds['apiKey'] ?? creds['password'],
      _ => creds['password'],
    };

    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => AddAccountConfigScreen(
          protocol: account.protocol,
          account: account,
          initialPassword: secretKey,
        ),
      ),
    );
    await _loadAccounts();
  }

  Future<void> _uploadProgress(String accountId) async {
    final ok = await CloudSyncService.instance.uploadReadingProgress(accountId);
    if (!mounted) return;
    _showToast(ok ? '阅读进度已上传' : '上传失败');
  }

  Future<void> _downloadProgress(String accountId) async {
    final result = await CloudSyncService.instance.downloadReadingProgress(accountId);
    if (!mounted) return;
    if (result == null) {
      _showToast('云端无阅读进度');
    } else {
      _showToast('更新 ${result.totalUpdated} 条，跳过 ${result.skipped} 条');
    }
  }

  Future<void> _syncMediaLibrary(String accountId) async {
    setState(() => _isLoading = true);
    try {
      final (added, updated) = await CloudMediaSyncService.instance.syncMediaLibrary(accountId);
      if (!mounted) return;
      _showToast('同步完成：新增 $added 条，更新 $updated 条');
    } catch (e) {
      debugPrint('[CloudAccounts] 同步媒体库失败: $e');
      if (!mounted) return;
      _showToast('同步失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSyncedMedia(String accountId) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('移除同步数据'),
        content: const Text('确定要移除该账户同步到本地的媒体元数据吗？不会删除云端内容。'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final count = await CloudMediaSyncService.instance.removeSyncedItems(accountId);
      if (!mounted) return;
      _showToast('已移除 $count 条同步数据');
    } catch (e) {
      if (!mounted) return;
      _showToast('移除失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('云存储'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _accounts.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final account = _accounts[index];
                    final isMediaServer = account.protocol == 'jellyfin' || account.protocol == 'emby';
                    return _AccountListTile(
                      account: account,
                      onTap: () => _openBrowser(account),
                      onEdit: () => _showEditDialog(account),
                      onDelete: () => _deleteAccount(account.id),
                      onUploadProgress: () => _uploadProgress(account.id),
                      onDownloadProgress: () => _downloadProgress(account.id),
                      onSyncMediaLibrary: isMediaServer ? () => _syncMediaLibrary(account.id) : null,
                      onRemoveSyncedMedia: isMediaServer ? () => _removeSyncedMedia(account.id) : null,
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    final neutral = NeutralPalette.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.cloud, size: 56, color: neutral.textTertiary),
          const SizedBox(height: 16),
          Text(
            '暂无云存储账户',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: neutral.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加云存储账户以访问云端资源',
            style: TextStyle(fontSize: 13, color: neutral.textTertiary),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _showAddDialog,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.add, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '添加账户',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountListTile extends StatelessWidget {
  final CloudAccount account;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onUploadProgress;
  final VoidCallback onDownloadProgress;
  final VoidCallback? onSyncMediaLibrary;
  final VoidCallback? onRemoveSyncedMedia;

  const _AccountListTile({
    required this.account,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onUploadProgress,
    required this.onDownloadProgress,
    this.onSyncMediaLibrary,
    this.onRemoveSyncedMedia,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(account.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(CupertinoIcons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: const Icon(CupertinoIcons.cloud, color: AppColors.primary),
        ),
        title: Text(account.displayName),
        subtitle: Text(
          '${CloudStorageFactory.getProtocolName(account.protocol)} · ${account.rootPath}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'browse':
                onTap();
              case 'edit':
                onEdit();
              case 'syncMedia':
                onSyncMediaLibrary?.call();
              case 'removeSynced':
                onRemoveSyncedMedia?.call();
              case 'uploadProgress':
                onUploadProgress();
              case 'downloadProgress':
                onDownloadProgress();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'browse', child: Text('浏览云端')),
            if (onSyncMediaLibrary != null)
              const PopupMenuItem(value: 'syncMedia', child: Text('同步到本地库')),
            if (onRemoveSyncedMedia != null)
              const PopupMenuItem(value: 'removeSynced', child: Text('移除同步数据')),
            const PopupMenuItem(value: 'edit', child: Text('编辑账户')),
            const PopupMenuItem(value: 'uploadProgress', child: Text('上传阅读进度')),
            const PopupMenuItem(value: 'downloadProgress', child: Text('下载阅读进度')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

