class Bookmark {
  final int? id;
  final int itemId;
  final int position;
  final String positionText;
  final String? note;
  final DateTime createdAt;

  Bookmark({
    this.id,
    required this.itemId,
    required this.position,
    required this.positionText,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemId': itemId,
      'position': position,
      'positionText': positionText,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as int?,
      itemId: map['itemId'] as int,
      position: map['position'] as int,
      positionText: map['positionText'] as String,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Bookmark copyWith({
    int? id,
    int? itemId,
    int? position,
    String? positionText,
    String? note,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      position: position ?? this.position,
      positionText: positionText ?? this.positionText,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
