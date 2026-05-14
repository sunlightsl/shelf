class ComicSeries {
  final int? id;
  final String title;
  final String? folderPath;
  String? coverPath;
  final String? author;
  final String? description;
  final SeriesStatus status;
  final int totalChapters;
  final int readChapters;
  bool isFavorite;
  final List<String> tags;
  final ComicSourceType sourceType;
  final DateTime createdAt;
  DateTime? updatedAt;
  DateTime? lastReadAt;
  DateTime? deletedAt;
  bool isPrivate;

  ComicSeries({
    this.id,
    required this.title,
    this.folderPath,
    this.coverPath,
    this.author,
    this.description,
    this.status = SeriesStatus.ongoing,
    this.totalChapters = 0,
    this.readChapters = 0,
    this.isFavorite = false,
    this.tags = const [],
    this.sourceType = ComicSourceType.folderSeries,
    DateTime? createdAt,
    this.updatedAt,
    this.lastReadAt,
    this.deletedAt,
    this.isPrivate = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'folderPath': folderPath,
      'coverPath': coverPath,
      'author': author,
      'description': description,
      'status': status.index,
      'totalChapters': totalChapters,
      'readChapters': readChapters,
      'isFavorite': isFavorite ? 1 : 0,
      'tags': tags.join(','),
      'sourceType': sourceType.index,
      'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updatedAt': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'lastReadAt': lastReadAt != null ? lastReadAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'deletedAt': deletedAt != null ? deletedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'isPrivate': isPrivate ? 1 : 0,
    };
  }

  factory ComicSeries.fromMap(Map<String, dynamic> map) {
    return ComicSeries(
      id: map['id'] as int?,
      title: map['title'] as String,
      folderPath: map['folderPath'] as String?,
      coverPath: map['coverPath'] as String?,
      author: map['author'] as String?,
      description: map['description'] as String?,
      status: SeriesStatus.values[(map['status'] as int? ?? 0).clamp(0, SeriesStatus.values.length - 1)],
      totalChapters: map['totalChapters'] as int? ?? 0,
      readChapters: map['readChapters'] as int? ?? 0,
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      tags: (map['tags'] as String? ?? '').isEmpty
          ? const []
          : (map['tags'] as String).split(','),
      sourceType: ComicSourceType.values[(map['sourceType'] as int? ?? 0).clamp(0, ComicSourceType.values.length - 1)],
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as int) * 1000)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['updatedAt'] as int) * 1000)
          : null,
      lastReadAt: map['lastReadAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['lastReadAt'] as int) * 1000)
          : null,
      deletedAt: map['deletedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['deletedAt'] as int) * 1000)
          : null,
      isPrivate: (map['isPrivate'] as int? ?? 0) == 1,
    );
  }

  ComicSeries copyWith({
    int? id,
    String? title,
    String? folderPath,
    String? coverPath,
    String? author,
    String? description,
    SeriesStatus? status,
    int? totalChapters,
    int? readChapters,
    bool? isFavorite,
    List<String>? tags,
    ComicSourceType? sourceType,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastReadAt,
    DateTime? deletedAt,
    bool? isPrivate,
  }) {
    return ComicSeries(
      id: id ?? this.id,
      title: title ?? this.title,
      folderPath: folderPath ?? this.folderPath,
      coverPath: coverPath ?? this.coverPath,
      author: author ?? this.author,
      description: description ?? this.description,
      status: status ?? this.status,
      totalChapters: totalChapters ?? this.totalChapters,
      readChapters: readChapters ?? this.readChapters,
      isFavorite: isFavorite ?? this.isFavorite,
      tags: tags ?? this.tags,
      sourceType: sourceType ?? this.sourceType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      deletedAt: deletedAt ?? this.deletedAt,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }
}

enum SeriesStatus { ongoing, completed, hiatus }

enum ComicSourceType { folderSeries, singleFile, looseImages }
