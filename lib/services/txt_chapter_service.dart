import '../models/chapter.dart';
import '../models/chapter_edit.dart';

class TxtChapterService {
  /// 垃圾广告/推广信息正则
  static final List<RegExp> _spamPatterns = [
    // URL / 域名
    RegExp(r'.*(www\.|https?://|[a-zA-Z0-9_-]+\.(com|cn|net|org|cc|io|top|xyz|vip)).*'),
    // 爬虫站常用推广语
    RegExp(r'.*(本书由|本作品由|本小说由|本文档由|更多.*尽在|更多.*请访问|欢迎访问|欢迎登录|热门推荐).*'),
    RegExp(r'.*(关注.*公众号|关注.*微博|订阅.*号|扫码.*关注|扫描二维码|加入.*群|QQ群|微信群).*'),
    RegExp(r'.*(免费.*下载|免费.*阅读|全本.*下载|TXT下载|电子书.*下载).*'),
    RegExp(r'^(连载|首发|独家|原创).*网$'),
    RegExp(r'.*(小说阅读网|起点中文网|纵横中文网|晋江文学城|潇湘书院|红袖添香).*'),
    RegExp(r'.*(整理制作|整理上传|校对版|精校版|转码|排版|制作：|出品：|监制：).*'),
    RegExp(r'.*(copyright|all rights reserved|版权所有|未经许可|禁止转载).*', caseSensitive: false),
  ];

  /// 分章规则定义（id: 规则标识，name: 显示名称，pattern: 正则）
  static final List<_ChapterPattern> chapterPatternDefs = [
    _ChapterPattern(id: 'chinese_chapter', name: '第X章/回/节/卷', pattern: RegExp(r'^\s*第[\s\d一二三四五六七八九十百千万零]+[章回节卷]\s*', multiLine: true)),
    _ChapterPattern(id: 'chinese_chapter_colon', name: '第X章：标题', pattern: RegExp(r'^\s*第\s*\d+\s*[章回节卷][\s:：]+', multiLine: true)),
    _ChapterPattern(id: 'chinese_episode', name: '第X集/话/篇/番', pattern: RegExp(r'^\s*第\s*[\d一二三四五六七八九十百千万零]+\s*[集话篇番]\s*', multiLine: true)),
    _ChapterPattern(id: 'english_chapter', name: 'Chapter X / Act X', pattern: RegExp(r'^\s*(?:Chapter|Ch\.?|Act|Scene|Part)\s+\d+', multiLine: true, caseSensitive: false)),
    _ChapterPattern(id: 'english_chapter_title', name: 'Chapter X: Title', pattern: RegExp(r'^\s*Chapter\s+\d+\s*[:.\s]', multiLine: true, caseSensitive: false)),
    _ChapterPattern(id: 'numbered_title', name: 'X. 标题', pattern: RegExp(r'^\s*\d+[\.、\s]+[^\d\n]{2,30}\s*$', multiLine: true)),
    _ChapterPattern(id: 'zhengwen', name: '正文：标题', pattern: RegExp(r'^\s*正文[\s:：]+', multiLine: true)),
    _ChapterPattern(id: 'special_chapter', name: '楔子/序章/后记等', pattern: RegExp(r'^\s*(楔子|序章|前言|引言|后记|尾声|番外|终章|大结局)\s*$', multiLine: true)),
    _ChapterPattern(id: 'volume_book', name: '上卷/下卷/上册', pattern: RegExp(r'^\s*[上下中][卷册]\s*$', multiLine: true)),
    _ChapterPattern(id: 'volume_number', name: '卷X / 集X', pattern: RegExp(r'^\s*[卷集]\s*[\d一二三四五六七八九十]+\s*', multiLine: true)),
    _ChapterPattern(id: 'jjwxc', name: '☆★ 晋江格式', pattern: RegExp(r'^\s*[☆★✦✧][、\.\s]*.{1,50}\s*$', multiLine: true)),
  ];

  /// 豁免目录过滤的章节标题（前言/楔子等不应被误杀）
  static final List<RegExp> _exemptFromTocFilter = [
    RegExp(r'^\s*(楔子|序章|前言|引言|后记|尾声|番外|终章)\s*$'),
  ];

  /// 需要跳过的非章节标题关键词
  static final List<RegExp> _skipPatterns = [
    RegExp(r'^\s*版权|著作权|版权声明|版权页|图书在版编目|CIP数据|ISBN|书号|出版社|出版人|发行|印刷|经销|定价\s*$', caseSensitive: false),
    RegExp(r'^\s*封面|封底|腰封|书脊\s*$', caseSensitive: false),
    RegExp(r'^\s*目录|Contents|目次|章节目录\s*$', caseSensitive: false),
    RegExp(r'^\s*简介|介绍|内容提要|内容梗概|故事简介\s*$', caseSensitive: false),
    RegExp(r'^\s*前言|序言|译者序|译序|导读|总导读|作者介绍|译者介绍|编者的话|卷首语|发刊词|题记\s*$', caseSensitive: false),
    RegExp(r'^\s*出版说明|再版说明|译本序|译后记|编后记\s*$', caseSensitive: false),
    RegExp(r'^\s*致谢|献词|献辞|鸣谢\s*$', caseSensitive: false),
    RegExp(r'^\s*附录|附注|注释|注\s*$', caseSensitive: false),
    RegExp(r'^\s*参考文献|参考书目|引用书目|文献索引\s*$', caseSensitive: false),
    RegExp(r'^\s*策划|责任编辑|封面设计|装帧设计|排版|校对|转码|监制|营销|出品人\s*$', caseSensitive: false),
    RegExp(r'^\s*微信|微博|豆瓣|公众号|订阅号|二维码|官网|网站|网址|邮箱|邮件|电话\s*$', caseSensitive: false),
  ];

