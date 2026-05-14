import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Router;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'app_directories.dart';

class WifiTransferRecord {
  final String id;
  final String fileName;
  final String? mediaTypeLabel;
  final DateTime timestamp;
  String status;
  String? destinationPath;
  String? errorMessage;

  WifiTransferRecord({
    required this.id,
    required this.fileName,
    this.mediaTypeLabel,
    required this.timestamp,
    this.status = 'pending',
    this.destinationPath,
    this.errorMessage,
  });
}

class WifiTransferService extends ChangeNotifier {
  static final WifiTransferService instance = WifiTransferService._internal();
  WifiTransferService._internal();

  factory WifiTransferService() => instance;

  HttpServer? _server;
  String? _ipAddress;
  int _port = 8080;
  bool _isRunning = false;
  final List<String> _uploadedFiles = [];
  final Map<String, String?> _fileTypes = {};
  final StreamController<String> _uploadController = StreamController<String>.broadcast();
  final List<WifiTransferRecord> _transferHistory = [];

  bool get isRunning => _isRunning;
  String? get ipAddress => _ipAddress;
  int get port => _port;
  List<String> get uploadedFiles => List.unmodifiable(_uploadedFiles);
  Stream<String> get uploadStream => _uploadController.stream;
  List<WifiTransferRecord> get transferHistory => List.unmodifiable(_transferHistory);

  String? getFileType(String filePath) => _fileTypes[filePath];

