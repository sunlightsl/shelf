import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_account.dart';

/// 云存储账户管理器
///
/// 职责：
/// 1. 账户配置的增删改查
/// 2. 敏感信息（密码、Token）加密存储（flutter_secure_storage）
/// 3. 非敏感信息（服务器地址、显示名）普通存储（SharedPreferences）
class CloudAccountManager {
  static final CloudAccountManager instance = CloudAccountManager._internal();
  CloudAccountManager._internal();

  static const _accountsKey = 'cloud_accounts_v1';
  static const _credentialsPrefix = 'cloud_cred_';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accountName: 'cloud_storage_credentials',
    ),
  );

  /// 获取所有账户列表（不含敏感凭证）
  Future<List<CloudAccount>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_accountsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((e) => CloudAccount.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('解析云存储账户列表失败: $e');
      return [];
    }
  }

  /// 保存账户列表（不含敏感凭证）
  Future<void> _saveAccounts(List<CloudAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_accountsKey, jsonStr);
  }

  /// 获取指定账户的敏感凭证
  Future<Map<String, String>> getCredentials(String accountId) async {
    final jsonStr = await _secureStorage.read(key: '$_credentialsPrefix$accountId');
    if (jsonStr == null || jsonStr.isEmpty) return {};

    try {
      final Map<String, dynamic> map = jsonDecode(jsonStr);
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      debugPrint('读取凭证失败: $e');
      return {};
    }
  }

  /// 保存敏感凭证
  Future<void> _saveCredentials(String accountId, Map<String, String> credentials) async {
    await _secureStorage.write(
      key: '$_credentialsPrefix$accountId',
      value: jsonEncode(credentials),
    );
  }

  /// 删除敏感凭证
  Future<void> _deleteCredentials(String accountId) async {
    await _secureStorage.delete(key: '$_credentialsPrefix$accountId');
  }

  /// 添加账户
  ///
  /// [account] 账户配置（不含敏感信息）
  /// [credentials] 敏感凭证（如 password、token）
  Future<void> addAccount(CloudAccount account, Map<String, String> credentials) async {
    final accounts = await getAccounts();

    // 去重：同协议 + 同显示名视为同一账户
    accounts.removeWhere((a) => a.id == account.id);
    accounts.add(account);

    await _saveAccounts(accounts);
    await _saveCredentials(account.id, credentials);
  }

  /// 更新账户配置
  Future<void> updateAccount(CloudAccount account) async {
    final accounts = await getAccounts();
    final index = accounts.indexWhere((a) => a.id == account.id);
    if (index >= 0) {
      accounts[index] = account;
      await _saveAccounts(accounts);
    }
  }

  /// 更新账户凭证
  Future<void> updateCredentials(String accountId, Map<String, String> credentials) async {
    await _saveCredentials(accountId, credentials);
  }

  /// 删除账户
  Future<void> deleteAccount(String accountId) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await _saveAccounts(accounts);
    await _deleteCredentials(accountId);
  }

  /// 获取完整账户（含凭证）
  Future<(CloudAccount?, Map<String, String>)> getAccountWithCredentials(String accountId) async {
    final accounts = await getAccounts();
    final account = accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => throw Exception('账户不存在'),
    );
    final credentials = await getCredentials(accountId);
    return (account, credentials);
  }
}