  static bool _isRealChapter(String title) {
    if (title.trim().isEmpty) return false;
    return !_skipPatterns.any((pattern) => pattern.hasMatch(title));
  }

  /// 文本预处理：去 trailing 空格、压缩空行、过滤垃圾广告
  static String preprocess(String content) {
    if (content.isEmpty) return content;

    var lines = content.split('\n');

    // 1. 去除每行 trailing 空格
    lines = lines.map((l) => l.trimRight()).toList();

    // 2. 压缩连续空行（最多保留 2 个）
    final compressed = <String>[];
    var emptyStreak = 0;
    for (final line in lines) {
      if (line.isEmpty) {
        emptyStreak++;
        if (emptyStreak <= 2) compressed.add('');
      } else {
        emptyStreak = 0;
        compressed.add(line);
      }
    }

    // 3. 过滤垃圾广告行
    final cleaned = compressed.where((line) {
      return !_spamPatterns.any((p) => p.hasMatch(line));
    }).toList();

    return cleaned.join('\n');
  }

  /// 检测内容是否像目录（大量单独的数字行、内容很短）
  static bool _isLikelyTableOfContents(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return true;
    // 内容很短，直接认为是目录
    // 内容很短才认为是目录（前言/楔子通常 100~500 字，不应被过滤）
    if (trimmed.length < 100) return true;

    final lines = trimmed.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 3) return true;

    // 检测是否有很多单独的数字行（页码）
    var digitOnlyLines = 0;
    for (final line in lines) {
      if (RegExp(r'^\s*\d+\s*$').hasMatch(line)) {
        digitOnlyLines++;
      }
    }
    // 如果超过30%的行是纯数字，认为是目录
    if (digitOnlyLines > lines.length * 0.3) return true;

    // 检测是否有大量短行（目录条目通常很短）
    var shortLines = 0;
    for (final line in lines) {
      if (line.trim().length < 20) shortLines++;
    }
    if (shortLines > lines.length * 0.75) return true;

