import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/cloud_file.dart';
import '../models/library_item.dart';
import '../services/cloud_storage/cloud_account.dart';
import '../services/cloud_storage/cloud_storage.dart';
import '../services/cloud_storage/cloud_sync_service.dart';
import '../services/cloud_storage/cloud_account_manager.dart';
import '../services/cloud_storage/cloud_storage_factory.dart';
import '../services/music_scan_service.dart';
import '../providers/library_provider.dart';
import 'readers/video_player_screen.dart';
import '../providers/comic_series_provider.dart';
import '../design_tokens/app_colors.dart';
import 'package:provider/provider.dart';

class CloudStorageBrowserScreen extends StatefulWidget {
  final CloudAccount account;

  const CloudStorageBrowserScreen({super.key, required this.account});

  @override
  State<CloudStorageBrowserScreen> createState() => _CloudStorageBrowserScreenState();
}

class _CloudStorageBrowserScreenState extends State<CloudStorageBrowserScreen> {
  final List<String> _pathStack = [];
  List<CloudFile> _items = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _selectedPaths = {};
  bool _isMultiSelect = false;

  String get _currentPath => _pathStack.isEmpty ? widget.account.rootPath : _pathStack.last;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await CloudSyncService.instance.browseDirectory(
        widget.account.id,
        _currentPath,
      );
      // 过滤掉 . 和 ..
      final filtered = items.where((i) => i.name != '.' && i.name != '..').toList();
      // 文件夹在前，文件在后，均按名称排序
      filtered.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() {
        _items = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _enterDirectory(CloudFile folder) {
    setState(() => _pathStack.add(folder.path));
    _loadDirectory();
  }

  void _goBack() {
    if (_pathStack.isNotEmpty) {
      setState(() => _pathStack.removeLast());
      _loadDirectory();
    }
  }

  void _toggleSelection(CloudFile file) {
    setState(() {
      if (_selectedPaths.contains(file.path)) {
        _selectedPaths.remove(file.path);
      } else {
        _selectedPaths.add(file.path);
      }
    });
  }

  Future<void> _downloadSelected() async {
    final selected = _items.where((i) => _selectedPaths.contains(i.path)).toList();
    if (selected.isEmpty) return;

    // 推断媒体类型
    final mediaType = _detectMediaType(selected);
    if (mediaType == null) {
      _showError('无法识别所选文件的媒体类型');
      return;
    }

    final downloaded = <String>[];
    final failed = <String>[];

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        files: selected,
        accountId: widget.account.id,
        mediaType: mediaType,
        onDone: (ok, fail) {
          downloaded.addAll(ok);
          failed.addAll(fail);
        },
        onComplete: () {
          if (!mounted) return;
          if (mediaType == MediaType.comic) {
            context.read<ComicSeriesProvider>().loadSeries();
          } else {
            context.read<LibraryProvider>().loadLibrary();
            if (mediaType == MediaType.music) {
              MusicScanService.instance.syncFromLibrary();
            }
          }
        },
      ),
    );

