class Chapter {
  final String title;
  String? _content;
  final int startIndex;

  /// 大文件懒加载：字符在全文中的起止偏移
  final int? startCharOffset;
  final int? endCharOffset;

  Chapter({
    required this.title,
    String? content,
    required this.startIndex,
    this.startCharOffset,
    this.endCharOffset,
  }) : _content = content;

  String get content => _content ?? '';
  set content(String value) => _content = value;
  bool get isLoaded => _content != null && _content!.isNotEmpty;

  /// 从全文提取本章内容（大文件懒加载模式）
  void loadFrom(String fullText) {
    if (startCharOffset != null && endCharOffset != null) {
      _content = fullText.substring(startCharOffset!, endCharOffset!);
    }
  }

  void unload() {
    _content = null;
  }
}
