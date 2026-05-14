import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/library_dao.dart';
import '../models/library_item.dart';
import 'cloud_storage/base_media_storage.dart';
import 'cloud_storage/cloud_account.dart';
import 'cloud_storage/cloud_account_manager.dart';
import 'cloud_storage/cloud_storage_factory.dart';
import 'cloud_storage/jellyfin_storage.dart';
import 'cloud_storage/emby_storage.dart';

/// 云端媒体库同步服务
///
/// 职责：将 Jellyfin / Emby 等媒体服务器的元数据同步到本地 library_items 表，
/// 实现 Infuse/VidHub 式的"元数据本地聚合，播放时动态路由"。
///
/// 同步策略：
/// - 只同步元数据（标题、海报URL、简介、文件ID），不下载视频文件
/// - 云端条目的 filePath 使用虚拟路径 `cloud://{protocol}/{accountId}/{remoteId}`
/// - 播放时根据 sourceType 判断，云端条目走 streamUrl 在线播放
class CloudMediaSyncService {
  static final CloudMediaSyncService instance = CloudMediaSyncService._internal();
  CloudMediaSyncService._internal();

  final LibraryDao _dao = LibraryDao();

  /// 同步指定账户的媒体库元数据到本地
  ///
  /// [accountId] 云存储账户 ID
  /// 返回 (新增数, 更新数)
  Future<(int added, int updated)> syncMediaLibrary(String accountId) async {
    final (account, credentials) = await CloudAccountManager.instance.getAccountWithCredentials(accountId);
    if (account == null) throw Exception('账户不存在');

    // 仅支持 Jellyfin / Emby
    if (account.protocol != 'jellyfin' && account.protocol != 'emby') {
      throw UnsupportedError('目前仅支持 Jellyfin / Emby 媒体库同步');
    }

    final storage = CloudStorageFactory.create(account.protocol);
    if (storage is! BaseMediaServerStorage) {
      throw UnsupportedError('该协议不支持媒体库同步');
    }

    final connected = await storage.connect(credentials);
    if (!connected) throw Exception('连接服务器失败');

    try {
      debugPrint('[CloudMediaSync] 开始同步媒体库: ${account.displayName}');
      final remoteItems = await storage.getMediaLibraryItems();
      debugPrint('[CloudMediaSync] 获取到 ${remoteItems.length} 条远程媒体');

      var added = 0;
      var updated = 0;

      // 查询该账户已同步的所有条目（用于增量同步）
      final existingItems = await _dao.getItemsBySourceAccount(accountId);
      final existingByRemoteId = <String, LibraryItem>{};
      for (final item in existingItems) {
        if (item.remoteId != null) {
          existingByRemoteId[item.remoteId!] = item;
        }
      }

      for (final remote in remoteItems) {
        final existing = existingByRemoteId[remote.remoteId];
        final virtualPath = 'cloud://${account.protocol}/$accountId/${remote.remoteId}';

        if (existing != null) {
          // 更新已有条目
          final updatedItem = existing.copyWith(
            title: remote.displayTitle,
            author: remote.isEpisode ? remote.seriesName : null,
            description: remote.overview,
            fileSize: remote.fileSize,
            totalProgress: remote.runtimeSeconds,
            remoteCoverUrl: remote.posterUrl,
            streamUrl: remote.streamUrl,
          );
          await _dao.updateItem(updatedItem);
          updated++;
        } else {
          // 插入新条目
          final newItem = LibraryItem(
            title: remote.displayTitle,
            mediaType: MediaType.video,
            format: FileFormat.mp4,
            filePath: virtualPath,
            author: remote.isEpisode ? remote.seriesName : null,
            description: remote.overview,
            addedDate: DateTime.now(),
            fileSize: remote.fileSize,
            totalProgress: remote.runtimeSeconds,
            sourceType: account.protocol,
            sourceAccountId: accountId,
            remoteId: remote.remoteId,
            remoteCoverUrl: remote.posterUrl,
            streamUrl: remote.streamUrl,
          );
          await _dao.insertItem(newItem);
          added++;
        }
      }

      debugPrint('[CloudMediaSync] 同步完成: 新增 $added, 更新 $updated');
      return (added, updated);
    } finally {
      await storage.disconnect();
    }
  }

  /// 删除指定账户的所有云端媒体条目
  Future<int> removeSyncedItems(String accountId) async {
    final items = await _dao.getItemsBySourceAccount(accountId);
    var count = 0;
    for (final item in items) {
      if (item.id != null) {
        await _dao.permanentlyDeleteItem(item.id!);
        count++;
      }
    }
    debugPrint('[CloudMediaSync] 已删除 $count 条同步条目');
    return count;
  }
}