    setState(() {
      _isMultiSelect = false;
      _selectedPaths.clear();
    });
  }

  MediaType? _detectMediaType(List<CloudFile> files) {
    // 媒体服务器（Jellyfin/Emby）的文件名通常不带扩展名，按协议推断为视频
    if (widget.account.protocol == 'jellyfin' || widget.account.protocol == 'emby') {
      return MediaType.video;
    }
    final exts = files.map((f) => p.extension(f.name).toLowerCase()).toList();
    if (exts.any((e) => ['.txt', '.epub', '.pdf', '.mobi', '.azw3'].contains(e))) {
      return MediaType.novel;
    }
    if (exts.any((e) => ['.zip', '.cbz', '.rar', '.cbr', '.pdf'].contains(e))) {
      return MediaType.comic;
    }
    if (exts.any((e) => ['.mp4', '.mkv', '.avi'].contains(e))) {
      return MediaType.video;
    }
    if (exts.any((e) => ['.mp3', '.flac', '.wav', '.aac', '.ogg', '.m4a'].contains(e))) {
      return MediaType.music;
    }
    return null;
  }

  bool _isVideoFile(CloudFile file) {
    // 媒体服务器（Jellyfin/Emby）的 item 名称通常不带扩展名，根据协议类型判断
    if (widget.account.protocol == 'jellyfin' || widget.account.protocol == 'emby') {
      return !file.isDirectory;
    }
    final ext = p.extension(file.name).toLowerCase();
    return ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.m4v'].contains(ext);
  }

  Future<void> _playStream(CloudFile file) async {
    try {
      final credentials = await CloudAccountManager.instance.getCredentials(widget.account.id);
      final storage = CloudStorageFactory.create(widget.account.protocol);
      final ok = await storage.connect({...widget.account.config, ...credentials});
      if (!ok) {
        _showError('连接失败，无法串流播放');
        return;
      }

      String? finalUrl;

      // WebDAV / 飞牛OS: 直接构造带 Basic Auth 的 URL
      if (widget.account.protocol == 'webdav' || widget.account.protocol == 'fnos') {
        final streamUrl = storage.getStreamUrl(file.path);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          final username = credentials['username'];
          final password = credentials['password'];
          if (username != null && password != null) {
            final uri = Uri.parse(streamUrl);
            final userInfo = Uri.encodeComponent(username) + ':' + Uri.encodeComponent(password);
            finalUrl = uri.replace(userInfo: userInfo).toString();
          } else {
            finalUrl = streamUrl;
          }
        }
      }
      // 123云盘: 异步获取下载链接
      else if (widget.account.protocol == 'pan123') {
        final pan123 = storage as dynamic;
        finalUrl = await pan123.getStreamUrlAsync(file.path);
      }
      // 阿里云盘: 异步获取下载链接
      else if (widget.account.protocol == 'aliyundrive') {
        final aliyun = storage as dynamic;
        finalUrl = await aliyun.getStreamUrlAsync(file.path);
      }
      // Jellyfin / Emby: 同步获取串流 URL
      else if (widget.account.protocol == 'jellyfin' ||
          widget.account.protocol == 'emby') {
        finalUrl = storage.getStreamUrl(file.path);
      }
      // S3: 暂不支持直接串流
      else {
        _showError('该协议暂不支持直接串流播放');
        return;
      }

      if (finalUrl == null || finalUrl.isEmpty) {
        _showError('无法获取串流链接');
        return;
      }

      final tempItem = LibraryItem(
        title: p.basenameWithoutExtension(file.name),
        mediaType: MediaType.video,
        format: FileFormat.mp4,
        filePath: finalUrl,
        addedDate: DateTime.now(),
      );

      if (!mounted) return;
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => VideoPlayerScreen(item: tempItem, streamUrl: finalUrl),
        ),
      );
    } catch (e) {
      _showError('串流播放失败: $e');
    }
  }

  void _showFileOptions(CloudFile file) {
    final mediaType = _detectMediaType([file]);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isVideoFile(file))
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _playStream(file);
              },
              child: const Text('直接播放'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadSingle(file);
            },
            child: const Text('下载到本地'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _downloadSingle(CloudFile file) async {
    final mediaType = _detectMediaType([file]);
    if (mediaType == null) {
      _showError('不支持的文件格式');
      return;
    }

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        files: [file],
        accountId: widget.account.id,
        mediaType: mediaType,
        onComplete: () {
          if (!mounted) return;
          if (mediaType == MediaType.comic) {
            context.read<ComicSeriesProvider>().loadSeries();
          } else {
            context.read<LibraryProvider>().loadLibrary();
            if (mediaType == MediaType.music) {
              MusicScanService.instance.syncFromLibrary();
            }
          }
        },
      ),
    );
  }

  Future<void> _syncCurrentFolder() async {
    // 推断当前目录的媒体类型
    final files = _items.where((i) => !i.isDirectory).toList();
    final mediaType = _detectMediaType(files);
    if (mediaType == null) {
      _showError('当前目录无法识别媒体类型');
      return;
    }

    setState(() => _isLoading = true);

    List<CloudFile> toDownload;
    try {
      toDownload = await CloudSyncService.instance.scanForDownloads(
        widget.account.id,
        _currentPath,
        mediaType,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('扫描失败: $e');
      return;
    }

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (toDownload.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('同步完成'),
          content: const Text('当前目录已与本地保持同步，无新文件。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    // 显示可下载文件列表，供用户选择
    final selected = await showCupertinoDialog<Set<String>>(
      context: context,
      builder: (ctx) => _SyncFilesDialog(
        files: toDownload,
        mediaType: mediaType,
      ),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    final downloadFiles = toDownload.where((f) => selected.contains(f.path)).toList();

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        files: downloadFiles,
        accountId: widget.account.id,
        mediaType: mediaType,
        onComplete: () {
          if (!mounted) return;
          if (mediaType == MediaType.comic) {
            context.read<ComicSeriesProvider>().loadSeries();
          } else {
            context.read<LibraryProvider>().loadLibrary();
            if (mediaType == MediaType.music) {
              MusicScanService.instance.syncFromLibrary();
            }
          }
        },
      ),
    );
  }

  void _showError(String msg) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('下载失败'),
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
        title: Text(
          _pathStack.isEmpty ? widget.account.displayName : p.basename(_currentPath),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () {
            if (_pathStack.isNotEmpty) {
              _goBack();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_isMultiSelect)
            TextButton(
              onPressed: _selectedPaths.isEmpty ? null : _downloadSelected,
              child: Text('下载(${_selectedPaths.length})'),
            )
          else ...[
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_2_circlepath),
              onPressed: _syncCurrentFolder,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.checkmark_circle),
              onPressed: () => setState(() => _isMultiSelect = true),
            ),
          ],
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _isMultiSelect
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => setState(() {
                          _isMultiSelect = false;
                          _selectedPaths.clear();
                        }),
                        child: const Text('取消'),
                      ),
                    ),
                    Expanded(
                      child: CupertinoButton.filled(
                        onPressed: _selectedPaths.isEmpty ? null : _downloadSelected,
                        child: Text('下载 ${_selectedPaths.length} 项'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle, size: 48, color: FunctionalColors.warning),
            const SizedBox(height: 12),
            Text('加载失败', style: TextStyle(fontSize: 16, color: Colors.grey[700])),
            const SizedBox(height: 4),
            Text(_error!, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: _loadDirectory,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('空文件夹', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isSelected = _selectedPaths.contains(item.path);

        return ListTile(
          leading: Icon(
            item.isDirectory ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill,
            color: item.isDirectory ? AppColors.primary : NeutralPalette.of(context).textSecondary,
          ),
          title: Text(item.name),
          subtitle: item.isDirectory
              ? const Text('文件夹')
              : Text(_formatSize(item.size)),
          trailing: _isMultiSelect
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(item),
                )
              : item.isDirectory
                  ? const Icon(CupertinoIcons.chevron_right, size: 18)
                  : IconButton(
                      icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 20),
                      onPressed: () => _showFileOptions(item),
                    ),
          onTap: () {
            if (_isMultiSelect) {
              _toggleSelection(item);
            } else if (item.isDirectory) {
              _enterDirectory(item);
            } else {
              _showFileOptions(item);
            }
          },
          onLongPress: () {
            if (!_isMultiSelect && !item.isDirectory) {
              setState(() {
                _isMultiSelect = true;
                _selectedPaths.add(item.path);
              });
            }
          },
        );
      },
    );
  }

  String _formatSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 下载进度对话框
