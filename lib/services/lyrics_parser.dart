class LyricLine {
  final Duration time;
  final String text;

  LyricLine({required this.time, required this.text});
}

class LyricsParser {
  /// 解析 LRC 格式歌词
  static List<LyricLine> parse(String content) {
    final lines = <LyricLine>[];
    final lineRegex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)');

    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final matches = lineRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final text = matches.last.group(4)!.trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final min = int.tryParse(match.group(1)!) ?? 0;
        final sec = int.tryParse(match.group(2)!) ?? 0;
        final msStr = match.group(3);
        final ms = msStr != null
            ? (msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr))
            : 0;

        lines.add(LyricLine(
          time: Duration(minutes: min, seconds: sec, milliseconds: ms),
          text: text,
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 根据当前时间获取当前歌词行索引
  static int getCurrentLineIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;

    int left = 0;
    int right = lines.length - 1;

    while (left < right) {
      final mid = (left + right + 1) ~/ 2;
      if (lines[mid].time <= position) {
        left = mid;
      } else {
        right = mid - 1;
      }
    }

    return left;
  }
}
