import 'dart:io';
import 'package:epubx/epubx.dart';

class EpubChapterData {
  final String title;
  final String content;

  EpubChapterData({required this.title, required this.content});
}

class EpubService {
  /// 非章节内容的关键词（用于过滤）
  static final List<RegExp> _skipPatterns = [
    RegExp(r'版权|著作权|版权声明|版权页', caseSensitive: false),
    RegExp(r'^\s*目录\s*$|contents|table\s+of\s+contents|toc', caseSensitive: false),
    RegExp(r'^\s*封面\s*$|cover\s+page', caseSensitive: false),
    RegExp(r'^\s*简介\s*$|^\s*介绍\s*$|about\s+this\s+book|synopsis', caseSensitive: false),
    RegExp(r'^\s*前言\s*$|^\s*序言\s*$|preface|foreword|prologue', caseSensitive: false),
    RegExp(r'^\s*后记\s*$|epilogue|afterword', caseSensitive: false),
    RegExp(r'^\s*致谢\s*$|acknowledgements|acknowledgments', caseSensitive: false),
    RegExp(r'^\s*附录\s*$|appendix', caseSensitive: false),
    RegExp(r'^\s*参考文献\s*$|bibliography|references', caseSensitive: false),
    RegExp(r'^\s*献词\s*$|dedication', caseSensitive: false),
    RegExp(r'^\s*译者序\s*$|^\s*译序\s*$|^\s*导读\s*$', caseSensitive: false),
    RegExp(r'^\s*出版说明\s*$|^\s*再版说明\s*$', caseSensitive: false),
  ];

  static bool _isRealChapter(String title) {
    if (title.trim().isEmpty) return false;
    final lowerTitle = title.toLowerCase();
    return !_skipPatterns.any((pattern) => pattern.hasMatch(lowerTitle));
  }

  static Future<List<EpubChapterData>> parseChapters(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final epub = await EpubReader.readBook(bytes);

    final rawChapters = <EpubChapterData>[];

    // 1. 尝试 NCX 目录解析
    void extractChapters(List<EpubChapter>? chapterList, {String prefix = ''}) {
      if (chapterList == null) return;
      for (var i = 0; i < chapterList.length; i++) {
        final chapter = chapterList[i];
        final title = prefix.isEmpty
            ? (chapter.Title ?? '第 ${i + 1} 章')
            : '$prefix - ${chapter.Title ?? '第 ${i + 1} 节'}';

        final content = _htmlToPlainText(chapter.HtmlContent);
        if (content.isNotEmpty) {
          rawChapters.add(EpubChapterData(title: title, content: content));
        }

        if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
          extractChapters(chapter.SubChapters, prefix: title);
        }
      }
    }

    extractChapters(epub.Chapters);

    // 2. 如果 NCX 为空，尝试按 Spine 阅读顺序解析
    if (rawChapters.isEmpty) {
      final spineItems = epub.Schema?.Package?.Spine?.Items;
      final manifest = epub.Schema?.Package?.Manifest;
      final htmlMap = epub.Content?.Html;

      if (spineItems != null && manifest != null && htmlMap != null) {
        final manifestItems = {for (var item in manifest.Items!) item.Id: item};

        for (var i = 0; i < spineItems.length; i++) {
          final idRef = spineItems[i].IdRef;
          final manifestItem = manifestItems[idRef];
          if (manifestItem == null) continue;

          final href = manifestItem.Href;
          if (href == null) continue;

          EpubTextContentFile? htmlFile;
          if (htmlMap.containsKey(href)) {
            htmlFile = htmlMap[href];
          } else {
            final fileName = href.split('/').last;
            for (final entry in htmlMap.entries) {
              if (entry.key.split('/').last == fileName) {
                htmlFile = entry.value;
                break;
              }
            }
          }

          if (htmlFile != null) {
            final content = _htmlToPlainText(htmlFile.Content);
            if (content.isNotEmpty) {
              rawChapters.add(EpubChapterData(
                title: '第 ${i + 1} 章',
                content: content,
              ));
            }
          }
        }
      }
    }

    // 3. 最后兜底：直接遍历所有 HTML 文件
    if (rawChapters.isEmpty && epub.Content?.Html != null) {
      final htmlFiles = epub.Content!.Html!.values.toList();
      for (var i = 0; i < htmlFiles.length; i++) {
        final content = _htmlToPlainText(htmlFiles[i].Content);
        if (content.isNotEmpty) {
          rawChapters.add(EpubChapterData(
            title: '第 ${i + 1} 章',
            content: content,
          ));
        }
      }
    }

    // 4. 过滤非章节内容
    final filtered = rawChapters.where((c) => _isRealChapter(c.title)).toList();
    // 如果过滤后章节太少（少于2个），保留原始结果避免误判
    return filtered.length >= 2 ? filtered : rawChapters;
  }

  static String _htmlToPlainText(String? html) {
    if (html == null || html.isEmpty) return '';

    var text = html
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        );

    // 将 <img> 标签转换为占位符，避免图片信息完全丢失
    text = text.replaceAllMapped(
      RegExp(r'<img[^>]*>', caseSensitive: false),
      (match) {
        final tag = match.group(0) ?? '';
        final altMatch = RegExp('alt=["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag);
        final alt = altMatch?.group(1);
        if (alt != null && alt.isNotEmpty) {
          return '[图片: $alt]';
        }
        final srcMatch = RegExp('src=["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag);
        final src = srcMatch?.group(1);
        if (src != null && src.isNotEmpty) {
          final fileName = src.split('/').last.split('\\').last;
          return '[图片: $fileName]';
        }
        return '[图片]';
      },
    );

    // 块级标签替换为换行
    text = text
        .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li|tr|blockquote)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n---\n');

    // 移除所有剩余标签（保留标签内文本）
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // 解码常见 HTML 实体
    const entities = {
      '&nbsp;': ' ',
      '&lt;': '<',
      '&gt;': '>',
      '&amp;': '&',
      '&quot;': '"',
      '&apos;': "'",
      '&#160;': ' ',
      '&#xA0;': ' ',
      '&#8212;': '—',
      '&#8211;': '–',
      '&#8220;': '"',
      '&#8221;': '"',
      '&#8230;': '…',
      '&hellip;': '…',
      '&mdash;': '—',
      '&ndash;': '–',
      '&ldquo;': '"',
      '&rdquo;': '"',
      '&lsquo;': ''',
      '&rsquo;': ''',
    };

    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    // 统一换行符并压缩多余空白
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    while (text.contains('\n\n\n')) {
      text = text.replaceAll('\n\n\n', '\n\n');
    }

    return text.trim();
  }
}
