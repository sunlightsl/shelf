class VideoEpisode {
  final int? id;
  final int seriesId;
  final String title;
  final String filePath;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? fileSize;
  final Duration? duration;
  final Duration? position;
  final double? percentage;
  bool isWatched;
  final DateTime createdAt;

  VideoEpisode({
    this.id,
    required this.seriesId,
    required this.title,
    required this.filePath,
    this.seasonNumber,
    this.episodeNumber,
    this.fileSize,
    this.duration,
    this.position,
    this.percentage,
    this.isWatched = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'seriesId': seriesId,
      'title': title,
      'filePath': filePath,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'fileSize': fileSize,
      'duration': duration?.inSeconds,
      'position': position?.inSeconds,
      'percentage': percentage,
      'isWatched': isWatched ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory VideoEpisode.fromMap(Map<String, dynamic> map) {
    return VideoEpisode(
      id: map['id'] as int?,
      seriesId: map['seriesId'] as int,
      title: map['title'] as String,
      filePath: map['filePath'] as String,
      seasonNumber: map['seasonNumber'] as int?,
      episodeNumber: map['episodeNumber'] as int?,
      fileSize: map['fileSize'] as int?,
      duration: map['duration'] != null
          ? Duration(seconds: map['duration'] as int)
          : null,
      position: map['position'] != null
          ? Duration(seconds: map['position'] as int)
          : null,
      percentage: map['percentage'] as double?,
      isWatched: (map['isWatched'] as int? ?? 0) == 1,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as int) * 1000)
          : DateTime.now(),
    );
  }

  String get displayLabel {
    if (seasonNumber != null && episodeNumber != null) {
      return 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
    }
    if (episodeNumber != null) {
      return '第 $episodeNumber 集';
    }
    return title;
  }
}
