import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:ui';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_render/pdf_render.dart';
import 'package:pdf_render/pdf_render_widgets.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:provider/provider.dart';
import '../../models/library_item.dart';
import '../../providers/library_provider.dart';
import '../../models/reading_progress.dart';
import '../../models/bookmark.dart';
import '../../models/chapter.dart';
import '../../models/chapter_edit.dart';
import '../../models/book_parsing_rule.dart';
import '../../database/library_dao.dart';
import '../../database/book_parsing_rule_dao.dart';
import '../../services/epub_service.dart';
import '../../services/txt_chapter_service.dart';
import '../../services/reading_settings_service.dart';
import '../../services/text_paginator.dart';
import '../../utils/chinese_converter.dart';

enum _BottomPanel { none, chapters, bookmarks, progress, brightness, settings }

class _SearchResultItem {
  final int chapterIndex;
  final String chapterTitle;
  final int offsetInChapter;
  final String snippet;

  _SearchResultItem({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.offsetInChapter,
    required this.snippet,
  });
}

class NovelReaderScreen extends StatefulWidget {
  final LibraryItem item;

  const NovelReaderScreen({super.key, required this.item});

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  final LibraryDao _dao = LibraryDao();
  final BookParsingRuleDao _bookRuleDao = BookParsingRuleDao();

  // 通用状态
  bool _isLoading = true;
  String _loadingMessage = '';
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier(false);

  // 正文样式
  double _fontSize = 18;
  double _lineHeight = 1.8;
  double _paragraphSpacing = 0;
  double _horizontalPadding = 24;
  double _letterSpacing = 0.3;
  FontWeight _fontWeight = FontWeight.w400;
  String _fontFamily = '';
  double _firstLineIndent = 2.0;

  // 标题样式
  double _titleFontSize = 22;
  double _titleTopPadding = 32;
  double _titleBottomPadding = 24;
  String _titleFontFamily = '';

  // 设置面板展开状态 (1=标题, 2=正文, 3=翻页, 4=更多)
  int _settingsExpandedGroup = 1;

  // TXT 编码设置
  TextEncoding _textEncoding = TextEncoding.auto;

  // 启用的分章规则 ID 列表（null 表示全部启用）
  List<String>? _enabledChapterRules;

  // 繁简转换
  ChineseConversion _chineseConversion = ChineseConversion.none;

  // 章节编辑操作记录
  List<ChapterEdit> _chapterEdits = [];

  // 底部弹出面板状态
  final ValueNotifier<_BottomPanel> _expandedPanelNotifier = ValueNotifier(_BottomPanel.none);

  // 进度面板的滑动值缓存
  double? _progressSliderValue;

  // 搜索功能由 _showSearchSheet 内部管理状态

  // 主题与布局
  ReadingTheme _readingTheme = ReadingTheme.light;
  bool _isHorizontal = false;
  double _brightness = 1.0;

  // TXT 状态
  String _txtContent = '';
  List<Chapter> _txtChapters = [];
  int _txtCurrentChapter = 0;
  PageController? _txtPageController;
  ScrollController? _txtScrollController;
  bool _txtNeedsPagination = true;
  Size? _txtViewSize;
  // 方案A：全局页面列表（横向翻页）
  List<TextPage> _txtAllPages = [];
  List<int> _txtChapterPageOffsets = [];
  Set<int> _txtPaginatedChapters = {};
  bool _txtIsPaginating = false;
  int _txtGlobalPageIndex = 0;
  double _restoredChapterOffset = -1.0; // 恢复进度时暂存的章节内偏移

  // EPUB 状态
  List<EpubChapterData> _epubChapters = [];
  int _epubCurrentChapter = 0;
  PageController? _epubPageController;
  ScrollController? _epubScrollController;
  bool _epubNeedsPagination = true;
  Size? _epubViewSize;
  // 方案A：全局页面列表（横向翻页）
  List<TextPage> _epubAllPages = [];
  List<int> _epubChapterPageOffsets = [];
  Set<int> _epubPaginatedChapters = {};
  bool _epubIsPaginating = false;
  int _epubGlobalPageIndex = 0;

  // PDF 状态
  int _pdfPage = 0;
  int _pdfTotalPages = 0;
  Future<PdfDocument>? _pdfDocFuture;
  final ScrollController _pdfScrollController = ScrollController();
  final PageController _pdfPageController = PageController();

  // MOBI / AZW3 状态
  String _mobiContent = '';

  // 横向翻页页码
  final ValueNotifier<int> _horizontalCurrentPageNotifier = ValueNotifier<int>(1);
  final ValueNotifier<int> _horizontalTotalPagesNotifier = ValueNotifier<int>(1);

  // 亮度 / 进度滑块（局部刷新，避免重建整个面板）
  late final ValueNotifier<double> _brightnessNotifier;
  late final ValueNotifier<double?> _progressSliderNotifier;

  // 书签
  List<Bookmark> _bookmarks = [];

