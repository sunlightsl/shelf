import 'package:flutter/material.dart';

class TextPage {
  final String text;
  final bool isChapterStart;
  final String? chapterTitle;

  const TextPage({
    required this.text,
    this.isChapterStart = false,
    this.chapterTitle,
  });
}

class TextPaginator {
  /// Split text into pages that fit within the given dimensions using TextPainter.
  static List<TextPage> paginate({
    required String text,
    required double width,
    required double height,
    required TextStyle style,
    double lineHeight = 1.8,
    double paragraphSpacing = 0,
    double firstLineIndent = 0,
    String? chapterTitle,
    TextStyle? titleStyle,
    double titleTopPadding = 24,
    double titleBottomPadding = 16,
  }) {
    if (text.isEmpty) return [];

    final pages = <TextPage>[];
    final paragraphs = text.split('\n');
    final effectiveStyle = style.copyWith(height: lineHeight);

    // Build indent string using full-width spaces
    final indentCount = firstLineIndent.round();
    final indentStr = indentCount > 0 ? '　' * indentCount : '';

    // Available height for text content
    double availableHeight = height;

    // Reserve space for chapter title on first page if present
    double titleHeight = 0;
    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      final effectiveTitleStyle = titleStyle ?? effectiveStyle.copyWith(
        fontSize: (effectiveStyle.fontSize ?? 18) + 4,
        fontWeight: FontWeight.bold,
        height: 1.4,
      );
      final titlePainter = TextPainter(
        text: TextSpan(text: chapterTitle, style: effectiveTitleStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      titlePainter.layout(maxWidth: width);
      titleHeight = titleTopPadding + titlePainter.height + titleBottomPadding;
      titlePainter.dispose();
    }

    int currentParagraph = 0;
    int currentChar = 0;
    bool isFirstPage = true;

    final paragraphPainter = TextPainter(textDirection: TextDirection.ltr);

    while (currentParagraph < paragraphs.length) {
      final pageText = StringBuffer();
      double usedHeight = isFirstPage && chapterTitle != null ? titleHeight : 0;
      bool pageHasContent = false;
      bool isChapterStartPage = isFirstPage && chapterTitle != null;

      while (currentParagraph < paragraphs.length) {
        final para = paragraphs[currentParagraph];
        var paraText = currentChar > 0 ? para.substring(currentChar) : para;

        if (paraText.isEmpty) {
          currentParagraph++;
          currentChar = 0;
          continue;
        }

        // Apply first-line indent for new paragraphs
        final isNewParagraph = currentChar == 0;
        final displayText = isNewParagraph && indentStr.isNotEmpty ? indentStr + paraText : paraText;

        // Measure the paragraph
        paragraphPainter.text = TextSpan(text: displayText, style: effectiveStyle);
        paragraphPainter.layout(maxWidth: width);
        final painterHeight = paragraphPainter.height;

        final spacing = pageHasContent && paragraphSpacing > 0 ? paragraphSpacing : 0;

        // Check if entire paragraph fits
        if (usedHeight + painterHeight + spacing <= availableHeight) {
          if (spacing > 0) usedHeight += spacing;
          if (pageText.isNotEmpty) pageText.write('\n');
          pageText.write(displayText);
          usedHeight += painterHeight;
          pageHasContent = true;
          currentParagraph++;
          currentChar = 0;
        } else {
          // Paragraph doesn't fit — try to split it to fill remaining space
          final remainingHeight = availableHeight - usedHeight - spacing;

          if (remainingHeight > 0) {
            var (fitted, remaining) = _splitParagraph(
              displayText,
              width,
              remainingHeight,
              effectiveStyle,
            );
            if (fitted.isEmpty && remaining.isNotEmpty) {
              // Force at least one character so the paragraph isn't lost
              fitted = remaining.substring(0, 1);
              remaining = remaining.substring(1);
            }
            if (fitted.isNotEmpty) {
              if (pageText.isNotEmpty) pageText.write('\n');
              pageText.write(fitted);
              pageHasContent = true;
              usedHeight += spacing + painterHeight; // approximate
            }
            if (remaining.isNotEmpty) {
              // Continue with remaining text in next iteration
              // Remove indent from remaining text for correct char calculation
              final remainingRaw = remaining.startsWith(indentStr)
                  ? remaining.substring(indentStr.length)
                  : remaining;
              currentChar = para.length - remainingRaw.length;
              break;
            } else {
              currentParagraph++;
              currentChar = 0;
              break;
            }
          } else {
            // No space at all, start new page
            break;
          }
        }
      }

      if (pageHasContent) {
        pages.add(TextPage(
          text: pageText.toString(),
          isChapterStart: isChapterStartPage,
          chapterTitle: isChapterStartPage ? chapterTitle : null,
        ));
        isFirstPage = false;
      } else {
        // Avoid infinite loop
        currentParagraph++;
        currentChar = 0;
        isFirstPage = false;
      }
    }

    paragraphPainter.dispose();

    if (pages.isEmpty && text.isNotEmpty) {
      pages.add(TextPage(text: text));
    }

    return pages;
  }

  /// Split a single paragraph to fit within remaining height.
  static (String fitted, String remaining) _splitParagraph(
    String text,
    double width,
    double maxHeight,
    TextStyle style,
  ) {
    int low = 0;
    int high = text.length;
    int best = 0;

    final painter = TextPainter(textDirection: TextDirection.ltr);

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final substring = text.substring(0, mid);
      painter.text = TextSpan(text: substring, style: style);
      painter.layout(maxWidth: width);
      final painterHeight = painter.height;

      if (painterHeight <= maxHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    painter.dispose();

    // Try to find a better break point (don't break in the middle of a word if possible)
    if (best < text.length && best > 0) {
      // Look for a space or punctuation to break at
      int breakPoint = best;
      while (breakPoint > 0 && breakPoint > best - 10) {
        if (text[breakPoint - 1] == ' ' ||
            text[breakPoint - 1] == '，' ||
            text[breakPoint - 1] == '。' ||
            text[breakPoint - 1] == '！' ||
            text[breakPoint - 1] == '？' ||
            text[breakPoint - 1] == '；' ||
            text[breakPoint - 1] == '：' ||
            text[breakPoint - 1] == '、' ||
            text[breakPoint - 1] == '.' ||
            text[breakPoint - 1] == ',' ||
            text[breakPoint - 1] == '!' ||
            text[breakPoint - 1] == '?') {
          break;
        }
        breakPoint--;
      }
      if (breakPoint > 0) {
        best = breakPoint;
      }
    }

    return (text.substring(0, best), text.substring(best));
  }
}
