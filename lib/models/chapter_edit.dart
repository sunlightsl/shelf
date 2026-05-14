/// 章节编辑操作记录
class ChapterEdit {
  final String type; // rename | merge | split
  final int chapterIndex;
  final String? newTitle;
  final int? mergeEndIndex;
  final int? splitAtLine;

  ChapterEdit({
    required this.type,
    required this.chapterIndex,
    this.newTitle,
    this.mergeEndIndex,
    this.splitAtLine,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'chapterIndex': chapterIndex,
      if (newTitle != null) 'newTitle': newTitle,
      if (mergeEndIndex != null) 'mergeEndIndex': mergeEndIndex,
      if (splitAtLine != null) 'splitAtLine': splitAtLine,
    };
  }

  factory ChapterEdit.fromMap(Map<String, dynamic> map) {
    return ChapterEdit(
      type: map['type'] as String,
      chapterIndex: map['chapterIndex'] as int,
      newTitle: map['newTitle'] as String?,
      mergeEndIndex: map['mergeEndIndex'] as int?,
      splitAtLine: map['splitAtLine'] as int?,
    );
  }

  static List<ChapterEdit> listFromJson(List<dynamic> json) {
    return json.map((e) => ChapterEdit.fromMap(e as Map<String, dynamic>)).toList();
  }

  static List<Map<String, dynamic>> listToJson(List<ChapterEdit> edits) {
    return edits.map((e) => e.toMap()).toList();
  }
}
