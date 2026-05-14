class ComicReadingProgress {
  final int? id;
  final int seriesId;
  final int? chapterId;
  final int currentPage;
  final int totalPages;
  final double percentage;
  final DateTime lastReadAt;

  ComicReadingProgress({
    this.id,
    required this.seriesId,
    this.chapterId,
    this.currentPage = 0,
    this.totalPages = 0,
    this.percentage = 0.0,
    DateTime? lastReadAt,
  }) : lastReadAt = lastReadAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'seriesId': seriesId,
      'chapterId': chapterId,
      'currentPage': currentPage,
      'totalPages': totalPages,
      'percentage': percentage,
      'lastReadAt': lastReadAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory ComicReadingProgress.fromMap(Map<String, dynamic> map) {
    return ComicReadingProgress(
      id: map['id'] as int?,
      seriesId: map['seriesId'] as int,
      chapterId: map['chapterId'] as int?,
      currentPage: map['currentPage'] as int? ?? 0,
      totalPages: map['totalPages'] as int? ?? 0,
      percentage: map['percentage'] as double? ?? 0.0,
      lastReadAt: map['lastReadAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['lastReadAt'] as int) * 1000)
          : DateTime.now(),
    );
  }

  ComicReadingProgress copyWith({
    int? id,
    int? seriesId,
    int? chapterId,
    int? currentPage,
    int? totalPages,
    double? percentage,
    DateTime? lastReadAt,
  }) {
    return ComicReadingProgress(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      chapterId: chapterId ?? this.chapterId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      percentage: percentage ?? this.percentage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }
}
