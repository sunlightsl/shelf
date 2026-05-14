import 'dart:convert';
import 'chapter_edit.dart';

class BookParsingRule {
  final int itemId;
  final List<String>? enabledChapterRules;
  final int? textEncoding;
  final int? chineseConversion;
  final List<ChapterEdit>? chapterEdits;

  BookParsingRule({
    required this.itemId,
    this.enabledChapterRules,
    this.textEncoding,
    this.chineseConversion,
    this.chapterEdits,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'enabledChapterRules': enabledChapterRules?.join(','),
      'textEncoding': textEncoding,
      'chineseConversion': chineseConversion,
      'chapterEdits': chapterEdits != null ? jsonEncode(ChapterEdit.listToJson(chapterEdits!)) : null,
    };
  }

  factory BookParsingRule.fromMap(Map<String, dynamic> map) {
    final rulesStr = map['enabledChapterRules'] as String?;
    final editsStr = map['chapterEdits'] as String?;
    return BookParsingRule(
      itemId: map['itemId'] as int,
      enabledChapterRules: rulesStr != null && rulesStr.isNotEmpty
          ? rulesStr.split(',')
          : null,
      textEncoding: map['textEncoding'] as int?,
      chineseConversion: map['chineseConversion'] as int?,
      chapterEdits: editsStr != null && editsStr.isNotEmpty
          ? ChapterEdit.listFromJson(jsonDecode(editsStr) as List<dynamic>)
          : null,
    );
  }
}
