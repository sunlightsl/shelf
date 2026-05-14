/// 云端文件/文件夹模型
class CloudFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedDate;
  final String? etag;

  CloudFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedDate,
    this.etag,
  });

  CloudFile copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    int? size,
    DateTime? modifiedDate,
    String? etag,
  }) {
    return CloudFile(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      etag: etag ?? this.etag,
    );
  }
}

/// 下载进度回调
typedef DownloadProgressCallback = void Function(int received, int total);
