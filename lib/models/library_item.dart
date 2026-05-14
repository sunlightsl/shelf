import 'package:path/path.dart' as p;

enum MediaType { novel, comic, video, music }

enum SortMode { title, modifiedTime, addedTime, lastOpenedTime }

enum FileFormat {
  txt,
  epub,
  pdf,
  mobi,
  azw3,
  zip,
  cbz,
  rar,
  cbr,
  mp4,
  mkv,
  avi,
  unknown,
  mp3,
  flac,
  wav,
  aac,
  ogg,
  m4a,
}

class LibraryItem {
  final int? id;
  final String title;
  final MediaType mediaType;
  final FileFormat format;
  final String filePath;
  final String? relativeFolderPath;
  String? coverPath;
  final String? author;
  final String? description;
  final List<String> tags;
  final DateTime addedDate;
  DateTime? lastOpenedDate;
  final int? fileSize;
  int? totalProgress;
  bool isFavorite;
  DateTime? deletedAt;
  bool isPrivate;

  // 云端来源字段
  final String? sourceType;
  final String? sourceAccountId;
  final String? remoteId;
  final String? remoteCoverUrl;
  final String? streamUrl;

  LibraryItem({
    this.id,
    required this.title,
    required this.mediaType,
    required this.format,
    required this.filePath,
    this.relativeFolderPath,
    this.coverPath,
    this.author,
    this.description,
    this.tags = const [],
    required this.addedDate,
    this.lastOpenedDate,
    this.fileSize,
    this.totalProgress,
    this.isFavorite = false,
    this.deletedAt,
    this.isPrivate = false,
    this.sourceType,
    this.sourceAccountId,
    this.remoteId,
    this.remoteCoverUrl,
    this.streamUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'mediaType': mediaType.index,
      'format': format.index,
      'filePath': filePath,
      'relativeFolderPath': relativeFolderPath,
      'coverPath': coverPath,
      'author': author,
      'description': description,
      'tags': tags.join(','),
      'addedDate': addedDate.toIso8601String(),
      'lastOpenedDate': lastOpenedDate?.toIso8601String(),
      'fileSize': fileSize,
      'totalProgress': totalProgress,
      'isFavorite': isFavorite ? 1 : 0,
      'deletedAt': deletedAt?.toIso8601String(),
      'isPrivate': isPrivate ? 1 : 0,
      'sourceType': sourceType,
      'sourceAccountId': sourceAccountId,
      'remoteId': remoteId,
      'remoteCoverUrl': remoteCoverUrl,
      'streamUrl': streamUrl,
    };
  }

