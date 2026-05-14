import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../design_tokens/app_colors.dart';

/// 阿里云盘 WebView 授权页面
///
/// 流程：
/// 1. 加载阿里云盘网页版
/// 2. 用户登录（短信/密码/扫码）
/// 3. 登录成功后点击右上角"获取 Token"
/// 4. 注入 JS 从 localStorage 提取 refresh_token
/// 5. 返回 token 给调用方
class AliyunDriveAuthScreen extends StatefulWidget {
  const AliyunDriveAuthScreen({super.key});

  @override
  State<AliyunDriveAuthScreen> createState() => _AliyunDriveAuthScreenState();
}

class _AliyunDriveAuthScreenState extends State<AliyunDriveAuthScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) {
            // 过滤统计埋点、风控脚本的非致命错误，减少噪音
            final url = error.url ?? '';
            final desc = error.description;
            if (url.contains('alicdn.com') ||
                url.contains('aliyun.com') ||
                desc?.contains('CONNECTION_REFUSED') == true ||
                desc?.contains('ERR_BLOCKED_BY_CLIENT') == true) {
              return;
            }
            debugPrint('WebView 错误: $desc [$url]');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.aliyundrive.com/sign/in'));
  }

  /// 从 localStorage 中提取 refresh_token
  Future<void> _extractToken() async {
    setState(() => _isExtracting = true);

    try {
      // 尝试多种方式提取 token
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          // 方式1: 直接读取 localStorage 中的常见键
          var keys = ['token', 'refresh_token', 'refreshToken', 'user'];
          for (var i = 0; i < keys.length; i++) {
            var value = localStorage.getItem(keys[i]);
            if (value) {
              try {
                var parsed = JSON.parse(value);
                if (parsed.refresh_token) return parsed.refresh_token;
                if (parsed.token && parsed.token.refresh_token) return parsed.token.refresh_token;
                if (typeof parsed === 'string' && parsed.length > 20) return parsed;
              } catch(e) {
                if (value.length > 20) return value;
              }
            }
          }

          // 方式2: 遍历所有 localStorage 键，找最长的字符串（通常是 token）
          var longestValue = '';
          for (var j = 0; j < localStorage.length; j++) {
            var k = localStorage.key(j);
            var v = localStorage.getItem(k);
            if (v && v.length > longestValue.length && v.length > 20) {
              try {
                var p = JSON.parse(v);
                if (p.refresh_token) return p.refresh_token;
                if (p.token && p.token.refresh_token) return p.token.refresh_token;
              } catch(e) {}
              longestValue = v;
            }
          }
          return longestValue.length > 20 ? longestValue : '';
        })()
      ''');

      var token = '';
      if (result is String) {
        token = result;
      }

      // 去除 Dart JS 返回的引号包裹
      if (token.startsWith('"') && token.endsWith('"')) {
        token = token.substring(1, token.length - 1);
      }

      if (token.isEmpty || token == 'null') {
        if (mounted) {
          _showError('未获取到 token，请确保已登录。如果仍失败，请手动复制 refresh_token。');
        }
        return;
      }

      if (mounted) {
        Navigator.pop(context, token);
      }
    } catch (e) {
      debugPrint('提取 token 失败: $e');
      if (mounted) {
        _showError('提取失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('获取失败'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阿里云盘登录'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isExtracting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CupertinoActivityIndicator(),
            )
          else
            TextButton(
              onPressed: _extractToken,
              child: const Text('获取 Token'),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CupertinoActivityIndicator()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: NeutralPalette.of(context).surface,
          child: Row(
            children: [
              Icon(CupertinoIcons.info_circle, size: 16, color: NeutralPalette.of(context).textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '请先登录阿里云盘，登录成功后点击右上角"获取 Token"',
                  style: TextStyle(fontSize: 12, color: NeutralPalette.of(context).textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