class _DownloadProgressDialog extends StatefulWidget {
  final List<CloudFile> files;
  final String accountId;
  final MediaType mediaType;
  final void Function(List<String>, List<String>)? onDone;
  final VoidCallback? onComplete;

  const _DownloadProgressDialog({
    required this.files,
    required this.accountId,
    required this.mediaType,
    this.onDone,
    this.onComplete,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  int _currentIndex = 0;
  int _currentReceived = 0;
  int _currentTotal = 1;
  final List<String> _downloaded = [];
  final List<String> _failed = [];
  bool _isDone = false;
  final CloudCancelToken _cancelToken = CloudCancelToken();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    for (int i = 0; i < widget.files.length; i++) {
      if (!mounted) return;
      setState(() {
        _currentIndex = i;
        _currentReceived = 0;
        _currentTotal = widget.files[i].size ?? 1;
      });

      try {
        final item = await CloudSyncService.instance.downloadFile(
          widget.accountId,
          widget.files[i],
          widget.mediaType,
          onProgress: (received, total) {
            if (mounted) {
              setState(() {
                _currentReceived = received;
                _currentTotal = total > 0 ? total : 1;
              });
            }
          },
          cancelToken: _cancelToken,
        );

        if (item != null) {
          _downloaded.add(widget.files[i].name);
        } else {
          _failed.add(widget.files[i].name);
        }
      } catch (e) {
        _failed.add(widget.files[i].name);
      }
    }

    if (mounted) {
      setState(() => _isDone = true);
      widget.onDone?.call(_downloaded, _failed);
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFile = widget.files[_currentIndex];
    final progress = _currentReceived / _currentTotal;

    return CupertinoAlertDialog(
      title: Text(_isDone ? '下载完成' : '正在下载'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          if (!_isDone) ...[
            Text(
              '${_currentIndex + 1} / ${widget.files.length}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              currentFile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ] else ...[
            Text('成功: ${_downloaded.length}  失败: ${_failed.length}'),
            if (_failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '失败文件:\n${_failed.join("\n")}',
                style: TextStyle(fontSize: 12, color: Colors.red[400]),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
      actions: [
        if (_isDone)
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          )
        else
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              _cancelToken.cancel('用户取消');
              Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
      ],
    );
  }
}

/// 同步文件选择对话框
/// 显示云端可下载的文件列表，供用户选择
class _SyncFilesDialog extends StatefulWidget {
  final List<CloudFile> files;
  final MediaType mediaType;

  const _SyncFilesDialog({
    required this.files,
    required this.mediaType,
  });

  @override
  State<_SyncFilesDialog> createState() => _SyncFilesDialogState();
}

class _SyncFilesDialogState extends State<_SyncFilesDialog> {
  final Set<String> _selected = {};
  bool _selectAll = true;

  @override
  void initState() {
    super.initState();
    for (final f in widget.files) {
      _selected.add(f.path);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selected.clear();
        _selectAll = false;
      } else {
        for (final f in widget.files) {
          _selected.add(f.path);
        }
        _selectAll = true;
      }
    });
  }

  String _formatSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = widget.files.fold<int>(0, (sum, f) => sum + (f.size ?? 0));

    return CupertinoAlertDialog(
      title: Text('发现 ${widget.files.length} 个新文件'),
      content: SizedBox(
        height: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              '类型: ${widget.mediaType.name} · 总大小: ${_formatSize(totalSize)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _toggleSelectAll,
              child: Text(
                _selectAll ? '取消全选' : '全选',
                style: TextStyle(fontSize: 14, color: AppColors.primary),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.files.length,
                itemBuilder: (context, index) {
                  final file = widget.files[index];
                  final isSelected = _selected.contains(file.path);
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: (_) {
                        setState(() {
                          if (isSelected) {
                            _selected.remove(file.path);
                          } else {
                            _selected.add(file.path);
                          }
                          _selectAll = _selected.length == widget.files.length;
                        });
                      },
                    ),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: Text(
                      _formatSize(file.size),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('下载 ${_selected.length} 个'),
        ),
      ],
    );
  }
}
