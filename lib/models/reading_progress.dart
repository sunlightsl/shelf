class ReadingProgress {
  final int? id;
  final int itemId;
  int position;
  String positionText;
  double percentage;
  DateTime lastReadAt;
  String? deviceId;
  int chapterIndex;       // 当前章节索引 (-1 表示未使用)
  double chapterOffset;   // 章节内进度 0.0~1.0 (-1.0 表示未使用)

  ReadingProgress({
    this.id,
    required this.itemId,
    required this.position,
    required this.positionText,
    required this.percentage,
    required this.lastReadAt,
    this.deviceId,
    this.chapterIndex = -1,
    this.chapterOffset = -1.0,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'itemId': itemId,
      'position': position,
      'positionText': positionText,
      'percentage': percentage,
      'lastReadAt': lastReadAt.toIso8601String(),
      'chapterIndex': chapterIndex,
      'chapterOffset': chapterOffset,
    };
    if (id != null) map['id'] = id;
    if (deviceId != null) map['deviceId'] = deviceId;
    return map;
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    return ReadingProgress(
      id: map['id'] as int?,
      itemId: map['itemId'] as int,
      position: map['position'] as int,
      positionText: map['positionText'] as String,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: DateTime.parse(map['lastReadAt'] as String),
      deviceId: map['deviceId'] as String?,
      chapterIndex: (map['chapterIndex'] as num?)?.toInt() ?? -1,
      chapterOffset: (map['chapterOffset'] as num?)?.toDouble() ?? -1.0,
    );
  }

  ReadingProgress copyWith({
    int? id,
    int? itemId,
    int? position,
    String? positionText,
    double? percentage,
    DateTime? lastReadAt,
    String? deviceId,
    int? chapterIndex,
    double? chapterOffset,
  }) {
    return ReadingProgress(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      position: position ?? this.position,
      positionText: positionText ?? this.positionText,
      percentage: percentage ?? this.percentage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      deviceId: deviceId ?? this.deviceId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterOffset: chapterOffset ?? this.chapterOffset,
    );
  }
}
