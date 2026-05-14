import 'comic_series.dart';
import 'library_item.dart';

class ComicChapter {
  final int? id;
  final int seriesId;
  final String? title;
  final double? chapterNumber;
  final int? volumeNumber;
  final String filePath;
  final FileFormat format;
  final int pageCount;
  final int? fileSize;
  final int sortOrder;
  bool isRead;
  String? coverPath;
  final DateTime createdAt;

  ComicChapter({
    this.id,
    required this.seriesId,
    this.title,
    this.chapterNumber,
    this.volumeNumber,
    required this.filePath,
    required this.format,
    this.pageCount = 0,
    this.fileSize,
    this.sortOrder = 0,
    this.isRead = false,
    this.coverPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'seriesId': seriesId,
      'title': title,
      'chapterNumber': chapterNumber,
      'volumeNumber': volumeNumber,
      'filePath': filePath,
      'format': format.index,
      'pageCount': pageCount,
      'fileSize': fileSize,
      'sortOrder': sortOrder,
      'isRead': isRead ? 1 : 0,
      'coverPath': coverPath,
      'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory ComicChapter.fromMap(Map<String, dynamic> map) {
    return ComicChapter(
      id: map['id'] as int?,
      seriesId: map['seriesId'] as int,
      title: map['title'] as String?,
      chapterNumber: map['chapterNumber'] as double?,
      volumeNumber: map['volumeNumber'] as int?,
      filePath: map['filePath'] as String,
      format: FileFormat.values[(map['format'] as int? ?? 0).clamp(0, FileFormat.values.length - 1)],
      pageCount: map['pageCount'] as int? ?? 0,
      fileSize: map['fileSize'] as int?,
      sortOrder: map['sortOrder'] as int? ?? 0,
      isRead: (map['isRead'] as int? ?? 0) == 1,
      coverPath: map['coverPath'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as int) * 1000)
          : DateTime.now(),
    );
  }

  LibraryItem toLibraryItem(ComicSeries series) {
    return LibraryItem(
      title: title ?? series.title,
      mediaType: MediaType.comic,
      format: format,
      filePath: filePath,
      coverPath: series.coverPath,
      author: series.author,
      description: series.description,
      tags: series.tags,
      addedDate: createdAt,
      fileSize: fileSize,
    );
  }

  ComicChapter copyWith({
    int? id,
    int? seriesId,
    String? title,
    double? chapterNumber,
    int? volumeNumber,
    String? filePath,
    FileFormat? format,
    int? pageCount,
    int? fileSize,
    int? sortOrder,
    bool? isRead,
    String? coverPath,
    DateTime? createdAt,
  }) {
    return ComicChapter(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      title: title ?? this.title,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      volumeNumber: volumeNumber ?? this.volumeNumber,
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      pageCount: pageCount ?? this.pageCount,
      fileSize: fileSize ?? this.fileSize,
      sortOrder: sortOrder ?? this.sortOrder,
      isRead: isRead ?? this.isRead,
      coverPath: coverPath ?? this.coverPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