  void addTransferRecord(String id, String fileName, String? mediaTypeLabel) {
    _transferHistory.insert(0, WifiTransferRecord(
      id: id,
      fileName: fileName,
      mediaTypeLabel: mediaTypeLabel,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void updateTransferRecord(String id, {required String status, String? destinationPath, String? errorMessage}) {
    final index = _transferHistory.indexWhere((r) => r.id == id);
    if (index >= 0) {
      final record = _transferHistory[index];
      _transferHistory[index] = WifiTransferRecord(
        id: record.id,
        fileName: record.fileName,
        mediaTypeLabel: record.mediaTypeLabel,
        timestamp: record.timestamp,
        status: status,
        destinationPath: destinationPath,
        errorMessage: errorMessage,
      );
      notifyListeners();
    }
  }

  void clearTransferHistory() {
    _transferHistory.clear();
    notifyListeners();
  }

  static bool _isValidForType(String filename, String? type) {
    if (type == null || type == 'auto') return true;
    final ext = path.extension(filename).toLowerCase().replaceAll('.', '');
    switch (type) {
      case 'novel':
        return ['txt', 'epub', 'pdf', 'mobi', 'azw3'].contains(ext);
      case 'comic':
        return ['zip', 'cbz', 'rar', 'cbr', 'pdf', 'mobi'].contains(ext);
      case 'video':
        return ['mp4', 'mkv', 'avi'].contains(ext);
      case 'music':
        return ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'].contains(ext);
      default:
        return true;
    }
  }

  Future<void> startServer() async {
    if (_isRunning) return;

    try {
      _ipAddress = await _getLocalIpAddress();
      final router = Router();

      // 上传页面
      router.get('/', (Request request) {
        return Response.ok(_uploadHtml, headers: {'Content-Type': 'text/html; charset=utf-8'});
      });

      // 文件上传接口（支持 query 参数 type=novel|comic|video|music|auto）
      // 使用流式解析，避免大文件占用大量内存
      router.post('/upload', (Request request) async {
        debugPrint('[WiFi Upload] ====== upload request received ======');
        debugPrint('[WiFi Upload] headers: ${request.headers}');
        debugPrint('[WiFi Upload] query: ${request.url.query}');

        final contentType = request.headers['content-type'];
        debugPrint('[WiFi Upload] content-type: $contentType');
        if (contentType == null || !contentType.contains('multipart/form-data')) {
          debugPrint('[WiFi Upload] ERROR: Invalid content type');
          return Response.badRequest(body: 'Invalid content type');
        }

        final uploadType = request.url.queryParameters['type'];
        final boundaryMatch = RegExp(r'boundary=([^;]+)').firstMatch(contentType);
        final rawBoundary = boundaryMatch?.group(1)?.trim() ?? '';
        final boundary = rawBoundary.replaceAll(RegExp(r'^"|"$'), '');
        debugPrint('[WiFi Upload] rawBoundary: "$rawBoundary", parsed boundary: "$boundary"');
        if (boundary.isEmpty) {
          debugPrint('[WiFi Upload] ERROR: Missing boundary in content-type');
          return Response.badRequest(body: 'Missing boundary in content-type');
        }

        try {
          final transformer = MimeMultipartTransformer(boundary);
          var partCount = 0;
          var successCount = 0;
          final uploadedFiles = <String>[];

          await for (final part in request.read().cast<List<int>>().transform(transformer)) {
            partCount++;
            debugPrint('[WiFi Upload] part #$partCount, headers: ${part.headers}');
            final disposition = part.headers['content-disposition'];
            if (disposition == null) {
              debugPrint('[WiFi Upload] part #$partCount: no content-disposition, skipping');
              continue;
            }

            final String rawFilename;
            final filenameStarMatch = RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(disposition);
            if (filenameStarMatch != null) {
              rawFilename = Uri.decodeComponent(filenameStarMatch.group(1)!);
              debugPrint('[WiFi Upload] matched filename*: $rawFilename');
            } else {
              final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
              if (filenameMatch == null) {
                debugPrint('[WiFi Upload] no filename match in disposition: $disposition');
                continue;
              }
              rawFilename = filenameMatch.group(1)!;
              debugPrint('[WiFi Upload] matched filename: $rawFilename');
            }

            // 使用 basename 防止路径遍历，同时保留文件夹上传时的子目录结构
            final safeFilename = path.basename(rawFilename);
            if (safeFilename.isEmpty) {
              debugPrint('[WiFi Upload] empty filename after basename, skipping');
              continue;
            }

            // 服务端校验：文件扩展名与所选分类是否匹配
            if (!_isValidForType(safeFilename, uploadType)) {
              debugPrint('[WiFi Upload] rejected: $safeFilename does not match type $uploadType');
              continue;
            }

            final uploadDir = Directory(AppDirectories.wifiUploadDir);
            if (!await uploadDir.exists()) {
              await uploadDir.create(recursive: true);
            }

            // 避免文件名冲突：同名文件加时间戳后缀
            final ext = path.extension(safeFilename);
            final base = path.basenameWithoutExtension(safeFilename);
            var filename = safeFilename;
            var filePath = path.join(uploadDir.path, filename);
            var counter = 1;
            while (await File(filePath).exists()) {
              filename = '${base}_${counter}_$ext';
              filePath = path.join(uploadDir.path, filename);
              counter++;
            }

            // 确保父目录存在（处理文件夹上传时可能的多层路径）
            final fileDir = path.dirname(filePath);
            await Directory(fileDir).create(recursive: true);

            // 先写入临时文件，完成后重命名，避免上传中断导致文件损坏
            final tmpPath = '$filePath.tmp';
            try {
              debugPrint('[WiFi Upload] writing to tmp: $tmpPath');
              await part.pipe(File(tmpPath).openWrite());
              debugPrint('[WiFi Upload] rename to: $filePath');
              await File(tmpPath).rename(filePath);
            } catch (e) {
              // 上传失败时清理临时文件
              try {
                final tmpFile = File(tmpPath);
                if (await tmpFile.exists()) await tmpFile.delete();
              } catch (_) {}
              rethrow;
            }

            _uploadedFiles.add(filePath);
            _fileTypes[filePath] = uploadType;
            addTransferRecord(filePath, path.basename(filePath), uploadType);
            _uploadController.add(filePath);
            uploadedFiles.add(path.basename(filePath));
            successCount++;
            debugPrint('[WiFi Upload] SUCCESS: $filePath');
          }

          if (successCount > 0) {
            return Response.ok(
              '{"success": true, "files": ${jsonEncode(uploadedFiles)}, "count": $successCount}',
              headers: {'Content-Type': 'application/json'},
            );
          }
          debugPrint('[WiFi Upload] ERROR: no valid parts processed, total parts: $partCount');
        } catch (e, st) {
          debugPrint('[WiFi Upload] ERROR exception: $e');
          debugPrint('[WiFi Upload] stack: $st');
          return Response.badRequest(
            body: jsonEncode({'success': false, 'error': 'Upload failed'}),
          );
        }

        return Response.badRequest(body: jsonEncode({'success': false, 'error': 'Upload failed'}));
      });

      // 状态接口
      router.get('/status', (Request request) {
        return Response.ok('{"status": "running", "files": ${_uploadedFiles.length}}',
            headers: {'Content-Type': 'application/json'});
      });

      final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
      _isRunning = true;
      notifyListeners();
    } catch (e) {
      _isRunning = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    _isRunning = false;
    notifyListeners();
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('获取本地 IP 失败: $e');
    }
    return null;
  }

  void clearUploadedFiles() {
    _uploadedFiles.clear();
    _fileTypes.clear();
    _transferHistory.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _uploadController.close();
    stopServer();
    super.dispose();
  }

  static const String _uploadHtml = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>拾光集 - WiFi传输</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #f5f5f7;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 480px;
            width: 100%;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        h1 {
            font-size: 28px;
            font-weight: 700;
            color: #1d1d1f;
            margin-bottom: 8px;
            text-align: center;
        }
        .subtitle {
            color: #86868b;
            font-size: 15px;
            text-align: center;
            margin-bottom: 24px;
        }
        .type-select-row {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 20px;
            padding: 0 4px;
        }
        .type-select-row label {
            font-size: 14px;
            color: #1d1d1f;
            font-weight: 500;
            white-space: nowrap;
        }
        .type-select-row select {
            flex: 1;
            padding: 10px 12px;
            border-radius: 10px;
            border: 1px solid #d2d2d7;
            background: #f5f5f7;
            font-size: 14px;
            color: #1d1d1f;
            outline: none;
            cursor: pointer;
        }
        .upload-mode-row {
            display: flex;
            gap: 8px;
            margin-bottom: 16px;
        }
        .mode-btn {
            flex: 1;
            padding: 10px;
            border-radius: 10px;
            border: 1px solid #d2d2d7;
            background: #f5f5f7;
            font-size: 13px;
            color: #1d1d1f;
            cursor: pointer;
            text-align: center;
            transition: all 0.2s;
        }
        .mode-btn.active {
            background: #0071e3;
            color: white;
            border-color: #0071e3;
        }
        .upload-area {
            border: 2px dashed #d2d2d7;
            border-radius: 16px;
            padding: 40px 24px;
            text-align: center;
            transition: all 0.3s;
            cursor: pointer;
        }
        .upload-area:hover {
            border-color: #0071e3;
            background: #f5f5f7;
        }
        .upload-area.dragover {
            border-color: #0071e3;
            background: #e8f4fd;
        }
        .upload-icon {
            font-size: 40px;
            margin-bottom: 10px;
        }
        .upload-text {
            font-size: 17px;
            color: #1d1d1f;
            font-weight: 600;
            margin-bottom: 4px;
        }
        .upload-hint {
            font-size: 13px;
            color: #86868b;
        }
        .file-list {
            margin-top: 24px;
        }
        .file-item {
            display: flex;
            align-items: center;
            padding: 12px;
            background: #f5f5f7;
            border-radius: 10px;
            margin-bottom: 8px;
        }
        .file-name {
            flex: 1;
            font-size: 14px;
            color: #1d1d1f;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .file-status {
            font-size: 12px;
            color: #34c759;
            font-weight: 600;
        }
        input[type="file"] { display: none; }
    </style>
</head>
<body>
    <div class="container">
        <h1>WiFi 文件传输</h1>
        <p class="subtitle">选择文件或拖拽到下方上传</p>
        <div class="type-select-row">
            <label>导入分类</label>
            <select id="typeSelect">
                <option value="auto">自动识别</option>
                <option value="novel">小说</option>
                <option value="comic">漫画</option>
                <option value="video">视频</option>
                <option value="music">音乐</option>
            </select>
        </div>
        <div class="upload-mode-row">
            <button class="mode-btn active" id="modeFile" onclick="setMode('file')">选择文件</button>
            <button class="mode-btn" id="modeFolder" onclick="setMode('folder')">选择文件夹</button>
        </div>
        <div class="upload-area" id="uploadArea">
            <div class="upload-icon">&#128228;</div>
            <div class="upload-text" id="uploadText">点击选择文件</div>
            <div class="upload-hint" id="uploadHint">支持小说、漫画、视频、音乐</div>
            <input type="file" id="fileInput" multiple accept=".txt,.epub,.pdf,.mobi,.azw3,.zip,.cbz,.rar,.cbr,.mp4,.mkv,.avi,.mp3,.flac,.wav,.aac,.ogg,.m4a">
        </div>
        <div class="file-list" id="fileList"></div>
    </div>
    <script>
        const uploadArea = document.getElementById('uploadArea');
        const fileInput = document.getElementById('fileInput');
        const fileList = document.getElementById('fileList');
        const typeSelect = document.getElementById('typeSelect');
        const uploadText = document.getElementById('uploadText');
        const uploadHint = document.getElementById('uploadHint');
        const modeFile = document.getElementById('modeFile');
        const modeFolder = document.getElementById('modeFolder');
        let currentMode = 'file';

        function setMode(mode) {
            currentMode = mode;
            if (mode === 'folder') {
                modeFile.classList.remove('active');
                modeFolder.classList.add('active');
                fileInput.setAttribute('webkitdirectory', '');
                fileInput.removeAttribute('multiple');
                uploadText.textContent = '点击选择文件夹';
                uploadHint.textContent = '将导入文件夹内的所有支持文件';
            } else {
                modeFolder.classList.remove('active');
                modeFile.classList.add('active');
                fileInput.removeAttribute('webkitdirectory');
                fileInput.setAttribute('multiple', '');
                uploadText.textContent = '点击选择文件';
                uploadHint.textContent = '支持小说、漫画、视频、音乐';
            }
        }

        uploadArea.addEventListener('click', () => fileInput.click());

        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadArea.classList.add('dragover');
        });

        uploadArea.addEventListener('dragleave', () => {
            uploadArea.classList.remove('dragover');
        });

        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadArea.classList.remove('dragover');
            handleFiles(e.dataTransfer.files);
        });

        fileInput.addEventListener('change', (e) => {
            handleFiles(e.target.files);
        });

        function handleFiles(files) {
            for (const file of files) {
                uploadFile(file);
            }
        }

        const typeExtMap = {
            'novel': ['txt', 'epub', 'pdf', 'mobi', 'azw3'],
            'comic': ['zip', 'cbz', 'rar', 'cbr', 'pdf', 'mobi'],
            'video': ['mp4', 'mkv', 'avi'],
            'music': ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a'],
        };

        function validateFileForType(file, type) {
            if (type === 'auto') return { valid: true };
            const ext = file.name.split('.').pop().toLowerCase();
            const allowed = typeExtMap[type];
            if (allowed && allowed.includes(ext)) return { valid: true };
            return { valid: false, ext, allowed };
        }

        async function uploadFile(file) {
            const item = document.createElement('div');
            item.className = 'file-item';
            item.innerHTML = `<span class="file-name">\${file.webkitRelativePath || file.name}</span><span class="file-status">上传中...</span>`;
            fileList.prepend(item);

            const type = typeSelect.value;
            const validation = validateFileForType(file, type);
            if (!validation.valid) {
                item.querySelector('.file-status').textContent = '不支持：该文件类型不属于所选分类';
                item.querySelector('.file-status').style.color = '#ff3b30';
                return;
            }

            const formData = new FormData();
            formData.append('file', file);
            const url = type === 'auto' ? '/upload' : '/upload?type=' + encodeURIComponent(type);

            try {
                const response = await fetch(url, {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();
                if (result.success) {
                    item.querySelector('.file-status').textContent = '完成';
                } else {
                    item.querySelector('.file-status').textContent = '失败';
                    item.querySelector('.file-status').style.color = '#ff3b30';
                }
            } catch (err) {
                item.querySelector('.file-status').textContent = '失败';
                item.querySelector('.file-status').style.color = '#ff3b30';
            }
        }
    </script>
</body>
</html>
''';
}