  Color get _bgColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFFF5F5F7);
    if (global == AppThemeMode.dark) return const Color(0xFF1C1C1E);
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return const Color(0xFF1C1C1E);
      case ReadingTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReadingTheme.eyeCare:
        return const Color(0xFFE8F5E9);
      case ReadingTheme.light:
        return const Color(0xFFF5F5F7);
    }
  }

  Color get _textColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFF1D1D1F);
    if (global == AppThemeMode.dark) return const Color(0xFFE5E5EA);
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return const Color(0xFFE5E5EA);
      case ReadingTheme.sepia:
        return const Color(0xFF5B4636);
      case ReadingTheme.eyeCare:
        return const Color(0xFF2E4A2E);
      case ReadingTheme.light:
        return const Color(0xFF1D1D1F);
    }
  }

  Color get _controlBarColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFFF5F5F7);
    if (global == AppThemeMode.dark) return const Color(0xFF1C1C1E);
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return const Color(0xFF1C1C1E);
      case ReadingTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReadingTheme.eyeCare:
        return const Color(0xFFE8F5E9);
      case ReadingTheme.light:
        return const Color(0xFFF5F5F7);
    }
  }

  TextStyle get _baseTextStyle {
    return TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      color: _textColor,
      letterSpacing: _letterSpacing,
      fontWeight: _fontWeight,
      fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
    );
  }

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _txtScrollController = ScrollController();
    _txtScrollController!.addListener(_hideControlsOnScroll);
    _epubScrollController = ScrollController();
    _epubScrollController!.addListener(_hideControlsOnScroll);
    _pdfScrollController.addListener(_hideControlsOnScroll);
    _brightnessNotifier = ValueNotifier<double>(_brightness);
    _progressSliderNotifier = ValueNotifier<double?>(null);
    _loadSettings();
    _initializeReader();
  }

  Future<void> _loadSettings() async {
    final service = ReadingSettingsService.instance;
    await service.load();
    if (!mounted) return;

    // 加载全局默认设置
    setState(() {
      _fontSize = service.settings.fontSize;
      _lineHeight = service.settings.lineHeight;
      _paragraphSpacing = service.settings.paragraphSpacing;
      _horizontalPadding = service.settings.horizontalPadding;
      _letterSpacing = service.settings.letterSpacing;
      _fontWeight = service.settings.fontWeight;
      _readingTheme = service.settings.theme;
      _brightness = service.settings.brightness;
      _brightnessNotifier.value = _brightness;
      _isHorizontal = service.settings.isHorizontal;
      _fontFamily = service.settings.fontFamily;
      _firstLineIndent = service.settings.firstLineIndent;
      _titleFontSize = service.settings.titleFontSize;
      _titleTopPadding = service.settings.titleTopPadding;
      _titleBottomPadding = service.settings.titleBottomPadding;
      _titleFontFamily = service.settings.titleFontFamily;
      _textEncoding = service.settings.textEncoding;
      _enabledChapterRules = service.settings.enabledChapterRules;
      _chineseConversion = service.settings.chineseConversion;
    });

    // 尝试加载本书专属规则（覆盖全局设置）
    final bookRule = await _bookRuleDao.getByItemId(widget.item.id!);
    if (bookRule != null && mounted) {
      setState(() {
        if (bookRule.enabledChapterRules != null) {
          _enabledChapterRules = bookRule.enabledChapterRules;
        }
        if (bookRule.textEncoding != null) {
          final encodingIdx = bookRule.textEncoding!.clamp(0, TextEncoding.values.length - 1);
          _textEncoding = TextEncoding.values[encodingIdx];
        }
        if (bookRule.chineseConversion != null) {
          final convIdx = bookRule.chineseConversion!.clamp(0, ChineseConversion.values.length - 1);
          _chineseConversion = ChineseConversion.values[convIdx];
        }
        if (bookRule.chapterEdits != null) {
          _chapterEdits = bookRule.chapterEdits!;
        }
      });
    }

    _updateSystemUIOverlayStyle();
  }

  void _updateSystemUIOverlayStyle() {
    final bool isDark = _readingTheme == ReadingTheme.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  Future<void> _saveSettings() async {
    _txtNeedsPagination = true;
    _epubNeedsPagination = true;
    await ReadingSettingsService.instance.save(ReadingSettings(
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      horizontalPadding: _horizontalPadding,
      letterSpacing: _letterSpacing,
      fontWeight: _fontWeight,
      theme: _readingTheme,
      brightness: _brightness,
      isHorizontal: _isHorizontal,
      fontFamily: _fontFamily,
      firstLineIndent: _firstLineIndent,
      titleFontSize: _titleFontSize,
      titleTopPadding: _titleTopPadding,
      titleBottomPadding: _titleBottomPadding,
      titleFontFamily: _titleFontFamily,
      textEncoding: _textEncoding,
      enabledChapterRules: _enabledChapterRules,
      chineseConversion: _chineseConversion,
    ));
    // 保存本书专属解析规则
    if (widget.item.id != null) {
      await _bookRuleDao.save(BookParsingRule(
        itemId: widget.item.id!,
        enabledChapterRules: _enabledChapterRules,
        textEncoding: _textEncoding.index,
        chineseConversion: _chineseConversion.index,
        chapterEdits: _chapterEdits.isNotEmpty ? _chapterEdits : null,
      ));
    }
  }

  Future<void> _initializeReader() async {
    switch (widget.item.format) {
      case FileFormat.txt:
        await _loadTxtContent();
        break;
      case FileFormat.epub:
        await _loadEpubContent();
        break;
      case FileFormat.pdf:
        _pdfDocFuture = PdfDocument.openFile(widget.item.filePath);
        await _loadPdfContent();
        break;
      case FileFormat.mobi:
      case FileFormat.azw3:
        await _loadMobiContent();
        break;
      default:
        if (mounted) setState(() => _isLoading = false);
    }
    await _restoreProgress();
    await _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    if (widget.item.id == null) return;
    final bookmarks = await _dao.getBookmarksByItem(widget.item.id!);
    if (!mounted) return;
    setState(() => _bookmarks = bookmarks);
  }

  (int, String) _getCurrentPosition() {
    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          if (_isHorizontal) {
            final page = _txtGlobalPageIndex;
            return (_txtCurrentChapter, '第 ${_txtCurrentChapter + 1}章 第 ${page + 1}页');
          }
          return (_txtCurrentChapter, '第 ${_txtCurrentChapter + 1}章');
        }
        if (_isHorizontal) {
          final page = _txtGlobalPageIndex;
          return (page, '第 ${page + 1} / ${_txtAllPages.length} 页');
        }
        return (0, '当前位置');
      case FileFormat.epub:
        if (_isHorizontal) {
          final page = _epubGlobalPageIndex;
          return (_epubCurrentChapter, '第 ${_epubCurrentChapter + 1} 章 第 ${page + 1} 页');
        }
        return (_epubCurrentChapter, '第 ${_epubCurrentChapter + 1} 章');
      case FileFormat.pdf:
        return (_pdfPage, '第 ${_pdfPage + 1} / $_pdfTotalPages 页');
      case FileFormat.mobi:
      case FileFormat.azw3:
        return (0, '当前位置');
      default:
        return (0, '当前位置');
    }
  }

  Future<void> _addBookmark() async {
    if (widget.item.id == null) return;

    final noteController = TextEditingController();
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('添加书签'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: noteController,
            placeholder: '备注（可选）',
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: NeutralPalette.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    noteController.dispose();

    if (confirm == true) {
      final (position, positionText) = _getCurrentPosition();
      final bookmark = await _dao.insertBookmark(Bookmark(
        itemId: widget.item.id!,
        position: position,
        positionText: positionText,
        note: noteController.text.isEmpty ? null : noteController.text,
        createdAt: DateTime.now(),
      ));
      if (mounted) {
        setState(() => _bookmarks.add(bookmark));
        _showToast('书签添加成功');
      }
    }
  }

  void _showBookmarkList() {
    if (_bookmarks.isEmpty) {
      _showToast('还没有书签');
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: _controlBarColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Text(
                '书签（${_bookmarks.length}）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
            ),
            Divider(height: 1, color: _textColor.withOpacity(0.1)),
            Expanded(
              child: ListView.builder(
                cacheExtent: 200.0,
                itemCount: _bookmarks.length,
                itemBuilder: (context, index) {
                  final bm = _bookmarks[index];
                  return Dismissible(
                    key: ValueKey(bm.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(CupertinoIcons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) async {
                      await _dao.deleteBookmark(bm.id!);
                      setState(() => _bookmarks.removeAt(index));
                    },
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      onPressed: () {
                        Navigator.pop(context);
                        _jumpToBookmark(bm);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bm.positionText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _textColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (bm.note != null)
                                  Text(
                                    bm.note!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _textColor.withOpacity(0.6),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${bm.createdAt.month}/${bm.createdAt.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textColor.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToBookmark(Bookmark bookmark) {
    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          setState(() {
            _txtCurrentChapter = bookmark.position.clamp(0, _txtChapters.length - 1);
            _txtAllPages = [];
            _txtChapterPageOffsets = [];
            _txtPaginatedChapters = {};
            _txtNeedsPagination = true;
            _txtGlobalPageIndex = 0;
            if (_txtScrollController?.hasClients ?? false) {
              _txtScrollController!.jumpTo(0);
            }
          });
        } else if (_isHorizontal && bookmark.position < _txtAllPages.length) {
          _txtGlobalPageIndex = bookmark.position;
          _txtPageController?.jumpToPage(_txtGlobalPageIndex);
        }
        break;
      case FileFormat.epub:
        setState(() {
          _epubCurrentChapter = bookmark.position.clamp(0, _epubChapters.length - 1);
          _epubAllPages = [];
          _epubChapterPageOffsets = [];
          _epubPaginatedChapters = {};
          _epubNeedsPagination = true;
          _epubGlobalPageIndex = 0;
          if (_epubScrollController?.hasClients ?? false) {
            _epubScrollController!.jumpTo(0);
          }
        });
        break;
      case FileFormat.pdf:
        _pdfPage = bookmark.position;
        break;
      default:
        break;
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: NeutralColorsDark.surfaceElevated,
      ),
    );
  }

  @override
  void dispose() {
    _saveProgress();
    _showControlsNotifier.dispose();
    _expandedPanelNotifier.dispose();
    _horizontalCurrentPageNotifier.dispose();
    _horizontalTotalPagesNotifier.dispose();
    _brightnessNotifier.dispose();
    _progressSliderNotifier.dispose();
    _txtScrollController?.dispose();
    _txtPageController?.dispose();
    _epubScrollController?.dispose();
    _epubPageController?.dispose();
    _pdfScrollController.dispose();
    _pdfPageController.dispose();

    // 释放大内存对象
    _txtContent = '';
    _txtChapters.clear();
    _txtAllPages.clear();
    _txtChapterPageOffsets.clear();
    _txtPaginatedChapters.clear();
    _epubChapters.clear();
    _epubAllPages.clear();
    _epubChapterPageOffsets.clear();
    _epubPaginatedChapters.clear();
    _mobiContent = '';

    WakelockPlus.disable();
    super.dispose();
  }

  // ===================== 加载内容 =====================

  String _decodeWithEncoding(List<int> bytes, TextEncoding encoding) {
    switch (encoding) {
      case TextEncoding.utf8:
        return utf8.decode(bytes, allowMalformed: true);
      case TextEncoding.gbk:
      case TextEncoding.gb2312:
        return gbk.decode(bytes);
      case TextEncoding.big5:
      case TextEncoding.latin1:
        return latin1.decode(bytes);
      case TextEncoding.auto:
        if (_isValidUtf8(bytes)) {
          try {
            return utf8.decode(bytes);
          } catch (_) {
            return gbk.decode(bytes);
          }
        } else {
          try {
            return gbk.decode(bytes);
          } catch (_) {
            return latin1.decode(bytes);
          }
        }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Future<void> _loadTxtContent() async {
    // 重置分页状态，防止重新加载后页码错乱
    _txtNeedsPagination = true;
    _txtAllPages.clear();
    _txtChapterPageOffsets.clear();
    _txtPaginatedChapters.clear();
    _txtGlobalPageIndex = 0;

    try {
      final file = File(widget.item.filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        final fileSize = stat.size;
        final isLargeFile = fileSize > 20 * 1024 * 1024; // 20MB

        if (isLargeFile && mounted) {
          setState(() => _loadingMessage = '正在加载大文件 (${_formatFileSize(fileSize)})...');
        }

        var bytes = await file.readAsBytes();

        // 1. BOM 检测（UTF-8 BOM = EF BB BF）
        if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
          bytes = bytes.sublist(3);
        }

        // 2. 按用户指定编码或自动检测解码
        var content = _decodeWithEncoding(bytes, _textEncoding);

        // 大文件模式下尽快释放字节数组引用
        if (isLargeFile) {
          bytes = Uint8List(0);
        }

        // 3. 统一换行符
        content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

        // 4. 繁简转换
        switch (_chineseConversion) {
          case ChineseConversion.t2s:
            content = ChineseConverter.traditionalToSimplified(content);
          case ChineseConversion.s2t:
            content = ChineseConverter.simplifiedToTraditional(content);
          case ChineseConversion.none:
            break;
        }

        if (isLargeFile && mounted) {
          setState(() => _loadingMessage = '正在解析章节...');
        }

        _txtContent = content;
        _txtChapters = TxtChapterService.parseChapters(content, enabledRules: _enabledChapterRules);
        _txtChapters = TxtChapterService.applyEdits(_txtChapters, _chapterEdits);
        if (_txtChapters.isNotEmpty) {
          _txtCurrentChapter = 0;
          _txtContent = ''; // 内容已保存到章节，释放重复内存
        }
        if (mounted) setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    } catch (e) {
      _txtContent = '加载失败：$e';
      if (mounted) setState(() {
        _isLoading = false;
        _loadingMessage = '';
      });
    }
  }

  /// 启发式 UTF-8 验证：检查字节序列是否符合 UTF-8 编码规范
  bool _isValidUtf8(List<int> bytes) {
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b & 0x80 == 0) { i++; continue; }
      int trailing = 0;
      if ((b & 0xE0) == 0xC0) trailing = 1;
      else if ((b & 0xF0) == 0xE0) trailing = 2;
      else if ((b & 0xF8) == 0xF0) trailing = 3;
      else return false;
      for (int j = 1; j <= trailing; j++) {
        if (i + j >= bytes.length || (bytes[i + j] & 0xC0) != 0x80) return false;
      }
      i += trailing + 1;
    }
    return true;
  }

  void _computeTxtPages() {
    _txtAllPages = [];
    _txtChapterPageOffsets = [];
    _txtPaginatedChapters = {};
  }

  Future<void> _loadEpubContent() async {
    try {
      final chapters = await EpubService.parseChapters(widget.item.filePath);
      _epubChapters = chapters;
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _computeEpubPages() {
    _epubAllPages = [];
    _epubChapterPageOffsets = [];
    _epubPaginatedChapters = {};
  }

  Future<void> _loadPdfContent() async {
    try {
      final doc = await _pdfDocFuture!;
      if (mounted) {
        setState(() {
          _pdfTotalPages = doc.pageCount;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMobiContent() async {
    try {
      final file = File(widget.item.filePath);
      final bytes = await file.readAsBytes();
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        try {
          content = gbk.decode(bytes);
        } catch (_) {
          content = latin1.decode(bytes);
        }
      }
      final lines = content
          .split('\n')
          .where((l) => l.trim().length > 10)
          .where((l) => !RegExp(r'^[\x00-\x08\x0B\x0C\x0E-\x1F]+$').hasMatch(l))
          .toList();
      _mobiContent = lines.take(500).join('\n\n');
      if (_mobiContent.length > 10000) {
        _mobiContent = _mobiContent.substring(0, 10000);
      }
      if (_mobiContent.isEmpty) {
        _mobiContent = 'MOBI / AZW3 格式暂不支持完美解析\n\n建议通过 Calibre 等工具转换为 EPUB 格式后再导入';
      }
    } catch (e) {
      _mobiContent = 'MOBI / AZW3 格式暂不支持直接阅读\n\n建议通过 Calibre 等工具转换为 EPUB 格式后再导入';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ===================== 进度恢复 =====================

  Future<void> _restoreProgress() async {
    if (widget.item.id == null) return;
    final progress = await _dao.getProgress(widget.item.id!);
    if (progress == null) return;
    if (!mounted) return;

    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          if (_isHorizontal) {
            // 优先使用新的 chapterIndex + chapterOffset 字段
            if (progress.chapterIndex >= 0 && progress.chapterIndex < _txtChapters.length) {
              _txtCurrentChapter = progress.chapterIndex;
              _restoredChapterOffset = progress.chapterOffset.clamp(0.0, 1.0);
              _txtGlobalPageIndex = 0;
            } else if (progress.position >= _txtChapters.length) {
              // 旧数据兼容：position 存的是全局页码
              _txtGlobalPageIndex = progress.position;
              _restoredChapterOffset = -1.0;
            } else {
              // 旧数据兼容：position 存的是章节索引
              _txtCurrentChapter = progress.position.clamp(0, _txtChapters.length - 1);
              _restoredChapterOffset = -1.0;
              _txtGlobalPageIndex = 0;
            }
            setState(() {
              _txtAllPages = [];
              _txtChapterPageOffsets = [];
              _txtPaginatedChapters = {};
              _txtNeedsPagination = true;
            });
          } else {
            // 垂直滚动模式
            if (progress.chapterIndex >= 0 && progress.chapterIndex < _txtChapters.length) {
              // 新数据
              setState(() => _txtCurrentChapter = progress.chapterIndex);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_txtScrollController != null && _txtScrollController!.hasClients) {
                  final maxExtent = _txtScrollController!.position.maxScrollExtent;
                  final targetPixels = (progress.chapterOffset.clamp(0.0, 1.0) * maxExtent).clamp(0.0, maxExtent);
                  _txtScrollController!.jumpTo(targetPixels);
                }
              });
            } else if (progress.position < _txtChapters.length) {
              // 旧数据兼容
              setState(() => _txtCurrentChapter = progress.position);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_txtScrollController != null && _txtScrollController!.hasClients) {
                  final maxExtent = _txtScrollController!.position.maxScrollExtent;
                  final targetScrollPercent = (progress.percentage * _txtChapters.length) - progress.position;
                  final targetPixels = (targetScrollPercent.clamp(0.0, 1.0) * maxExtent).clamp(0.0, maxExtent);
                  _txtScrollController!.jumpTo(targetPixels);
                }
              });
            }
          }
        } else if (_isHorizontal) {
          _txtGlobalPageIndex = progress.position;
          _restoredChapterOffset = -1.0;
          setState(() => _txtNeedsPagination = true);
        } else if (!_isHorizontal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_txtScrollController != null && _txtScrollController!.hasClients) {
              final maxExtent = _txtScrollController!.position.maxScrollExtent;
              final targetPixels = (progress.percentage.clamp(0.0, 1.0) * maxExtent).clamp(0.0, maxExtent);
              _txtScrollController!.jumpTo(targetPixels);
            }
          });
        }
        break;
      case FileFormat.epub:
        if (_isHorizontal) {
          // 优先使用新的 chapterIndex + chapterOffset 字段
          if (progress.chapterIndex >= 0 && progress.chapterIndex < _epubChapters.length) {
            _epubCurrentChapter = progress.chapterIndex;
            _restoredChapterOffset = progress.chapterOffset.clamp(0.0, 1.0);
            _epubGlobalPageIndex = 0;
          } else if (progress.position >= _epubChapters.length) {
            // 旧数据兼容：position 存的是全局页码
            _epubGlobalPageIndex = progress.position;
            _restoredChapterOffset = -1.0;
          } else {
            // 旧数据兼容：position 存的是章节索引
            _epubCurrentChapter = progress.position.clamp(0, _epubChapters.length - 1);
            _restoredChapterOffset = -1.0;
            _epubGlobalPageIndex = 0;
          }
          setState(() {
            _epubAllPages = [];
            _epubChapterPageOffsets = [];
            _epubPaginatedChapters = {};
            _epubNeedsPagination = true;
          });
        } else {
          if (progress.chapterIndex >= 0 && progress.chapterIndex < _epubChapters.length) {
            // 新数据
            setState(() => _epubCurrentChapter = progress.chapterIndex);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_epubScrollController != null && _epubScrollController!.hasClients) {
                final maxExtent = _epubScrollController!.position.maxScrollExtent;
                final targetPixels = (progress.chapterOffset.clamp(0.0, 1.0) * maxExtent).clamp(0.0, maxExtent);
                _epubScrollController!.jumpTo(targetPixels);
              }
            });
          } else if (progress.position < _epubChapters.length) {
            // 旧数据兼容
            setState(() => _epubCurrentChapter = progress.position);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_epubScrollController != null && _epubScrollController!.hasClients) {
                final maxExtent = _epubScrollController!.position.maxScrollExtent;
                final targetScrollPercent = (progress.percentage * _epubChapters.length) - progress.position;
                final targetPixels = (targetScrollPercent.clamp(0.0, 1.0) * maxExtent).clamp(0.0, maxExtent);
                _epubScrollController!.jumpTo(targetPixels);
              }
            });
          }
        }
        break;
      case FileFormat.pdf:
        setState(() => _pdfPage = progress.position);
        if (!_isHorizontal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pdfScrollController.hasClients && _pdfTotalPages > 0) {
              final estimatedPageHeight = MediaQuery.of(context).size.width * 1.4;
              final target = (progress.position * estimatedPageHeight).clamp(
                0.0,
                _pdfScrollController.position.maxScrollExtent,
              );
              _pdfScrollController.jumpTo(target);
            }
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pdfPageController.hasClients && progress.position < _pdfTotalPages) {
              _pdfPageController.jumpToPage(progress.position);
            }
          });
        }
        break;
      default:
        break;
    }
  }

  // ===================== 进度保存 =====================

  double _getScrollPercent(ScrollController? controller) {
    if (controller == null || !controller.hasClients) return 0.0;
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    return (controller.position.pixels / maxExtent).clamp(0.0, 1.0);
  }

  double _getChapterOffsetFromGlobalPage(int globalPage, List<int> offsets, int chapterIndex, int totalPages) {
    if (offsets.isEmpty || chapterIndex < 0 || chapterIndex >= offsets.length) return 0.0;
    final chapterStart = offsets[chapterIndex];
    final chapterEnd = (chapterIndex + 1 < offsets.length) ? offsets[chapterIndex + 1] : totalPages;
    final chapterPages = chapterEnd - chapterStart;
    if (chapterPages <= 0) return 0.0;
    final chapterPage = (globalPage - chapterStart).clamp(0, chapterPages - 1);
    return chapterPage / chapterPages;
  }

  Future<void> _saveProgress() async {
    if (widget.item.id == null) return;

    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          if (_isHorizontal) {
            final globalPage = _txtGlobalPageIndex;
            final totalPages = _txtAllPages.length;
            final percentage = totalPages > 0 ? globalPage / totalPages : 0.0;
            final chapterOffset = _getChapterOffsetFromGlobalPage(globalPage, _txtChapterPageOffsets, _txtCurrentChapter, totalPages);
            await _dao.saveProgress(
              ReadingProgress(
                itemId: widget.item.id!,
                position: globalPage,
                positionText: '第 ${_txtCurrentChapter + 1}/${_txtChapters.length} 章 第 ${globalPage + 1}/${totalPages} 页',
                percentage: percentage,
                lastReadAt: DateTime.now(),
                chapterIndex: _txtCurrentChapter,
                chapterOffset: chapterOffset,
              ),
            );
          } else {
            final scrollPercent = _getScrollPercent(_txtScrollController);
            final percentage = (_txtCurrentChapter + scrollPercent) / _txtChapters.length;
            await _dao.saveProgress(
              ReadingProgress(
                itemId: widget.item.id!,
                position: _txtCurrentChapter,
                positionText: '第 ${_txtCurrentChapter + 1}/${_txtChapters.length} 章',
                percentage: percentage,
                lastReadAt: DateTime.now(),
                chapterIndex: _txtCurrentChapter,
                chapterOffset: scrollPercent,
              ),
            );
          }
        } else if (_isHorizontal) {
          final globalPage = _txtGlobalPageIndex;
          final totalPages = _txtAllPages.length;
          final percentage = totalPages > 0 ? globalPage / totalPages : 0.0;
          await _dao.saveProgress(
            ReadingProgress(
              itemId: widget.item.id!,
              position: globalPage,
              positionText: '第 ${globalPage + 1} / ${totalPages} 页',
              percentage: percentage,
              lastReadAt: DateTime.now(),
              chapterIndex: -1,
              chapterOffset: percentage,
            ),
          );
        } else {
          final scrollPercent = _getScrollPercent(_txtScrollController);
          final position = (scrollPercent * 100000).toInt();
          await _dao.saveProgress(
            ReadingProgress(
              itemId: widget.item.id!,
              position: position,
              positionText: '滚动位置 ${(scrollPercent * 100).toStringAsFixed(1)}%',
              percentage: scrollPercent,
              lastReadAt: DateTime.now(),
              chapterIndex: -1,
              chapterOffset: scrollPercent,
            ),
          );
        }
        break;
      case FileFormat.epub:
        if (_isHorizontal) {
          final globalPage = _epubGlobalPageIndex;
          final totalPages = _epubAllPages.length;
          final percentage = totalPages > 0 ? globalPage / totalPages : 0.0;
          final chapterOffset = _getChapterOffsetFromGlobalPage(globalPage, _epubChapterPageOffsets, _epubCurrentChapter, totalPages);
          await _dao.saveProgress(
            ReadingProgress(
              itemId: widget.item.id!,
              position: globalPage,
              positionText: '第 ${_epubCurrentChapter + 1} 章 第 ${globalPage + 1} 页',
              percentage: percentage,
              lastReadAt: DateTime.now(),
              chapterIndex: _epubCurrentChapter,
              chapterOffset: chapterOffset,
            ),
          );
        } else if (_epubChapters.isNotEmpty) {
          final scrollPercent = _getScrollPercent(_epubScrollController);
          final percentage = (_epubCurrentChapter + scrollPercent) / _epubChapters.length;
          await _dao.saveProgress(
            ReadingProgress(
              itemId: widget.item.id!,
              position: _epubCurrentChapter,
              positionText: '第 ${_epubCurrentChapter + 1} / ${_epubChapters.length} 章',
              percentage: percentage,
              lastReadAt: DateTime.now(),
              chapterIndex: _epubCurrentChapter,
              chapterOffset: scrollPercent,
            ),
          );
        }
        break;
      case FileFormat.pdf:
        final percentage =
            _pdfTotalPages > 0 ? (_pdfPage / _pdfTotalPages).toDouble() : 0.0;
        await _dao.saveProgress(
          ReadingProgress(
            itemId: widget.item.id!,
            position: _pdfPage,
            positionText: '第 ${_pdfPage + 1} / $_pdfTotalPages 页',
            percentage: percentage,
            lastReadAt: DateTime.now(),
            chapterIndex: -1,
            chapterOffset: percentage,
          ),
        );
        break;
      default:
        break;
    }

    await _dao.updateLastOpened(widget.item.id!);
  }

  // ===================== 交互 =====================

  void _toggleControls() {
    _showControlsNotifier.value = !_showControlsNotifier.value;
    if (!_showControlsNotifier.value) {
      _expandedPanelNotifier.value = _BottomPanel.none;
    }
  }

  void _hideControlsOnScroll() {
    if (_showControlsNotifier.value) {
      _showControlsNotifier.value = false;
    }
  }

  void _togglePanel(_BottomPanel panel) {
    _expandedPanelNotifier.value = (_expandedPanelNotifier.value == panel) ? _BottomPanel.none : panel;
    if (panel == _BottomPanel.progress) {
      _progressSliderValue = _getCurrentUnit().toDouble();
    }
  }

  void _toggleHorizontal() {
    setState(() {
      _isHorizontal = !_isHorizontal;
      _txtAllPages = [];
      _txtChapterPageOffsets = [];
      _txtPaginatedChapters = {};
      _epubAllPages = [];
      _epubChapterPageOffsets = [];
      _epubPaginatedChapters = {};
      _txtNeedsPagination = true;
      _epubNeedsPagination = true;
      _txtGlobalPageIndex = 0;
      _epubGlobalPageIndex = 0;
      if (_isHorizontal) {
        _txtPageController = PageController();
        _epubPageController = PageController();
      }
    });
    _saveSettings();
  }

  void _showMoreMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(widget.item.title, style: TextStyle(color: _textColor)),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showBookInfo();
            },
            child: const Text('书籍信息'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showEditInfo();
            },
            child: const Text('编辑信息'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showSearchSheet();
            },
            child: const Text('全文搜索'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _addBookmark();
            },
            child: const Text('添加书签'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showBookmarkList();
            },
            child: const Text('书签列表'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showBookInfo() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: BoxDecoration(
          color: _controlBarColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('书籍信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _textColor)),
                const SizedBox(height: 20),
                _infoRow('书名', widget.item.title),
                if (widget.item.author != null) _infoRow('作者', widget.item.author!),
                _infoRow('格式', widget.item.format.name.toUpperCase()),
                _infoRow('路径', widget.item.filePath),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.6))),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 14, color: _textColor)),
          ),
        ],
      ),
    );
  }

  void _showEditInfo() {
    final titleController = TextEditingController(text: widget.item.title);
    final authorController = TextEditingController(text: widget.item.author ?? '');

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('编辑信息'),
        content: Column(
          children: [
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: titleController,
              placeholder: '书名',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: NeutralPalette.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: authorController,
              placeholder: '作者',
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: NeutralPalette.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              await context.read<LibraryProvider>().updateItemInfo(
                widget.item.id!,
                title: titleController.text.isEmpty ? null : titleController.text,
                author: authorController.text.isEmpty ? null : authorController.text,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      titleController.dispose();
      authorController.dispose();
    });
  }

  void _showSearchSheet() {
    final searchController = TextEditingController();
    List<_SearchResultItem> results = [];

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          void performSearch() {
            final query = searchController.text.trim();
            if (query.isEmpty) return;
            final lowerQuery = query.toLowerCase();
            final matches = <_SearchResultItem>[];

            switch (widget.item.format) {
              case FileFormat.txt:
                if (_txtChapters.isNotEmpty) {
                  for (var ci = 0; ci < _txtChapters.length; ci++) {
                    final chapter = _txtChapters[ci];
                    final content = chapter.content.toLowerCase();
                    int offset = 0;
                    while (true) {
                      offset = content.indexOf(lowerQuery, offset);
                      if (offset == -1) break;
                      final snippetStart = offset > 20 ? offset - 20 : 0;
                      final snippetEnd = (offset + query.length + 30)
                          .clamp(0, chapter.content.length);
                      matches.add(_SearchResultItem(
                        chapterIndex: ci,
                        chapterTitle: chapter.title,
                        offsetInChapter: offset,
                        snippet: chapter.content.substring(snippetStart, snippetEnd),
                      ));
                      offset += query.length;
                      if (matches.length >= 20) break;
                    }
                    if (matches.length >= 20) break;
                  }
                } else {
                  final text = (_txtContent.isNotEmpty ? _txtContent : _txtAllPages.map((p) => p.text).join('\n')).toLowerCase();
                  int offset = 0;
                  while (true) {
                    offset = text.indexOf(lowerQuery, offset);
                    if (offset == -1) break;
                    final fullText = _txtContent.isNotEmpty ? _txtContent : _txtAllPages.map((p) => p.text).join('\n');
                    final snippetStart = offset > 20 ? offset - 20 : 0;
                    final snippetEnd = (offset + query.length + 30).clamp(0, fullText.length);
                    matches.add(_SearchResultItem(
                      chapterIndex: 0,
                      chapterTitle: '',
                      offsetInChapter: offset,
                      snippet: fullText.substring(snippetStart, snippetEnd),
                    ));
                    offset += query.length;
                    if (matches.length >= 20) break;
                  }
                }
                break;
              case FileFormat.epub:
                for (var ci = 0; ci < _epubChapters.length; ci++) {
                  final chapter = _epubChapters[ci];
                  final content = chapter.content.toLowerCase();
                  int offset = 0;
                  while (true) {
                    offset = content.indexOf(lowerQuery, offset);
                    if (offset == -1) break;
                    final snippetStart = offset > 20 ? offset - 20 : 0;
                    final snippetEnd = (offset + query.length + 30)
                        .clamp(0, chapter.content.length);
                    matches.add(_SearchResultItem(
                      chapterIndex: ci,
                      chapterTitle: chapter.title,
                      offsetInChapter: offset,
                      snippet: chapter.content.substring(snippetStart, snippetEnd),
                    ));
                    offset += query.length;
                    if (matches.length >= 20) break;
                  }
                  if (matches.length >= 20) break;
                }
                break;
              case FileFormat.mobi:
              case FileFormat.azw3:
                final text = _mobiContent.toLowerCase();
                int offset = 0;
                while (true) {
                  offset = text.indexOf(lowerQuery, offset);
                  if (offset == -1) break;
                  final snippetStart = offset > 20 ? offset - 20 : 0;
                  final snippetEnd = (offset + query.length + 30).clamp(0, _mobiContent.length);
                  matches.add(_SearchResultItem(
                    chapterIndex: 0,
                    chapterTitle: '',
                    offsetInChapter: offset,
                    snippet: _mobiContent.substring(snippetStart, snippetEnd),
                  ));
                  offset += query.length;
                  if (matches.length >= 20) break;
                }
                break;
              default:
                break;
            }
            setModalState(() => results = matches);
          }

          void onResultTap(_SearchResultItem result) {
            Navigator.pop(context);
            _jumpToSearchResult(result);
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: _controlBarColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoSearchTextField(
                          controller: searchController,
                          onSubmitted: (_) => performSearch(),
                          placeholder: '搜索内容',
                        ),
                      ),
                      CupertinoButton(
                        onPressed: performSearch,
                        child: Text('搜索', style: TextStyle(color: _textColor)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _textColor.withOpacity(0.1)),
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Text(
                            searchController.text.isEmpty ? '输入关键词搜索' : '未找到结果',
                            style: TextStyle(color: _textColor.withOpacity(0.5)),
                          ),
                        )
                      : ListView.builder(
                          cacheExtent: 200.0,
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final result = results[index];
                            return CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              onPressed: () => onResultTap(result),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (result.chapterTitle.isNotEmpty)
                                    Text(
                                      result.chapterTitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    result.snippet,
                                    style: TextStyle(fontSize: 14, color: _textColor),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
    searchController.dispose();
  }

  /// 跳转到搜索结果所在位置
  void _jumpToSearchResult(_SearchResultItem result) {
    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          setState(() {
            _txtCurrentChapter = result.chapterIndex.clamp(0, _txtChapters.length - 1);
            _txtAllPages = [];
            _txtChapterPageOffsets = [];
            _txtPaginatedChapters = {};
            _txtNeedsPagination = true;
            _txtGlobalPageIndex = 0;
            if (_txtScrollController?.hasClients ?? false) {
              _txtScrollController!.jumpTo(0);
            }
          });
        } else if (_isHorizontal && _txtAllPages.isNotEmpty) {
          // 无章节模式下尝试估算页面位置
          final fullText = _txtContent.isNotEmpty ? _txtContent : _txtAllPages.map((p) => p.text).join('\n');
          if (fullText.isNotEmpty) {
            final ratio = result.offsetInChapter / fullText.length;
            final targetPage = (ratio * _txtAllPages.length).toInt().clamp(0, _txtAllPages.length - 1);
            _txtGlobalPageIndex = targetPage;
            _txtPageController?.jumpToPage(targetPage);
          }
        }
        break;
      case FileFormat.epub:
        setState(() {
          _epubCurrentChapter = result.chapterIndex.clamp(0, _epubChapters.length - 1);
          _epubAllPages = [];
          _epubChapterPageOffsets = [];
          _epubPaginatedChapters = {};
          _epubNeedsPagination = true;
          _epubGlobalPageIndex = 0;
          if (_epubScrollController?.hasClients ?? false) {
            _epubScrollController!.jumpTo(0);
          }
        });
        break;
      default:
        break;
    }
  }

  void _showProgressSheet() {
    _showControlsNotifier.value = true;
    _expandedPanelNotifier.value = _BottomPanel.progress;
    _progressSliderValue = _getCurrentUnit().toDouble();
  }

  int _getTotalUnits() {
    switch (widget.item.format) {
      case FileFormat.txt:
        return _txtChapters.isNotEmpty ? _txtChapters.length : _txtAllPages.length;
      case FileFormat.epub:
        return _epubChapters.length;
      case FileFormat.pdf:
        return _pdfTotalPages;
      default:
        return 1;
    }
  }

  int _getCurrentUnit() {
    switch (widget.item.format) {
      case FileFormat.txt:
        return _txtChapters.isNotEmpty ? _txtCurrentChapter : _txtGlobalPageIndex;
      case FileFormat.epub:
        return _epubCurrentChapter;
      case FileFormat.pdf:
        return _pdfPage;
      default:
        return 0;
    }
  }

  void _jumpToUnit(int unit) {
    switch (widget.item.format) {
      case FileFormat.txt:
        if (_txtChapters.isNotEmpty) {
          setState(() {
            _txtCurrentChapter = unit.clamp(0, _txtChapters.length - 1);
            _txtScrollController?.jumpTo(0);
            _txtAllPages = [];
            _txtChapterPageOffsets = [];
            _txtPaginatedChapters = {};
            _txtNeedsPagination = true;
            _txtGlobalPageIndex = 0;
          });
        } else {
          _txtGlobalPageIndex = unit.clamp(0, _txtAllPages.length - 1);
          _txtPageController?.jumpToPage(_txtGlobalPageIndex);
        }
        break;
      case FileFormat.epub:
        setState(() {
          _epubCurrentChapter = unit.clamp(0, _epubChapters.length - 1);
          _epubScrollController?.jumpTo(0);
          _epubAllPages = [];
          _epubChapterPageOffsets = [];
          _epubPaginatedChapters = {};
          _epubNeedsPagination = true;
          _epubGlobalPageIndex = 0;
        });
        break;
      case FileFormat.pdf:
        if (!_isHorizontal) {
          if (_pdfScrollController.hasClients && _pdfTotalPages > 0) {
            final estimatedPageHeight = MediaQuery.of(context).size.width * 1.4;
            final target = (unit * estimatedPageHeight).clamp(
              0.0,
              _pdfScrollController.position.maxScrollExtent,
            );
            _pdfScrollController.jumpTo(target);
          }
        } else {
          if (_pdfPageController.hasClients && unit < _pdfTotalPages) {
            _pdfPageController.jumpToPage(unit);
          }
        }
        break;
      default:
        break;
    }
  }

  void _showChapterList() {
    final chapters = widget.item.format == FileFormat.txt
        ? _txtChapters.map((c) => c.title).toList()
        : widget.item.format == FileFormat.epub
            ? _epubChapters.map((c) => c.title).toList()
            : <String>[];
    if (chapters.isEmpty) {
      _showToast('暂无目录');
      return;
    }
    _showControlsNotifier.value = true;
    _expandedPanelNotifier.value = _BottomPanel.chapters;
  }

  void _showBrightnessSheet() {
    _showControlsNotifier.value = true;
    _expandedPanelNotifier.value = _BottomPanel.brightness;
  }

  void _showSettingsSheet() {
    _showControlsNotifier.value = true;
    _expandedPanelNotifier.value = _BottomPanel.settings;
  }

  Widget _buildSettingLabel(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textColor.withOpacity(0.7)),
    );
  }

  // ===================== 扉页 =====================

  bool get _shouldShowTitlePage {
    switch (widget.item.format) {
      case FileFormat.txt:
        return _txtCurrentChapter == 0;
      case FileFormat.epub:
        return _epubCurrentChapter == 0;
      case FileFormat.mobi:
      case FileFormat.azw3:
        return true;
      default:
        return false;
    }
  }

  Widget _buildTitlePage() {
    final topSafePadding = MediaQuery.viewPaddingOf(context).top;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(_horizontalPadding, topSafePadding + 40, _horizontalPadding, 40),
          child: Column(
            children: [
            if (widget.item.coverPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                child: Image.file(
                  File(widget.item.coverPath!),
                  width: 140,
                  height: 200,
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (_, __, ___) => _defaultCover(),
                ),
              )
            else
              _defaultCover(),
            const SizedBox(height: 32),
            Text(
              widget.item.title,
              style: TextStyle(
                fontSize: _fontSize + 8,
                fontWeight: FontWeight.bold,
                color: _textColor,
                fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.item.author != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.item.author!,
                style: TextStyle(
                  fontSize: _fontSize + 2,
                  color: _textColor.withOpacity(0.7),
                  fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
                ),
              ),
            ],
            if (widget.item.description != null && widget.item.description!.isNotEmpty) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s16),
                decoration: BoxDecoration(
                  color: _textColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Text(
                  widget.item.description!,
                  style: TextStyle(
                    fontSize: _fontSize - 2,
                    height: _lineHeight,
                    color: _textColor.withOpacity(0.8),
                    fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _defaultCover() {
    final neutral = NeutralPalette.of(context);
    return Container(
      width: 140,
      height: 200,
      decoration: BoxDecoration(
        color: neutral.divider,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Icon(
        CupertinoIcons.book,
        color: neutral.textTertiary,
        size: 48,
      ),
    );
  }

  // ===================== 构建 UI =====================

  @override
  Widget build(BuildContext context) {
    final bool isDark = _readingTheme == ReadingTheme.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _bgColor,
        body: Stack(
          children: [
            _buildContent(),
            if (_isLoading)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(),
                    if (_loadingMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _loadingMessage,
                        style: TextStyle(fontSize: 14, color: _textColor.withOpacity(0.6)),
                      ),
                    ],
                  ],
                ),
              ),
            // 亮度遮罩
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity((1.0 - _brightness).clamp(0.0, 1.0)),
              ),
            ),
            ListenableBuilder(
              listenable: Listenable.merge([_showControlsNotifier, _expandedPanelNotifier]),
              builder: (context, _) {
                if (!_showControlsNotifier.value) return const SizedBox.shrink();
                return Stack(
                  children: [
                    _buildAppBar(),
                    _buildBottomArea(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.item.format) {
      case FileFormat.txt:
        return _isHorizontal ? _buildTxtHorizontal() : _buildTxtView();
      case FileFormat.epub:
        return _isHorizontal ? _buildEpubHorizontal() : _buildEpubView();
      case FileFormat.pdf:
        return _buildPdfView();
      case FileFormat.mobi:
      case FileFormat.azw3:
        return _buildMobiView();
      default:
        return _buildFallbackView();
    }
  }

  // ---- TXT ----
  String _applyIndent(String text) {
    if (_firstLineIndent <= 0) return text;
    final indent = '　' * _firstLineIndent.round();
    return text.split('\n').map((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return line;
      return indent + line;
    }).join('\n');
  }

  List<String> _splitParagraphs(String content) {
    if (_firstLineIndent <= 0) {
      return content.split('\n').where((p) => p.trim().isNotEmpty).toList();
    }
    final indent = '　' * _firstLineIndent.round();
    return content
        .split('\n')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => indent + p)
        .toList();
  }

  Widget _buildTxtView() {
    final List<String> paragraphs;
    final String? chapterTitle;
    if (_txtChapters.isNotEmpty) {
      chapterTitle = _txtChapters[_txtCurrentChapter].title;
      paragraphs = _splitParagraphs(_txtChapters[_txtCurrentChapter].content);
    } else {
      chapterTitle = null;
      paragraphs = _splitParagraphs(_txtContent);
    }

    final hasNextChapter = _txtChapters.isNotEmpty && _txtCurrentChapter < _txtChapters.length - 1;
    final hasPrevChapter = _txtChapters.isNotEmpty && _txtCurrentChapter > 0;
    final topSafePadding = MediaQuery.viewPaddingOf(context).top;
    final extraBottomSpacing = _fontSize * _lineHeight * 1.5;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          controller: _txtScrollController,
          slivers: [
            if (hasPrevChapter)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: CupertinoButton(
                        onPressed: () {
                          setState(() {
                            _txtCurrentChapter--;
                            if (_txtScrollController?.hasClients ?? false) {
                              _txtScrollController!.jumpTo(0);
                            }
                          });
                          _saveProgress();
                        },
                        child: Text(
                          '上一章：${_txtChapters[_txtCurrentChapter - 1].title}',
                          style: TextStyle(color: _textColor.withOpacity(0.6), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_shouldShowTitlePage)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: topSafePadding + 40, bottom: topSafePadding + 60),
                    child: _buildTitlePage(),
                  ),
                ),
              ),
            if (chapterTitle != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(_horizontalPadding, _titleTopPadding, _horizontalPadding, _titleBottomPadding),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    chapterTitle,
                    style: TextStyle(
                      fontSize: _titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: _textColor,
                      height: 1.4,
                      fontFamily: _titleFontFamily.isEmpty ? null : _titleFontFamily,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
              sliver: SliverList.builder(
                itemCount: paragraphs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: _paragraphSpacing),
                    child: RepaintBoundary(
                      child: Text(
                        paragraphs[index],
                        style: _baseTextStyle,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (hasNextChapter)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: CupertinoButton(
                        onPressed: () {
                          setState(() {
                            _txtCurrentChapter++;
                            if (_txtScrollController?.hasClients ?? false) {
                              _txtScrollController!.jumpTo(0);
                            }
                          });
                          _saveProgress();
                        },
                        child: Text(
                          '下一章：${_txtChapters[_txtCurrentChapter + 1].title}',
                          style: TextStyle(color: _textColor.withOpacity(0.6), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: extraBottomSpacing + 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTxtHorizontal() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topSafePadding = MediaQuery.viewPaddingOf(context).top;
        final bottomSafePadding = MediaQuery.viewPaddingOf(context).bottom;
        // 分页可用高度需减去状态栏和导航栏高度
        final availableHeight = constraints.maxHeight - topSafePadding - bottomSafePadding;
        _txtViewSize = Size(constraints.maxWidth, availableHeight);

        if (_txtNeedsPagination) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _performTxtPagination(constraints.maxWidth, availableHeight);
          });
          return const Center(child: CupertinoActivityIndicator());
        }

        if (_txtAllPages.isEmpty) {
          return const Center(child: Text('内容为空'));
        }

        _txtPageController ??= PageController(initialPage: _txtGlobalPageIndex.clamp(0, _txtAllPages.length - 1));

        return PageView.builder(
          controller: _txtPageController,
          scrollDirection: Axis.horizontal,
          itemCount: _txtAllPages.length,
          onPageChanged: (index) {
            if (!mounted) return;
            final chapter = _findTxtChapterByPageIndex(index);
            _txtGlobalPageIndex = index;
            _horizontalCurrentPageNotifier.value = index + 1;
            _horizontalTotalPagesNotifier.value = _txtAllPages.length;
            if (chapter != _txtCurrentChapter) {
              _txtCurrentChapter = chapter;
            }
            _preloadTxtChaptersIfNeeded(index);
            _saveProgress();
            _showControlsNotifier.value = false;
          },
          itemBuilder: (context, index) {
            return _buildPaginatedPage(_txtAllPages[index], topSafePadding, bottomSafePadding);
          },
        );
      },
    );
  }

  Widget _buildPaginatedPage(TextPage? page, double topSafePadding, double bottomSafePadding) {
    if (page == null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        child: Container(color: _bgColor),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_horizontalPadding, topSafePadding + 16, _horizontalPadding, bottomSafePadding + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (page.chapterTitle != null)
              Padding(
                padding: EdgeInsets.only(top: _titleTopPadding),
                child: Text(
                  page.chapterTitle!,
                  style: _baseTextStyle.copyWith(
                    fontSize: _titleFontSize,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                    fontFamily: _titleFontFamily.isEmpty ? null : _titleFontFamily,
                  ),
                ),
              ),
            if (page.chapterTitle != null) SizedBox(height: _titleBottomPadding),
            Expanded(
              child: Text(
                page.text,
                style: _baseTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _performTxtPagination(double maxWidth, double maxHeight) {
    if (!mounted || !_txtNeedsPagination) return;

    final availableWidth = maxWidth - _horizontalPadding * 2;
    final availableHeight = maxHeight - 32;

    _txtAllPages = [];
    _txtChapterPageOffsets = [];
    _txtPaginatedChapters = {};

    if (_txtChapters.isNotEmpty) {
      final currentPages = _paginateTxtChapter(_txtCurrentChapter, availableWidth, availableHeight);
      _txtChapterPageOffsets.add(0);
      _txtAllPages.addAll(currentPages);
      _txtPaginatedChapters.add(_txtCurrentChapter);
    } else {
      _txtAllPages = TextPaginator.paginate(
        text: _txtContent,
        width: availableWidth,
        height: availableHeight,
        style: _baseTextStyle,
        lineHeight: _lineHeight,
        paragraphSpacing: _paragraphSpacing,
        firstLineIndent: _firstLineIndent,
      );
      _txtChapterPageOffsets.add(0);
    }

    if (!mounted) return;
    setState(() {
      _txtNeedsPagination = false;
      if (_restoredChapterOffset >= 0.0 && _txtAllPages.isNotEmpty) {
        _txtGlobalPageIndex = (_restoredChapterOffset * _txtAllPages.length).toInt().clamp(0, _txtAllPages.length - 1);
        _restoredChapterOffset = -1.0;
      } else {
        _txtGlobalPageIndex = _txtGlobalPageIndex.clamp(0, (_txtAllPages.length - 1).clamp(0, 999999));
      }
      _horizontalCurrentPageNotifier.value = _txtGlobalPageIndex + 1;
      _horizontalTotalPagesNotifier.value = _txtAllPages.length;
      if (_txtPageController?.hasClients ?? false) {
        _txtPageController!.jumpToPage(_txtGlobalPageIndex);
      }
    });

    // 预加载相邻章节
    if (_txtChapters.isNotEmpty) {
      final nextChapter = _txtCurrentChapter + 1;
      final prevChapter = _txtCurrentChapter - 1;
      if (nextChapter < _txtChapters.length) {
        _preloadTxtChapter(nextChapter);
      }
      if (prevChapter >= 0) {
        _preloadTxtChapter(prevChapter);
      }
    }
  }

  List<TextPage> _paginateTxtChapter(int chapterIndex, double availableWidth, double availableHeight) {
    if (chapterIndex < 0 || chapterIndex >= _txtChapters.length) return [];
    final chapter = _txtChapters[chapterIndex];
    final textStyle = _baseTextStyle;
    final titleStyle = textStyle.copyWith(
      fontSize: _titleFontSize,
      fontWeight: FontWeight.bold,
      height: 1.4,
      fontFamily: _titleFontFamily.isEmpty ? null : _titleFontFamily,
    );
    return TextPaginator.paginate(
      text: chapter.content,
      width: availableWidth,
      height: availableHeight,
      style: textStyle,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      firstLineIndent: _firstLineIndent,
      chapterTitle: chapter.title,
      titleStyle: titleStyle,
      titleTopPadding: _titleTopPadding,
      titleBottomPadding: _titleBottomPadding,
    );
  }

  int _findTxtChapterByPageIndex(int pageIndex) {
    if (_txtChapterPageOffsets.isEmpty) return 0;
    for (int i = _txtChapterPageOffsets.length - 1; i >= 0; i--) {
      if (pageIndex >= _txtChapterPageOffsets[i]) {
        return i.clamp(0, _txtChapters.length - 1);
      }
    }
    return 0;
  }

  void _appendTxtChapterPages(int chapterIndex, List<TextPage> pages) {
    if (pages.isEmpty) return;
    while (_txtChapterPageOffsets.length <= chapterIndex) {
      _txtChapterPageOffsets.add(_txtAllPages.length);
    }
    _txtAllPages.addAll(pages);
  }

  Future<void> _preloadTxtChaptersIfNeeded(int currentPageIndex) async {
    if (_txtViewSize == null || _txtIsPaginating || _txtChapters.isEmpty) return;
    final currentChapter = _findTxtChapterByPageIndex(currentPageIndex);
    final nextChapter = currentChapter + 1;
    final prevChapter = currentChapter - 1;

    if (nextChapter < _txtChapters.length && !_txtPaginatedChapters.contains(nextChapter)) {
      _preloadTxtChapter(nextChapter);
    }
    if (prevChapter >= 0 && !_txtPaginatedChapters.contains(prevChapter)) {
      _preloadTxtChapter(prevChapter);
    }
  }

  Future<void> _preloadTxtChapter(int chapterIndex) async {
    if (_txtViewSize == null || chapterIndex < 0 || chapterIndex >= _txtChapters.length) return;
    if (_txtPaginatedChapters.contains(chapterIndex) || _txtIsPaginating) return;

    _txtIsPaginating = true;

    await Future.delayed(Duration.zero);
    if (!mounted) return;

    final availableWidth = _txtViewSize!.width - _horizontalPadding * 2;
    final availableHeight = _txtViewSize!.height - 32;
    final pages = _paginateTxtChapter(chapterIndex, availableWidth, availableHeight);

    if (!mounted) return;
    setState(() {
      _appendTxtChapterPages(chapterIndex, pages);
      _txtPaginatedChapters.add(chapterIndex);
      _txtIsPaginating = false;
    });
  }

  // ---- EPUB ----
  Widget _buildEpubView() {
    if (_isLoading) {
      return const SizedBox.shrink();
    }
    if (_epubChapters.isEmpty) {
      return Center(child: Text('EPUB 内容为空', style: TextStyle(color: _textColor)));
    }
    final chapter = _epubChapters[_epubCurrentChapter];
    final paragraphs = _splitParagraphs(chapter.content);
    final hasNextChapter = _epubCurrentChapter < _epubChapters.length - 1;
    final hasPrevChapter = _epubCurrentChapter > 0;
    final topSafePadding = MediaQuery.viewPaddingOf(context).top;
    final extraBottomSpacing = _fontSize * _lineHeight * 1.5;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          controller: _epubScrollController,
          slivers: [
            if (hasPrevChapter)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: CupertinoButton(
                        onPressed: () {
                          setState(() {
                            _epubCurrentChapter--;
                            if (_epubScrollController?.hasClients ?? false) {
                              _epubScrollController!.jumpTo(0);
                            }
                          });
                          _saveProgress();
                        },
                        child: Text(
                          '上一章：${_epubChapters[_epubCurrentChapter - 1].title}',
                          style: TextStyle(color: _textColor.withOpacity(0.6), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_shouldShowTitlePage)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: topSafePadding + 40, bottom: topSafePadding + 60),
                    child: _buildTitlePage(),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                _horizontalPadding,
                _shouldShowTitlePage ? 0 : _titleTopPadding,
                _horizontalPadding,
                _titleBottomPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  chapter.title,
                  style: TextStyle(
                    fontSize: _titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                    height: 1.4,
                    fontFamily: _titleFontFamily.isEmpty ? null : _titleFontFamily,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
              sliver: SliverList.builder(
                itemCount: paragraphs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: _paragraphSpacing),
                    child: RepaintBoundary(
                      child: Text(
                        paragraphs[index],
                        style: _baseTextStyle,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (hasNextChapter)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: CupertinoButton(
                        onPressed: () {
                          setState(() {
                            _epubCurrentChapter++;
                            if (_epubScrollController?.hasClients ?? false) {
                              _epubScrollController!.jumpTo(0);
                            }
                          });
                          _saveProgress();
                        },
                        child: Text(
                          '下一章：${_epubChapters[_epubCurrentChapter + 1].title}',
                          style: TextStyle(color: _textColor.withOpacity(0.6), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: extraBottomSpacing + 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpubHorizontal() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topSafePadding = MediaQuery.viewPaddingOf(context).top;
        final bottomSafePadding = MediaQuery.viewPaddingOf(context).bottom;
        // 分页可用高度需减去状态栏和导航栏高度
        final availableHeight = constraints.maxHeight - topSafePadding - bottomSafePadding;
        _epubViewSize = Size(constraints.maxWidth, availableHeight);

        if (_isLoading) {
          return const SizedBox.shrink();
        }

        if (_epubChapters.isEmpty) {
          return const Center(child: Text('EPUB 内容为空'));
        }

        if (_epubNeedsPagination) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _performEpubPagination(constraints.maxWidth, availableHeight);
          });
          return const Center(child: CupertinoActivityIndicator());
        }

        if (_epubAllPages.isEmpty) {
          return const Center(child: Text('内容为空'));
        }

        _epubPageController ??= PageController(initialPage: _epubGlobalPageIndex.clamp(0, _epubAllPages.length - 1));

        return PageView.builder(
          controller: _epubPageController,
          scrollDirection: Axis.horizontal,
          itemCount: _epubAllPages.length,
          onPageChanged: (index) {
            if (!mounted) return;
            final chapter = _findEpubChapterByPageIndex(index);
            _epubGlobalPageIndex = index;
            _horizontalCurrentPageNotifier.value = index + 1;
            _horizontalTotalPagesNotifier.value = _epubAllPages.length;
            if (chapter != _epubCurrentChapter) {
              _epubCurrentChapter = chapter;
            }
            _preloadEpubChaptersIfNeeded(index);
            _saveProgress();
            _showControlsNotifier.value = false;
          },
          itemBuilder: (context, index) {
            return _buildPaginatedPage(_epubAllPages[index], topSafePadding, bottomSafePadding);
          },
        );
      },
    );
  }

  void _performEpubPagination(double maxWidth, double maxHeight) {
    if (!mounted || !_epubNeedsPagination) return;

    final availableWidth = maxWidth - _horizontalPadding * 2;
    final availableHeight = maxHeight - 32;

    _epubAllPages = [];
    _epubChapterPageOffsets = [];
    _epubPaginatedChapters = {};

    final currentPages = _paginateEpubChapter(_epubCurrentChapter, availableWidth, availableHeight);
    _epubChapterPageOffsets.add(0);
    _epubAllPages.addAll(currentPages);
    _epubPaginatedChapters.add(_epubCurrentChapter);

    if (!mounted) return;
    setState(() {
      _epubNeedsPagination = false;
      if (_restoredChapterOffset >= 0.0 && _epubAllPages.isNotEmpty) {
        _epubGlobalPageIndex = (_restoredChapterOffset * _epubAllPages.length).toInt().clamp(0, _epubAllPages.length - 1);
        _restoredChapterOffset = -1.0;
      } else {
        _epubGlobalPageIndex = _epubGlobalPageIndex.clamp(0, (_epubAllPages.length - 1).clamp(0, 999999));
      }
      _horizontalCurrentPageNotifier.value = _epubGlobalPageIndex + 1;
      _horizontalTotalPagesNotifier.value = _epubAllPages.length;
      if (_epubPageController?.hasClients ?? false) {
        _epubPageController!.jumpToPage(_epubGlobalPageIndex);
      }
    });

    // 预加载相邻章节
    final nextChapter = _epubCurrentChapter + 1;
    final prevChapter = _epubCurrentChapter - 1;
    if (nextChapter < _epubChapters.length) {
      _preloadEpubChapter(nextChapter);
    }
    if (prevChapter >= 0) {
      _preloadEpubChapter(prevChapter);
    }
  }

  List<TextPage> _paginateEpubChapter(int chapterIndex, double availableWidth, double availableHeight) {
    if (chapterIndex < 0 || chapterIndex >= _epubChapters.length) return [];
    final chapter = _epubChapters[chapterIndex];
    final textStyle = _baseTextStyle;
    final titleStyle = textStyle.copyWith(
      fontSize: _titleFontSize,
      fontWeight: FontWeight.bold,
      height: 1.4,
      fontFamily: _titleFontFamily.isEmpty ? null : _titleFontFamily,
    );
    return TextPaginator.paginate(
      text: chapter.content,
      width: availableWidth,
      height: availableHeight,
      style: textStyle,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      firstLineIndent: _firstLineIndent,
      chapterTitle: chapter.title,
      titleStyle: titleStyle,
      titleTopPadding: _titleTopPadding,
      titleBottomPadding: _titleBottomPadding,
    );
  }

  int _findEpubChapterByPageIndex(int pageIndex) {
    if (_epubChapterPageOffsets.isEmpty) return 0;
    for (int i = _epubChapterPageOffsets.length - 1; i >= 0; i--) {
      if (pageIndex >= _epubChapterPageOffsets[i]) {
        return i.clamp(0, _epubChapters.length - 1);
      }
    }
    return 0;
  }

  void _appendEpubChapterPages(int chapterIndex, List<TextPage> pages) {
    if (pages.isEmpty) return;
    while (_epubChapterPageOffsets.length <= chapterIndex) {
      _epubChapterPageOffsets.add(_epubAllPages.length);
    }
    _epubAllPages.addAll(pages);
  }

  Future<void> _preloadEpubChaptersIfNeeded(int currentPageIndex) async {
    if (_epubViewSize == null || _epubIsPaginating || _epubChapters.isEmpty) return;
    final currentChapter = _findEpubChapterByPageIndex(currentPageIndex);
    final nextChapter = currentChapter + 1;
    final prevChapter = currentChapter - 1;

    if (nextChapter < _epubChapters.length && !_epubPaginatedChapters.contains(nextChapter)) {
      _preloadEpubChapter(nextChapter);
    }
    if (prevChapter >= 0 && !_epubPaginatedChapters.contains(prevChapter)) {
      _preloadEpubChapter(prevChapter);
    }
  }

  Future<void> _preloadEpubChapter(int chapterIndex) async {
    if (_epubViewSize == null || chapterIndex < 0 || chapterIndex >= _epubChapters.length) return;
    if (_epubPaginatedChapters.contains(chapterIndex) || _epubIsPaginating) return;

    _epubIsPaginating = true;

    await Future.delayed(Duration.zero);
    if (!mounted) return;

    final availableWidth = _epubViewSize!.width - _horizontalPadding * 2;
    final availableHeight = _epubViewSize!.height - 32;
    final pages = _paginateEpubChapter(chapterIndex, availableWidth, availableHeight);

    if (!mounted) return;
    setState(() {
      _appendEpubChapterPages(chapterIndex, pages);
      _epubPaginatedChapters.add(chapterIndex);
      _epubIsPaginating = false;
    });
  }

  // ---- PDF ----
  Widget _buildPdfView() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: PdfDocumentLoader(
        doc: _pdfDocFuture!,
        documentBuilder: (context, doc, pageCount) {
          if (pageCount == 0) {
            return const Center(child: Text('PDF 内容为空'));
          }
          if (_isHorizontal) {
            return _buildPdfHorizontal(doc, pageCount);
          }
          return _buildPdfVertical(doc, pageCount);
        },
      ),
    );
  }

  Widget _buildPdfVertical(PdfDocument? doc, int pageCount) {
    return ListView.builder(
      cacheExtent: 200.0,
      controller: _pdfScrollController,
      padding: EdgeInsets.fromLTRB(
        _horizontalPadding,
        MediaQuery.viewPaddingOf(context).top + 20,
        _horizontalPadding,
        MediaQuery.paddingOf(context).bottom + 40,
      ),
      itemCount: pageCount,
      itemBuilder: (context, index) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.small),
            boxShadow: isDark
                ? null
                : [
                    AppShadows.ambient,
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: PdfPageView(
              key: ValueKey('pdf_page_${index + 1}'),
              pdfDocument: doc,
              pageNumber: index + 1,
              pageBuilder: (context, textureBuilder, pageSize) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = width * pageSize.height / pageSize.width;
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: textureBuilder(size: Size(width, height)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPdfHorizontal(PdfDocument? doc, int pageCount) {
    return PageView.builder(
      controller: _pdfPageController,
      itemCount: pageCount,
      onPageChanged: (index) {
        _pdfPage = index;
        _showControlsNotifier.value = false;
      },
      itemBuilder: (context, index) {
        return Container(
          color: _bgColor,
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Center(
            child: PdfPageView(
              key: ValueKey('pdf_page_${index + 1}'),
              pdfDocument: doc,
              pageNumber: index + 1,
              pageBuilder: (context, textureBuilder, pageSize) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final ratio = min(
                      constraints.maxWidth / pageSize.width,
                      constraints.maxHeight / pageSize.height,
                    );
                    final width = pageSize.width * ratio;
                    final height = pageSize.height * ratio;
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Container(
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          boxShadow: isDark
                              ? null
                              : const [
                                  AppShadows.ambient,
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: textureBuilder(size: Size(width, height)),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ---- MOBI ----
  Widget _buildMobiView() {
    final topSafePadding = MediaQuery.viewPaddingOf(context).top;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(_horizontalPadding, 0, _horizontalPadding, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_shouldShowTitlePage) ...[
                SizedBox(height: topSafePadding + 40),
                _buildTitlePage(),
                SizedBox(height: topSafePadding + 60),
              ],
              Text(
                _applyIndent(_mobiContent),
                style: _baseTextStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackView() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle, color: _textColor.withOpacity(0.4), size: 56),
              const SizedBox(height: 20),
              Text(
                '不支持的文件格式',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: _textColor.withOpacity(0.7), height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- AppBar ----
  Widget _buildAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: _controlBarColor.withOpacity(0.75),
              border: Border(
                bottom: BorderSide(
                  color: _textColor.withOpacity(0.06),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.viewPaddingOf(context).top,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: Icon(CupertinoIcons.chevron_back, color: _textColor),
                    ),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _textColor),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _addBookmark,
                      child: Icon(CupertinoIcons.bookmark, color: _textColor),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _showMoreMenu,
                      child: Icon(CupertinoIcons.ellipsis, color: _textColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- 底部区域(面板 + 功能栏) ----
  Widget _buildBottomArea() {
    final showPageIndicator = _isHorizontal && _horizontalTotalPagesNotifier.value > 0 && _expandedPanelNotifier.value == _BottomPanel.none;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: _controlBarColor.withOpacity(0.75),
              border: Border(
                top: BorderSide(
                  color: _textColor.withOpacity(0.06),
                  width: 0.5,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPageIndicator)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _horizontalCurrentPageNotifier,
                      builder: (context, currentPage, _) => ValueListenableBuilder<int>(
                        valueListenable: _horizontalTotalPagesNotifier,
                        builder: (context, totalPages, _) => Text(
                          '$currentPage / $totalPages',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: _textColor.withOpacity(0.6)),
                        ),
                      ),
                    ),
                  ),
                if (_expandedPanelNotifier.value != _BottomPanel.none) _buildExpandedPanel(),
                _buildBottomBarRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    switch (_expandedPanelNotifier.value) {
      case _BottomPanel.chapters:
        return _buildChaptersPanel();
      case _BottomPanel.bookmarks:
        return _buildBookmarksPanel();
      case _BottomPanel.progress:
        return _buildProgressPanel();
      case _BottomPanel.brightness:
        return _buildBrightnessPanel();
      case _BottomPanel.settings:
        return _buildSettingsPanel();
      case _BottomPanel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPanelContainer({required Widget child, double? height}) {
    final maxH = MediaQuery.of(context).size.height * 0.55;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height ?? maxH,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _controlBarColor,
        border: Border(top: BorderSide(color: _textColor.withOpacity(0.08))),
        boxShadow: isDark
            ? null
            : const [
                AppShadows.ambient,
              ],
      ),
      child: child,
    );
  }

  Widget _buildChaptersPanel() {
    final chapters = widget.item.format == FileFormat.txt
        ? _txtChapters.map((c) => c.title).toList()
        : widget.item.format == FileFormat.epub
            ? _epubChapters.map((c) => c.title).toList()
            : <String>[];
    final currentIndex = widget.item.format == FileFormat.txt ? _txtCurrentChapter : _epubCurrentChapter;

    if (chapters.isEmpty) {
      return _buildPanelContainer(
        height: 120,
        child: Center(
          child: Text('暂无目录', style: TextStyle(color: _textColor.withOpacity(0.5))),
        ),
      );
    }

    return _buildPanelContainer(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text(
              '目录（${chapters.length} 章）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor),
            ),
          ),
          Divider(height: 1, color: _textColor.withOpacity(0.1)),
          Expanded(
            child: ListView.builder(
              cacheExtent: 200.0,
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final isCurrent = index == currentIndex;
                final isTxt = widget.item.format == FileFormat.txt;
                final chapterItem = CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  onPressed: () {
                    if (isTxt) {
                      setState(() {
                        _txtCurrentChapter = index;
                        _txtAllPages = [];
                        _txtChapterPageOffsets = [];
                        _txtPaginatedChapters = {};
                        _txtNeedsPagination = true;
                        _txtGlobalPageIndex = 0;
                        if (_txtScrollController?.hasClients ?? false) {
                          _txtScrollController!.jumpTo(0);
                        }
                      });
                      _expandedPanelNotifier.value = _BottomPanel.none;
                    } else if (widget.item.format == FileFormat.epub) {
                      setState(() {
                        _epubCurrentChapter = index;
                        _epubAllPages = [];
                        _epubChapterPageOffsets = [];
                        _epubPaginatedChapters = {};
                        _epubNeedsPagination = true;
                        _epubGlobalPageIndex = 0;
                        if (_epubScrollController?.hasClients ?? false) {
                          _epubScrollController!.jumpTo(0);
                        }
                      });
                      _expandedPanelNotifier.value = _BottomPanel.none;
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          chapters[index],
                          style: TextStyle(
                            fontSize: 15,
                            color: isCurrent ? AppColors.primary : _textColor,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        const Icon(CupertinoIcons.checkmark, color: AppColors.primary, size: 18),
                    ],
                  ),
                );
                if (!isTxt) return chapterItem;
                return GestureDetector(
                  onLongPress: () => _showChapterEditMenu(context, index),
                  behavior: HitTestBehavior.translucent,
                  child: chapterItem,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showChapterEditMenu(BuildContext context, int index) {
    final canMerge = index < _txtChapters.length - 1;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(_txtChapters[index].title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _renameChapter(index);
            },
            child: const Text('重命名'),
          ),
          if (canMerge)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _mergeChapterWithNext(index);
              },
              child: const Text('与下一章合并'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _splitChapter(index);
            },
            child: const Text('拆分本章'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _renameChapter(int index) async {
    final controller = TextEditingController(text: _txtChapters[index].title);
    final newTitle = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('重命名章节'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '输入新标题',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.isEmpty) return;
    if (mounted) {
      setState(() {
        _chapterEdits.add(ChapterEdit(
          type: 'rename',
          chapterIndex: index,
          newTitle: newTitle,
        ));
      });
    }
    await _saveSettings();
    await _loadTxtContent();
    // 保持当前阅读位置尽量不变
    if (mounted && index < _txtChapters.length) {
      setState(() => _txtCurrentChapter = index.clamp(0, _txtChapters.length - 1));
    }
  }

  Future<void> _mergeChapterWithNext(int index) async {
    if (index >= _txtChapters.length - 1) return;
    setState(() {
      _chapterEdits.add(ChapterEdit(
        type: 'merge',
        chapterIndex: index,
        mergeEndIndex: index + 1,
      ));
    });
    await _saveSettings();
    await _loadTxtContent();
    setState(() => _txtCurrentChapter = index.clamp(0, _txtChapters.length - 1));
  }

  Future<void> _splitChapter(int index) async {
    final lineCount = _txtChapters[index].content.split('\n').length;
    final controller = TextEditingController();
    final splitAt = await showCupertinoDialog<int>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('拆分章节'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('本章共 $lineCount 行，输入在第几行后拆分：'),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                placeholder: '1-${lineCount - 1}',
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, val);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (splitAt == null || splitAt <= 0 || splitAt >= lineCount) return;
    setState(() {
      _chapterEdits.add(ChapterEdit(
        type: 'split',
        chapterIndex: index,
        splitAtLine: splitAt,
      ));
    });
    await _saveSettings();
    await _loadTxtContent();
    setState(() => _txtCurrentChapter = index.clamp(0, _txtChapters.length - 1));
  }

  Widget _buildBookmarksPanel() {
    if (_bookmarks.isEmpty) {
      return _buildPanelContainer(
        height: 120,
        child: Center(
          child: Text('还没有书签', style: TextStyle(color: _textColor.withOpacity(0.5))),
        ),
      );
    }
    return _buildPanelContainer(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text(
              '书签（${_bookmarks.length}）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor),
            ),
          ),
          Divider(height: 1, color: _textColor.withOpacity(0.1)),
          Expanded(
            child: ListView.builder(
              cacheExtent: 200.0,
              itemCount: _bookmarks.length,
              itemBuilder: (context, index) {
                final bm = _bookmarks[index];
                return Dismissible(
                  key: ValueKey(bm.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(CupertinoIcons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await _dao.deleteBookmark(bm.id!);
                    setState(() => _bookmarks.removeAt(index));
                  },
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    onPressed: () {
                      _expandedPanelNotifier.value = _BottomPanel.none;
                      _jumpToBookmark(bm);
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bm.positionText,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (bm.note != null)
                                Text(
                                  bm.note!,
                                  style: TextStyle(fontSize: 13, color: _textColor.withOpacity(0.6)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${bm.createdAt.month}/${bm.createdAt.day}',
                          style: TextStyle(fontSize: 12, color: _textColor.withOpacity(0.4)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel() {
    final total = _getTotalUnits();
    final current = _getCurrentUnit();
    _progressSliderValue ??= current.toDouble();
    _progressSliderNotifier.value = _progressSliderValue;
    return _buildPanelContainer(
      height: MediaQuery.of(context).size.height * 0.32,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: ValueListenableBuilder<double?>(
              valueListenable: _progressSliderNotifier,
              builder: (context, sliderValue, _) {
                final value = sliderValue ?? _progressSliderValue ?? current.toDouble();
                final pct = total > 0 ? (value / total * 100).toInt() : 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('阅读进度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor)),
                    const SizedBox(height: 16),
                    Text('$pct%', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: _textColor)),
                    const SizedBox(height: 4),
                    Text('已读 ${value.toInt()} / 共 $total',
                        style: TextStyle(fontSize: 13, color: _textColor.withOpacity(0.6))),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoSlider(
                        value: value.clamp(0, total.toDouble().max(1)),
                        max: total.toDouble().max(1),
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          _progressSliderValue = v;
                          _progressSliderNotifier.value = v;
                        },
                        onChangeEnd: (v) {
                          _jumpToUnit(v.toInt());
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrightnessPanel() {
    return _buildPanelContainer(
      height: MediaQuery.of(context).size.height * 0.36,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('亮度', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(CupertinoIcons.sun_min, color: _textColor.withOpacity(0.5), size: 20),
                    Expanded(
                      child: ValueListenableBuilder<double>(
                        valueListenable: _brightnessNotifier,
                        builder: (context, brightness, _) => Slider(
                          value: brightness,
                          min: 0.1,
                          max: 1.0,
                          activeColor: AppColors.primary,
                          onChanged: (v) => _brightnessNotifier.value = v,
                          onChangeEnd: (v) {
                            _brightness = v;
                            _saveSettings();
                          },
                        ),
                      ),
                    ),
                    Icon(CupertinoIcons.sun_max, color: _textColor.withOpacity(0.5), size: 20),
                  ],
                ),
                const SizedBox(height: 16),
                Text('背景颜色', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ThemeCircle(
                      color: const Color(0xFFF5F5F7),
                      isSelected: _readingTheme == ReadingTheme.light,
                      onTap: () {
                        setState(() => _readingTheme = ReadingTheme.light);
                        _saveSettings();
                      },
                    ),
                    _ThemeCircle(
                      color: const Color(0xFF1C1C1E),
                      isSelected: _readingTheme == ReadingTheme.dark,
                      onTap: () {
                        setState(() => _readingTheme = ReadingTheme.dark);
                        _saveSettings();
                      },
                    ),
                    _ThemeCircle(
                      color: const Color(0xFFF4ECD8),
                      isSelected: _readingTheme == ReadingTheme.sepia,
                      onTap: () {
                        setState(() => _readingTheme = ReadingTheme.sepia);
                        _saveSettings();
                      },
                    ),
                    _ThemeCircle(
                      color: const Color(0xFFE8F5E9),
                      isSelected: _readingTheme == ReadingTheme.eyeCare,
                      onTap: () {
                        setState(() => _readingTheme = ReadingTheme.eyeCare);
                        _saveSettings();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    final fontOptions = [
      ('系统默认', ''),
      ('宋体', 'serif'),
      ('黑体', 'sans-serif'),
    ];

    Widget buildGroupButton({
      required int groupId,
      required String label,
      required IconData icon,
    }) {
      final isExpanded = _settingsExpandedGroup == groupId;
      return GestureDetector(
        onTap: () {
          setState(() {
            _settingsExpandedGroup = isExpanded ? 0 : groupId;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: isExpanded ? AppColors.primary : _textColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isExpanded ? Colors.white : _textColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isExpanded ? Colors.white : _textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSlider({
      required double value,
      required double min,
      required double max,
      required int divisions,
      required String Function(double) labelBuilder,
      required ValueChanged<double> onChanged,
      VoidCallback? onChangeEnd,
    }) {
      return _LocalSlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        labelBuilder: labelBuilder,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        labelColor: _textColor.withOpacity(0.7),
      );
    }

    return _buildPanelContainer(
      height: MediaQuery.of(context).size.height * 0.55,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Text('阅读设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
              ),
              Divider(height: 1, color: _textColor.withOpacity(0.1)),
              Expanded(
                child: ListView(
                  cacheExtent: 200.0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    Row(
                      children: [
                        Expanded(child: buildGroupButton(groupId: 1, label: '标题样式', icon: CupertinoIcons.textformat_size)),
                        const SizedBox(width: 6),
                        Expanded(child: buildGroupButton(groupId: 2, label: '正文样式', icon: CupertinoIcons.doc_text)),
                        const SizedBox(width: 6),
                        Expanded(child: buildGroupButton(groupId: 3, label: '翻页方式', icon: CupertinoIcons.arrow_right_arrow_left)),
                        const SizedBox(width: 6),
                        Expanded(child: buildGroupButton(groupId: 4, label: '更多', icon: CupertinoIcons.ellipsis_circle)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_settingsExpandedGroup == 1) ...[
                      buildSlider(
                        value: _titleFontSize,
                        min: 14,
                        max: 40,
                        divisions: 26,
                        labelBuilder: (v) => '标题字号 ${v.toInt()}',
                        onChanged: (v) => _titleFontSize = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _titleTopPadding,
                        min: 0,
                        max: 80,
                        divisions: 16,
                        labelBuilder: (v) => '标题上间距 ${v.toInt()}',
                        onChanged: (v) => _titleTopPadding = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _titleBottomPadding,
                        min: 0,
                        max: 48,
                        divisions: 12,
                        labelBuilder: (v) => '标题下间距 ${v.toInt()}',
                        onChanged: (v) => _titleBottomPadding = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      _buildSettingLabel('标题字体'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: fontOptions.map((opt) {
                          final (label, family) = opt;
                          final isSelected = _titleFontFamily == family;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _titleFontFamily = family);
                              _saveSettings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : _textColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.small),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected ? Colors.white : _textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_settingsExpandedGroup == 2) ...[
                      buildSlider(
                        value: _fontSize,
                        min: 12,
                        max: 32,
                        divisions: 20,
                        labelBuilder: (v) => '正文字号 ${v.toInt()}',
                        onChanged: (v) => _fontSize = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _lineHeight,
                        min: 1.2,
                        max: 2.5,
                        divisions: 13,
                        labelBuilder: (v) => '行间距 ${v.toStringAsFixed(1)}',
                        onChanged: (v) => _lineHeight = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _paragraphSpacing,
                        min: 0,
                        max: 24,
                        divisions: 12,
                        labelBuilder: (v) => '段间距 ${v.toInt()}',
                        onChanged: (v) => _paragraphSpacing = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _letterSpacing,
                        min: -0.5,
                        max: 2.0,
                        divisions: 25,
                        labelBuilder: (v) => '字间距 ${v.toStringAsFixed(1)}',
                        onChanged: (v) => _letterSpacing = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _horizontalPadding,
                        min: 8,
                        max: 48,
                        divisions: 10,
                        labelBuilder: (v) => '左右边距 ${v.toInt()}',
                        onChanged: (v) => _horizontalPadding = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      buildSlider(
                        value: _firstLineIndent,
                        min: 0,
                        max: 4,
                        divisions: 8,
                        labelBuilder: (v) => '首行缩进 ${v.toStringAsFixed(1)}',
                        onChanged: (v) => _firstLineIndent = v,
                        onChangeEnd: () => _saveSettings(),
                      ),
                      const SizedBox(height: 8),
                      _buildSettingLabel('正文字体'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: fontOptions.map((opt) {
                          final (label, family) = opt;
                          final isSelected = _fontFamily == family;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _fontFamily = family);
                              _saveSettings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : _textColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.small),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected ? Colors.white : _textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      _buildSettingLabel('字体粗细'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          (FontWeight.w300, '细体'),
                          (FontWeight.w400, '常规'),
                          (FontWeight.w500, '中等'),
                          (FontWeight.w700, '粗体'),
                        ].map((opt) {
                          final (weight, label) = opt;
                          final isSelected = _fontWeight == weight;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _fontWeight = weight);
                              _saveSettings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : _textColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.small),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isSelected ? Colors.white : _textColor,
                                  fontWeight: weight,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_settingsExpandedGroup == 3) ...[
                      _buildSettingLabel('翻页方式'),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ToggleOption(
                            label: '纵向滚动',
                            isSelected: !_isHorizontal,
                            onTap: () {
                              if (_isHorizontal) {
                                _toggleHorizontal();
                              }
                            },
                          ),
                          _ToggleOption(
                            label: '横向翻页',
                            isSelected: _isHorizontal,
                            onTap: () {
                              if (!_isHorizontal) {
                                _toggleHorizontal();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_settingsExpandedGroup == 4) ...[
                      if (widget.item.format == FileFormat.txt) ...[
                        _buildSettingLabel('TXT 编码'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _ToggleOption(
                              label: '自动',
                              isSelected: _textEncoding == TextEncoding.auto,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.auto);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: 'UTF-8',
                              isSelected: _textEncoding == TextEncoding.utf8,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.utf8);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: 'GBK',
                              isSelected: _textEncoding == TextEncoding.gbk,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.gbk);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: 'GB2312',
                              isSelected: _textEncoding == TextEncoding.gb2312,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.gb2312);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: 'Big5',
                              isSelected: _textEncoding == TextEncoding.big5,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.big5);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: 'Latin1',
                              isSelected: _textEncoding == TextEncoding.latin1,
                              onTap: () {
                                setState(() => _textEncoding = TextEncoding.latin1);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettingLabel('繁简转换'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ToggleOption(
                              label: '不转换',
                              isSelected: _chineseConversion == ChineseConversion.none,
                              onTap: () {
                                setState(() => _chineseConversion = ChineseConversion.none);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: '繁转简',
                              isSelected: _chineseConversion == ChineseConversion.t2s,
                              onTap: () {
                                setState(() => _chineseConversion = ChineseConversion.t2s);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                            _ToggleOption(
                              label: '简转繁',
                              isSelected: _chineseConversion == ChineseConversion.s2t,
                              onTap: () {
                                setState(() => _chineseConversion = ChineseConversion.s2t);
                                _saveSettings();
                                _loadTxtContent();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSettingLabel('分章规则'),
                        const SizedBox(height: 4),
                        Text(
                          '关闭误匹配的规则（已保存为此书专属设置）',
                          style: TextStyle(fontSize: 12, color: _textColor.withOpacity(0.5)),
                        ),
                        const SizedBox(height: 8),
                        ...TxtChapterService.chapterPatternDefs.map((def) {
                          final isEnabled = _enabledChapterRules == null || _enabledChapterRules!.contains(def.id);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_enabledChapterRules == null) {
                                  // 当前全部启用，关闭此规则
                                  _enabledChapterRules = TxtChapterService.chapterPatternDefs
                                      .map((d) => d.id)
                                      .where((id) => id != def.id)
                                      .toList();
                                } else if (_enabledChapterRules!.contains(def.id)) {
                                  _enabledChapterRules!.remove(def.id);
                                } else {
                                  _enabledChapterRules!.add(def.id);
                                }
                              });
                              _saveSettings();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: _textColor.withOpacity(0.06)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      def.name,
                                      style: TextStyle(fontSize: 14, color: _textColor),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    height: 24,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: CupertinoSwitch(
                                        value: isEnabled,
                                        onChanged: (value) {
                                          setState(() {
                                            if (_enabledChapterRules == null) {
                                              _enabledChapterRules = TxtChapterService.chapterPatternDefs
                                                  .map((d) => d.id)
                                                  .where((id) => id != def.id)
                                                  .toList();
                                            } else if (value) {
                                              if (!_enabledChapterRules!.contains(def.id)) {
                                                _enabledChapterRules!.add(def.id);
                                              }
                                            } else {
                                              _enabledChapterRules!.remove(def.id);
                                            }
                                          });
                                          _saveSettings();
                                        },
                                        activeColor: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.medium),
                                onPressed: () {
                                  setState(() => _enabledChapterRules = null);
                                  _saveSettings();
                                },
                                child: Text(
                                  '恢复默认规则',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                color: _textColor.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(AppRadius.medium),
                                onPressed: () async {
                                  if (widget.item.id != null) {
                                    await _bookRuleDao.delete(widget.item.id!);
                                  }
                                  setState(() {
                                    _enabledChapterRules = ReadingSettingsService.instance.settings.enabledChapterRules;
                                    _textEncoding = ReadingSettingsService.instance.settings.textEncoding;
                                    _chineseConversion = ReadingSettingsService.instance.settings.chineseConversion;
                                    _chapterEdits = [];
                                  });
                                  _loadTxtContent();
                                },
                                child: Text(
                                  '清除本书设置',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _textColor.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            onPressed: () {
                              setState(() => _isLoading = true);
                              _loadTxtContent();
                            },
                            child: Text(
                              '重新解析目录',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- BottomBar ----
  Widget _buildBottomBarRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BottomBarItem(
            icon: CupertinoIcons.list_bullet,
            label: '目录',
            color: _textColor,
            isActive: _expandedPanelNotifier.value == _BottomPanel.chapters,
            onTap: () => _togglePanel(_BottomPanel.chapters),
          ),
          _BottomBarItem(
            icon: CupertinoIcons.bookmark,
            label: '书签',
            color: _textColor,
            isActive: _expandedPanelNotifier.value == _BottomPanel.bookmarks,
            onTap: () => _togglePanel(_BottomPanel.bookmarks),
          ),
          _BottomBarItem(
            icon: CupertinoIcons.chart_bar,
            label: '进度',
            color: _textColor,
            isActive: _expandedPanelNotifier.value == _BottomPanel.progress,
            onTap: () => _togglePanel(_BottomPanel.progress),
          ),
          _BottomBarItem(
            icon: _readingTheme == ReadingTheme.dark
                ? CupertinoIcons.moon_fill
                : CupertinoIcons.sun_max,
            label: '亮度',
            color: _textColor,
            isActive: _expandedPanelNotifier.value == _BottomPanel.brightness,
            onTap: () => _togglePanel(_BottomPanel.brightness),
          ),
          _BottomBarItem(
            icon: CupertinoIcons.textformat_size,
            label: '设置',
            color: _textColor,
            isActive: _expandedPanelNotifier.value == _BottomPanel.settings,
            onTap: () => _togglePanel(_BottomPanel.settings),
          ),
        ],
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isActive;

  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? activeColor : color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? activeColor : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.color,
    required this.textColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: isSelected
              ? Border.all(color: AppColors.primary, width: 2)
              : Border.all(color: neutral.divider),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
          ),
        ),
      ),
    );
  }
}

class _LocalSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final Color labelColor;

  const _LocalSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
    this.onChangeEnd,
    required this.labelColor,
  });

  @override
  State<_LocalSlider> createState() => _LocalSliderState();
}

class _LocalSliderState extends State<_LocalSlider> {
  late final ValueNotifier<double> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ValueNotifier<double>(widget.value);
  }

  @override
  void didUpdateWidget(_LocalSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _notifier.value = widget.value;
    }
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _notifier,
      builder: (context, current, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.labelBuilder(current),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: widget.labelColor,
              ),
            ),
            Slider(
              value: current,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              activeColor: AppColors.primary,
              onChanged: (v) {
                _notifier.value = v;
                widget.onChanged(v);
              },
              onChangeEnd: widget.onChangeEnd != null ? (double _) => widget.onChangeEnd!() : null,
            ),
          ],
        );
      },
    );
  }
}

class _ThemeCircle extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCircle({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: AppColors.primary, width: 3)
              : Border.all(color: neutral.divider, width: 1),
        ),
        child: isSelected
            ? const Icon(CupertinoIcons.checkmark, color: AppColors.primary, size: 20)
            : null,
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : neutral.divider,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : neutral.textPrimary,
          ),
        ),
      ),
    );
  }
}

extension on double {
  double max(double other) => this > other ? this : other;
}
