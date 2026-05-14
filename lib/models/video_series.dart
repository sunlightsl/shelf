class VideoSeries {
  final int? id;
  final String title;
  final String? folderPath;
  String? coverPath;
  final String? description;
  final int totalEpisodes;
  final int watchedEpisodes;
  bool isFavorite;
  final DateTime createdAt;
  DateTime? updatedAt;
  DateTime? lastWatchedAt;
  bool isPrivate;

  VideoSeries({
    this.id,
    required this.title,
    this.folderPath,
    this.coverPath,
    this.description,
    this.totalEpisodes = 0,
    this.watchedEpisodes = 0,
    this.isFavorite = false,
    DateTime? createdAt,
    this.updatedAt,
    this.lastWatchedAt,
    this.isPrivate = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'folderPath': folderPath,
      'coverPath': coverPath,
      'description': description,
      'totalEpisodes': totalEpisodes,
      'watchedEpisodes': watchedEpisodes,
      'isFavorite': isFavorite ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
      'updatedAt': updatedAt != null ? updatedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'lastWatchedAt': lastWatchedAt != null ? lastWatchedAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'isPrivate': isPrivate ? 1 : 0,
    };
  }

  factory VideoSeries.fromMap(Map<String, dynamic> map) {
    return VideoSeries(
      id: map['id'] as int?,
      title: map['title'] as String,
      folderPath: map['folderPath'] as String?,
      coverPath: map['coverPath'] as String?,
      description: map['description'] as String?,
      totalEpisodes: map['totalEpisodes'] as int? ?? 0,
      watchedEpisodes: map['watchedEpisodes'] as int? ?? 0,
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as int) * 1000)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['updatedAt'] as int) * 1000)
          : null,
      lastWatchedAt: map['lastWatchedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['lastWatchedAt'] as int) * 1000)
          : null,
      isPrivate: (map['isPrivate'] as int? ?? 0) == 1,
    );
  }

  VideoSeries copyWith({
    int? id,
    String? title,
    String? folderPath,
    String? coverPath,
    String? description,
    int? totalEpisodes,
    int? watchedEpisodes,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastWatchedAt,
    bool? isPrivate,
  }) {
    return VideoSeries(
      id: id ?? this.id,
      title: title ?? this.title,
      folderPath: folderPath ?? this.folderPath,
      coverPath: coverPath ?? this.coverPath,
      description: description ?? this.description,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastWatchedAt: lastWatchedAt ?? this.lastWatchedAt,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }
}