    return false;
  }

  /// 检测标题是否像目录条目（末尾跟着页码数字）
  /// 白名单标题（楔子/序章等）即使有页码也不过滤
  static bool _isTocEntry(String title) {
    if (_exemptFromTocFilter.any((p) => p.hasMatch(title))) return false;
    return RegExp(r'\s+\d+\s*$').hasMatch(title);
  }

  /// 清理章节标题中的行尾页码和多余空格
  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'[ \t]+[\.…·]{2,}[ \t]*\d+[ \t]*$'), '')
        .replaceAll(RegExp(r'[ \t]+\d+[ \t]*$'), '')
        .trim();
  }

  /// 解析章节，可通过 [enabledRules] 指定启用的规则 ID 列表，null 表示全部启用
  static List<Chapter> parseChapters(String content, {List<String>? enabledRules}) {
    if (content.isEmpty) return [];

    final processed = preprocess(content);
    final chapters = <Chapter>[];
    final lines = processed.split('\n');

    // 构建启用的正则列表
    final activePatterns = enabledRules == null
        ? chapterPatternDefs.map((d) => d.pattern).toList()
        : chapterPatternDefs
            .where((d) => enabledRules.contains(d.id))
            .map((d) => d.pattern)
            .toList();

    // 先尝试用正则匹配章节标题
    final matches = <_ChapterMatch>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      for (final pattern in activePatterns) {
        if (pattern.hasMatch(line)) {
          matches.add(_ChapterMatch(index: i, title: _cleanTitle(line), pattern: pattern));
          break;
        }
      }
    }

    // 去重：相邻的相同标题只保留第一个（目录页和正文重复出现）
    final uniqueMatches = <_ChapterMatch>[];
    for (var i = 0; i < matches.length; i++) {
      if (i > 0 &&
          matches[i].title == matches[i - 1].title &&
          (matches[i].index - matches[i - 1].index) < 50) {
        continue;
      }
      uniqueMatches.add(matches[i]);
    }

    // 如果匹配到章节，按章节分割
    if (uniqueMatches.length >= 2) {
      for (var i = 0; i < uniqueMatches.length; i++) {
        final start = uniqueMatches[i].index;
        final end = i < uniqueMatches.length - 1 ? uniqueMatches[i + 1].index : lines.length;
        final chapterLines = lines.sublist(start, end);
        final chapterContent = chapterLines.skip(1).join('\n').trim();

        if (chapterContent.isNotEmpty) {
          chapters.add(Chapter(
            title: uniqueMatches[i].title,
            content: chapterContent,
            startIndex: start,
          ));
        }
      }
    }

    // 过滤非章节内容
    // 1. 跳过 _skipPatterns 匹配的标题
    // 2. 跳过像目录条目的标题（末尾有页码数字）
    // 3. 跳过像目录的章节（内容太短或全是数字页码）
    //    白名单标题（楔子/序章等）豁免内容长度过滤
    final filtered = chapters.where((c) {
      if (!_isRealChapter(c.title)) return false;
      if (_isTocEntry(c.title)) return false;
      if (_exemptFromTocFilter.any((p) => p.hasMatch(c.title))) return true;
      if (_isLikelyTableOfContents(c.content)) return false;
      return true;
    }).toList();

    // 回退策略：过滤后 ≥2 章用过滤结果；否则原始 ≥2 章用原始；否则兜底分割
    if (filtered.length >= 2) {
      return filtered;
    } else if (chapters.length >= 2) {
      return chapters;
    } else {
      return _splitByLength(content);
    }
  }

  static List<Chapter> _splitByLength(String content, {int charsPerChapter = 5000}) {
    final chapters = <Chapter>[];
    var start = 0;
    var chapterIndex = 1;

    while (start < content.length) {
      var end = start + charsPerChapter;
      if (end > content.length) end = content.length;

      // 尝试在段落边界分割
      if (end < content.length) {
        final nearestBreak = content.lastIndexOf('\n\n', end);
        if (nearestBreak > start + charsPerChapter * 0.8) {
          end = nearestBreak;
        }
      }

      final chapterContent = content.substring(start, end).trim();
      if (chapterContent.isNotEmpty) {
        chapters.add(Chapter(
          title: '第$chapterIndex章',
          content: chapterContent,
          startIndex: start,
        ));
        chapterIndex++;
      }

      start = end;
    }

    return chapters;
  }

  /// 应用章节编辑操作到解析后的章节列表。
  /// 按 [edits] 的**记录顺序**逐个应用，merge/split 会改变后续 edit 的索引上下文。
  static List<Chapter> applyEdits(List<Chapter> chapters, List<ChapterEdit> edits) {
    if (edits.isEmpty) return chapters;

    var result = chapters
        .map((c) => Chapter(
              title: c.title,
              content: c.content,
              startIndex: c.startIndex,
              startCharOffset: c.startCharOffset,
              endCharOffset: c.endCharOffset,
            ))
        .toList();

    for (final edit in edits) {
      switch (edit.type) {
        case 'rename':
          if (edit.chapterIndex >= 0 && edit.chapterIndex < result.length) {
            result[edit.chapterIndex] = Chapter(
              title: edit.newTitle ?? result[edit.chapterIndex].title,
              content: result[edit.chapterIndex].content,
              startIndex: result[edit.chapterIndex].startIndex,
            );
          }
        case 'merge':
          final endIndex = edit.mergeEndIndex ?? edit.chapterIndex + 1;
          if (edit.chapterIndex < 0 || edit.chapterIndex >= result.length) continue;
          if (endIndex <= edit.chapterIndex || endIndex >= result.length) continue;

          final mergedContent = result
              .sublist(edit.chapterIndex, endIndex + 1)
              .map((c) => c.content)
              .join('\n\n');

          result.replaceRange(edit.chapterIndex, endIndex + 1, [
            Chapter(
              title: edit.newTitle ?? result[edit.chapterIndex].title,
              content: mergedContent,
              startIndex: result[edit.chapterIndex].startIndex,
            ),
          ]);
        case 'split':
          final splitLine = edit.splitAtLine;
          if (edit.chapterIndex < 0 || edit.chapterIndex >= result.length) continue;
          if (splitLine == null || splitLine <= 0) continue;

          final chapter = result[edit.chapterIndex];
          final lines = chapter.content.split('\n');
          if (splitLine >= lines.length) continue;

          final firstContent = lines.sublist(0, splitLine).join('\n');
          final secondContent = lines.sublist(splitLine).join('\n');

          result.replaceRange(edit.chapterIndex, edit.chapterIndex + 1, [
            Chapter(
              title: chapter.title,
              content: firstContent,
              startIndex: chapter.startIndex,
            ),
            Chapter(
              title: edit.newTitle ?? '${chapter.title}（续）',
              content: secondContent,
              startIndex: chapter.startIndex + firstContent.length,
            ),
          ]);
      }
    }

    return result;
  }
}

class _ChapterPattern {
  final String id;
  final String name;
  final RegExp pattern;

  const _ChapterPattern({required this.id, required this.name, required this.pattern});
}

class _ChapterMatch {
  final int index;
  final String title;
  final RegExp pattern;

  _ChapterMatch({required this.index, required this.title, required this.pattern});
}