  factory LibraryItem.fromMap(Map<String, dynamic> map) {
    return LibraryItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      mediaType: MediaType.values[map['mediaType'] as int],
      format: FileFormat.values[map['format'] as int],
      filePath: map['filePath'] as String,
      relativeFolderPath: map['relativeFolderPath'] as String?,
      coverPath: map['coverPath'] as String?,
      author: map['author'] as String?,
      description: map['description'] as String?,
      tags: (map['tags'] as String? ?? '').isEmpty
          ? const []
          : (map['tags'] as String).split(','),
      addedDate: DateTime.parse(map['addedDate'] as String),
      lastOpenedDate: map['lastOpenedDate'] != null
          ? DateTime.parse(map['lastOpenedDate'] as String)
          : null,
      fileSize: map['fileSize'] as int?,
      totalProgress: map['totalProgress'] as int?,
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      deletedAt: map['deletedAt'] != null
          ? DateTime.parse(map['deletedAt'] as String)
          : null,
      isPrivate: (map['isPrivate'] as int? ?? 0) == 1,
      sourceType: map['sourceType'] as String?,
      sourceAccountId: map['sourceAccountId'] as String?,
      remoteId: map['remoteId'] as String?,
      remoteCoverUrl: map['remoteCoverUrl'] as String?,
      streamUrl: map['streamUrl'] as String?,
    );
  }

  LibraryItem copyWith({
    int? id,
    String? title,
    MediaType? mediaType,
    FileFormat? format,
    String? filePath,
    String? relativeFolderPath,
    String? coverPath,
    String? author,
    String? description,
    List<String>? tags,
    DateTime? addedDate,
    DateTime? lastOpenedDate,
    int? fileSize,
    int? totalProgress,
    bool? isFavorite,
    DateTime? deletedAt,
    bool? isPrivate,
    String? sourceType,
    String? sourceAccountId,
    String? remoteId,
    String? remoteCoverUrl,
    String? streamUrl,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      mediaType: mediaType ?? this.mediaType,
      format: format ?? this.format,
      filePath: filePath ?? this.filePath,
      relativeFolderPath: relativeFolderPath ?? this.relativeFolderPath,
      coverPath: coverPath ?? this.coverPath,
      author: author ?? this.author,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      addedDate: addedDate ?? this.addedDate,
      lastOpenedDate: lastOpenedDate ?? this.lastOpenedDate,
      fileSize: fileSize ?? this.fileSize,
      totalProgress: totalProgress ?? this.totalProgress,
      isFavorite: isFavorite ?? this.isFavorite,
      deletedAt: deletedAt ?? this.deletedAt,
      isPrivate: isPrivate ?? this.isPrivate,
      sourceType: sourceType ?? this.sourceType,
      sourceAccountId: sourceAccountId ?? this.sourceAccountId,
      remoteId: remoteId ?? this.remoteId,
      remoteCoverUrl: remoteCoverUrl ?? this.remoteCoverUrl,
      streamUrl: streamUrl ?? this.streamUrl,
    );
  }

  /// 是否为云端来源（非本地文件）
  bool get isCloudSource => sourceType != null && sourceType != 'local';

  /// 获取有效的封面路径/URL（优先远程封面）
  String? get effectiveCover => remoteCoverUrl ?? coverPath;
}

extension FileFormatExtension on String {
  FileFormat toFileFormat() {
    final ext = toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'txt':
        return FileFormat.txt;
      case 'epub':
        return FileFormat.epub;
      case 'pdf':
        return FileFormat.pdf;
      case 'mobi':
        return FileFormat.mobi;
      case 'azw3':
        return FileFormat.azw3;
      case 'zip':
        return FileFormat.zip;
      case 'cbz':
        return FileFormat.cbz;
      case 'rar':
        return FileFormat.rar;
      case 'cbr':
        return FileFormat.cbr;
      case 'mp4':
        return FileFormat.mp4;
      case 'mkv':
        return FileFormat.mkv;
      case 'avi':
        return FileFormat.avi;
      case 'mp3':
        return FileFormat.mp3;
      case 'flac':
        return FileFormat.flac;
      case 'wav':
        return FileFormat.wav;
      case 'aac':
        return FileFormat.aac;
      case 'ogg':
        return FileFormat.ogg;
      case 'm4a':
        return FileFormat.m4a;
      default:
        return FileFormat.unknown;
    }
  }
}

FileFormat getFormatFromPath(String path) {
  final ext = p.extension(path).toLowerCase().replaceAll('.', '');
  return ext.toFileFormat();
}

MediaType getMediaTypeFromFormat(FileFormat format) {
  switch (format) {
    case FileFormat.txt:
    case FileFormat.epub:
    case FileFormat.pdf:
    case FileFormat.mobi:
    case FileFormat.azw3:
      return MediaType.novel;
    case FileFormat.zip:
    case FileFormat.cbz:
    case FileFormat.rar:
    case FileFormat.cbr:
      return MediaType.comic;
    case FileFormat.mp4:
    case FileFormat.mkv:
    case FileFormat.avi:
      return MediaType.video;
    case FileFormat.mp3:
    case FileFormat.flac:
    case FileFormat.wav:
    case FileFormat.aac:
    case FileFormat.ogg:
    case FileFormat.m4a:
      return MediaType.music;
    case FileFormat.unknown:
      return MediaType.novel;
  }
}
