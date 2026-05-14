import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'dart:ui';
import 'package:archive/archive_io.dart';
import 'package:local_library/design_tokens/app_shadows.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_render/pdf_render.dart';
import 'package:pdf_render/pdf_render_widgets.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../models/comic_chapter.dart';
import '../../models/comic_series.dart';
import '../../models/library_item.dart';
import '../../models/reading_progress.dart';
import '../../database/library_dao.dart';
import '../../providers/comic_series_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/cover_service.dart';
import '../../services/mobi_service.dart';
import '../../services/rar_service.dart';
import '../../services/reading_settings_service.dart';

class ComicReaderScreen extends StatefulWidget {
  final LibraryItem item;
  final ComicSeries? series;
  final List<ComicChapter>? chapters;
  final int currentChapterIndex;
  final int initialPage;

  const ComicReaderScreen({
    super.key,
    required this.item,
    this.series,
    this.chapters,
    this.currentChapterIndex = 0,
    this.initialPage = 0,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  List<String> _pages = []; // RAR/CBR 文件路径列表（按需读取）
  bool _isLoading = true;
  late int _currentPage;
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _showThumbnailPanelNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showChapterPanelNotifier = ValueNotifier(false);
  PageController? _pageController;
  bool _isHorizontal = true;
  bool _isRightToLeft = false; // 日漫右开模式
  final LibraryDao _dao = LibraryDao();
  ComicSeriesProvider? _seriesProvider; // 缓存 provider 引用，供 dispose 时使用

  // PDF 状态
  int _pdfPage = 0;
  int _pdfTotalPages = 0;
  Future<PdfDocument>? _pdfDocFuture;

  // ZIP/CBZ 流式加载
  Archive? _zipArchive;
  InputFileStream? _zipInputStream;
  final List<ArchiveFile> _zipImageFiles = [];
  final Map<int, Uint8List> _pageCache = {};
  static const int _maxCacheSize = 7;
  static const int _maxCacheBytes = 50 * 1024 * 1024; // 50MB
  int _currentCacheBytes = 0;

  OrientationLock _orientationLock = OrientationLock.auto;

  // 主题与亮度（复用小说阅读器设置）
  ReadingTheme _readingTheme = ReadingTheme.dark;
  double _brightness = 1.0;
  final ValueNotifier<bool> _showSettingsPanelNotifier = ValueNotifier(false);

  // 章节导航
  late final ValueNotifier<int> _currentPageNotifier;

  int get _currentChapterIndex => widget.currentChapterIndex;
  bool get _hasChapters => widget.chapters != null && widget.chapters!.length > 1;
  bool get _hasPrevChapter => _hasChapters && _currentChapterIndex > 0;
  bool get _hasNextChapter => _hasChapters && _currentChapterIndex < widget.chapters!.length - 1;

  bool get _isPdf => widget.item.format == FileFormat.pdf;
  bool get _isZip =>
      widget.item.format == FileFormat.zip ||
      widget.item.format == FileFormat.cbz;
  bool get _isMobi =>
      widget.item.format == FileFormat.mobi ||
      widget.item.format == FileFormat.azw3;

  int get _totalImageCount {
    if (_isZip) return _zipImageFiles.length;
    return _pages.length;
  }

  int? _imageCacheWidth;

  int get _cacheWidth {
    if (_imageCacheWidth != null) return _imageCacheWidth!;
    final mq = MediaQuery.of(context);
    _imageCacheWidth = (mq.size.width * mq.devicePixelRatio).ceil();
    return _imageCacheWidth!;
  }

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pdfPage = widget.initialPage;
    _currentPageNotifier = ValueNotifier(widget.initialPage);
    _seriesProvider = context.read<ComicSeriesProvider>();
    WakelockPlus.enable();
    _loadSettings();
    _loadPages();
  }

  @override
  void dispose() {
    _saveProgress();
    _showControlsNotifier.dispose();
    _showThumbnailPanelNotifier.dispose();
    _showChapterPanelNotifier.dispose();
    _showSettingsPanelNotifier.dispose();
    _currentPageNotifier.dispose();
    _pageController?.dispose();

    // 释放大内存对象
    _pages.clear();
    _zipImageFiles.clear();
    _pageCache.clear();
    _currentCacheBytes = 0;
    _zipArchive = null;
    _zipInputStream?.closeSync();
    _zipInputStream = null;

    // 清理 MOBI 提取的临时图片
    if (_isMobi) {
      MobiService.clearExtractedImages(widget.item.filePath);
    }

    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  Future<void> _saveProgress() async {
    final int position;
    final int totalPages;

    if (_isPdf) {
      position = _pdfPage;
      totalPages = _pdfTotalPages;
    } else {
      position = _currentPage;
      totalPages = _totalImageCount;
    }

    // 系列漫画：通过 ComicSeriesProvider 保存进度
    if (widget.series != null && widget.series!.id != null) {
      final chapter = widget.chapters != null && _currentChapterIndex >= 0 && _currentChapterIndex < widget.chapters!.length
          ? widget.chapters![_currentChapterIndex]
          : null;
      if (_seriesProvider != null) {
        await _seriesProvider!.saveProgress(
          widget.series!.id!,
          chapter?.id,
          position,
          totalPages,
        );
      }
      return;
    }

    // 普通单文件漫画
    if (widget.item.id == null) return;
    final percentage = totalPages > 0 ? position / totalPages : 0.0;
    await _dao.saveProgress(
      ReadingProgress(
        itemId: widget.item.id!,
        position: position,
        positionText: '第 ${position + 1} / $totalPages 页',
        percentage: percentage,
        lastReadAt: DateTime.now(),
        chapterIndex: -1,
        chapterOffset: percentage,
      ),
    );
    await _dao.updateLastOpened(widget.item.id!);
  }

  Future<void> _loadPages() async {
    try {
      if (widget.item.format == FileFormat.zip ||
          widget.item.format == FileFormat.cbz) {
        await _loadZipPages();
      } else if (widget.item.format == FileFormat.rar ||
          widget.item.format == FileFormat.cbr) {
        await _loadRarPages();
      } else if (widget.item.format == FileFormat.pdf) {
        _pdfDocFuture = PdfDocument.openFile(widget.item.filePath);
        setState(() => _isLoading = false);
        _pageController = PageController(initialPage: _pdfPage);
        return;
      } else if (_isMobi) {
        _pages = await MobiService.extractImages(widget.item.filePath);
      }

      setState(() => _isLoading = false);

      if (_totalImageCount > 0) {
        _pageController = PageController(initialPage: _currentPage);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadZipPages() async {
    final file = File(widget.item.filePath);
    _zipInputStream = InputFileStream(file.path);
    _zipArchive = ZipDecoder().decodeBuffer(_zipInputStream!);

    final entries = <MapEntry<String, ArchiveFile>>[];
    for (final file in _zipArchive!) {
      if (file.isFile) {
        final name = file.name.toLowerCase();
        if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png') ||
            name.endsWith('.webp') ||
            name.endsWith('.gif') ||
            name.endsWith('.bmp')) {
          entries.add(MapEntry(file.name, file));
        }
      }
    }

    entries.sort((a, b) => a.key.compareTo(b.key));
    _zipImageFiles.addAll(entries.map((e) => e.value));
  }

  static bool _isImageByMagicBytes(List<int> data) {
    if (data.length < 4) return false;
    // JPEG: FF D8 FF
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
    // PNG: 89 50 4E 47
    if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
      return true;
    }
    // GIF: 47 49 46 38
    if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) {
      return true;
    }
    // BMP: 42 4D
    if (data[0] == 0x42 && data[1] == 0x4D) return true;
    // WEBP: RIFF....WEBP
    if (data.length >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return true;
    }
    return false;
  }

  Future<void> _loadRarPages() async {
    _pages = await RarService.extractImages(widget.item.filePath);
  }

  Future<Uint8List> _getPageData(int index) async {
    if (_pageCache.containsKey(index)) {
      final data = _pageCache.remove(index)!;
      _pageCache[index] = data;
      return data;
    }

    if (index < 0 || index >= _totalImageCount) {
      throw RangeError('Page index $index out of range');
    }

    final Uint8List data;
    if (_isZip) {
      data = Uint8List.fromList(_zipImageFiles[index].content);
    } else {
      data = await File(_pages[index]).readAsBytes();
    }

    _pageCache[index] = data;
    _currentCacheBytes += data.length;

    while (_pageCache.length > _maxCacheSize || _currentCacheBytes > _maxCacheBytes) {
      final firstKey = _pageCache.keys.first;
      final removed = _pageCache.remove(firstKey)!;
      _currentCacheBytes -= removed.length;
    }

    return data;
  }

  Future<void> _preloadPages(int centerIndex) async {
    final start = (centerIndex - 3).clamp(0, _totalImageCount - 1);
    final end = (centerIndex + 3).clamp(0, _totalImageCount - 1);

    final futures = <Future<void>>[];
    for (int i = start; i <= end; i++) {
      if (!_pageCache.containsKey(i)) {
        futures.add(_getPageData(i).catchError((e) {
          debugPrint('[ComicReader] 预加载页面 $i 失败: $e');
        }));
      }
    }
    await Future.wait(futures);
  }

  Color get _bgColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFFF5F5F7);
    if (global == AppThemeMode.dark) return Colors.black;
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return Colors.black;
      case ReadingTheme.light:
        return const Color(0xFFF5F5F7);
      case ReadingTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReadingTheme.eyeCare:
        return const Color(0xFFE8F5E9);
    }
  }

  Color get _textColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFF1D1D1F);
    if (global == AppThemeMode.dark) return const Color(0xFFE5E5EA);
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return const Color(0xFFE5E5EA);
      case ReadingTheme.light:
        return const Color(0xFF1D1D1F);
      case ReadingTheme.sepia:
        return const Color(0xFF5B4636);
      case ReadingTheme.eyeCare:
        return const Color(0xFF2E4A2E);
    }
  }

  Color get _controlBarColor {
    final global = ReadingSettingsService.instance.settings.appThemeMode;
    if (global == AppThemeMode.light) return const Color(0xFFF5F5F7);
    if (global == AppThemeMode.dark) return const Color(0xFF1C1C1E);
    switch (_readingTheme) {
      case ReadingTheme.dark:
        return const Color(0xFF1C1C1E);
      case ReadingTheme.light:
        return const Color(0xFFF5F5F7);
      case ReadingTheme.sepia:
        return const Color(0xFFF4ECD8);
      case ReadingTheme.eyeCare:
        return const Color(0xFFE8F5E9);
    }
  }

  Future<void> _loadSettings() async {
    await ReadingSettingsService.instance.load();
    final settings = ReadingSettingsService.instance.settings;
    _orientationLock = settings.orientationLock;
    _readingTheme = settings.theme;
    _brightness = settings.brightness;
    _applyOrientation();
  }

  Future<void> _saveSettings() async {
    final settings = ReadingSettingsService.instance.settings.copyWith(
      theme: _readingTheme,
      brightness: _brightness,
      orientationLock: _orientationLock,
    );
    await ReadingSettingsService.instance.save(settings);
  }

  void _applyOrientation() {
    switch (_orientationLock) {
      case OrientationLock.portrait:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
      case OrientationLock.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case OrientationLock.auto:
        SystemChrome.setPreferredOrientations([]);
        break;
    }
  }

  void _toggleOrientationLock() {
    final values = OrientationLock.values;
    final nextIndex = (_orientationLock.index + 1) % values.length;
    _orientationLock = values[nextIndex];
    _applyOrientation();
    _saveSettings();
    setState(() {});
  }

  void _toggleControls() {
    _showControlsNotifier.value = !_showControlsNotifier.value;
    if (!_showControlsNotifier.value) {
      _showThumbnailPanelNotifier.value = false;
      _showSettingsPanelNotifier.value = false;
    }
  }

  void _toggleThumbnailPanel() {
    _showThumbnailPanelNotifier.value = !_showThumbnailPanelNotifier.value;
    _showChapterPanelNotifier.value = false;
    _showSettingsPanelNotifier.value = false;
  }

  void _toggleChapterPanel() {
    _showChapterPanelNotifier.value = !_showChapterPanelNotifier.value;
    _showThumbnailPanelNotifier.value = false;
    _showSettingsPanelNotifier.value = false;
  }

  void _toggleSettingsPanel() {
    _showSettingsPanelNotifier.value = !_showSettingsPanelNotifier.value;
    _showThumbnailPanelNotifier.value = false;
    _showChapterPanelNotifier.value = false;
  }

  void _openPrevChapter() {
    if (!_hasPrevChapter) return;
    final prevChapter = widget.chapters![_currentChapterIndex - 1];
    _openChapter(prevChapter, _currentChapterIndex - 1);
  }

  void _openNextChapter() {
    if (!_hasNextChapter) return;
    final nextChapter = widget.chapters![_currentChapterIndex + 1];
    _openChapter(nextChapter, _currentChapterIndex + 1);
  }

  void _openChapter(ComicChapter chapter, int chapterIndex) {
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(
        builder: (_) => ComicReaderScreen(
          item: chapter.toLibraryItem(widget.series!),
          series: widget.series,
          chapters: widget.chapters,
          currentChapterIndex: chapterIndex,
        ),
      ),
    );
  }

  void _jumpToPage(int page) {
    _toggleThumbnailPanel();
    if (_isPdf) {
      _pdfPage = page;
      _pageController?.jumpToPage(page);
    } else {
      _currentPage = page;
      _pageController?.jumpToPage(page);
    }
    _preloadPages(page);
  }

  Future<void> _setCurrentPageAsCover() async {
    if (_totalImageCount == 0 || widget.item.id == null) return;

    try {
      final imageData = await _getPageData(_currentPage);
      final coverPath = await CoverService.instance.saveCustomCover(
        imageData,
        widget.item.title,
      );
      if (coverPath != null && context.mounted) {
        await context.read<LibraryProvider>().updateCover(widget.item.id!, coverPath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('封面设置成功'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('封面设置失败'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (_isPdf)
              _buildPdfViewer()
            else if (_totalImageCount == 0)
              Center(
                child: Text(
                  '无法解析此漫画文件',
                  style: TextStyle(color: _textColor.withOpacity(0.7)),
                ),
              )
            else
              _isHorizontal
                  ? _buildHorizontalGallery()
                  : _buildVerticalGallery(),
            // 亮度遮罩
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity((1.0 - _brightness).clamp(0.0, 1.0)),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _showControlsNotifier,
              builder: (context, showControls, child) {
                if (!showControls) return const SizedBox.shrink();
                return Stack(
                  children: [
                    _buildAppBar(),
                    _buildBottomBar(),
                  ],
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _showThumbnailPanelNotifier,
              builder: (context, showThumbnailPanel, child) {
                if (!showThumbnailPanel) return const SizedBox.shrink();
                return _buildThumbnailPanel();
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _showChapterPanelNotifier,
              builder: (context, showChapterPanel, child) {
                if (!showChapterPanel) return const SizedBox.shrink();
                return _buildChapterPanel();
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _showSettingsPanelNotifier,
              builder: (context, showSettingsPanel, child) {
                if (!showSettingsPanel) return const SizedBox.shrink();
                return _buildBrightnessPanel();
              },
            ),
            if (_hasChapters && !_isLoading) _buildChapterNavigationOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    return PdfDocumentLoader(
      doc: _pdfDocFuture!,
      documentBuilder: (context, doc, pageCount) {
        if (pageCount == 0) return const Center(child: Text('PDF 内容为空'));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pdfTotalPages != pageCount) {
            setState(() => _pdfTotalPages = pageCount);
          }
        });
        if (_isHorizontal) {
          return PageView.builder(
            controller: _pageController,
            reverse: _isRightToLeft,
            onPageChanged: (index) {
              _pdfPage = index;
              _currentPageNotifier.value = _pdfPage;
              _showControlsNotifier.value = false;
            },
            itemCount: pageCount,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              return Container(
                color: _bgColor,
                child: Center(
                  child: PdfPageView(
                    key: ValueKey('pdf_page_$pageNumber'),
                    pdfDocument: doc,
                    pageNumber: pageNumber,
                    pageBuilder: (context, textureBuilder, pageSize) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final ratio = min(
                            constraints.maxWidth / pageSize.width,
                            constraints.maxHeight / pageSize.height,
                          );
                          final width = pageSize.width * ratio;
                          final height = pageSize.height * ratio;
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
        return ListView.builder(
          cacheExtent: 200.0,
          itemCount: pageCount,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              color: _bgColor,
              child: PdfPageView(
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
            );
          },
        );
      },
    );
  }

  Widget _buildHorizontalGallery() {
    _preloadPages(_currentPage);

    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: _totalImageCount,
      builder: (context, index) {
        return PhotoViewGalleryPageOptions.customChild(
          child: FutureBuilder<Uint8List>(
            future: _getPageData(index),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  cacheWidth: _cacheWidth,
                );
              }
              return const Center(child: CupertinoActivityIndicator());
            },
          ),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
      scrollDirection: Axis.horizontal,
      reverse: _isRightToLeft,
      onPageChanged: (index) {
        _currentPage = index;
        _currentPageNotifier.value = index;
        _preloadPages(index);
        _showControlsNotifier.value = false;
      },
      backgroundDecoration: BoxDecoration(color: _bgColor),
    );
  }

  Widget _buildVerticalGallery() {
    _preloadPages(_currentPage);

    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: _totalImageCount,
      builder: (context, index) {
        return PhotoViewGalleryPageOptions.customChild(
          child: FutureBuilder<Uint8List>(
            future: _getPageData(index),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  cacheWidth: _cacheWidth,
                );
              }
              return const Center(child: CupertinoActivityIndicator());
            },
          ),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        );
      },
      scrollDirection: Axis.vertical,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
        _currentPageNotifier.value = index;
        _preloadPages(index);
      },
      backgroundDecoration: BoxDecoration(color: _bgColor),
    );
  }

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      CupertinoIcons.chevron_back,
                      color: _textColor,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.item.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_isPdf)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _setCurrentPageAsCover,
                      child: Icon(
                        CupertinoIcons.photo,
                        color: _textColor,
                      ),
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final bool hasPages = _isPdf ? _pdfTotalPages > 0 : _totalImageCount > 0;
    final int totalPages = _isPdf ? _pdfTotalPages : _totalImageCount;
    final int currentDisplay = _isPdf ? _pdfPage : _currentPage;

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPages)
                    Text(
                      '${currentDisplay + 1} / $totalPages',
                      style: TextStyle(
                        color: _textColor.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _toggleThumbnailPanel,
                        icon: Icon(
                          CupertinoIcons.square_grid_2x2,
                          color: _textColor,
                        ),
                      ),
                      if (_hasChapters)
                        IconButton(
                          onPressed: _toggleChapterPanel,
                          icon: Icon(
                            CupertinoIcons.list_bullet,
                            color: _textColor,
                          ),
                        ),
                      IconButton(
                        onPressed: _toggleOrientationLock,
                        icon: Icon(
                          switch (_orientationLock) {
                            OrientationLock.portrait => CupertinoIcons.device_phone_portrait,
                            OrientationLock.landscape => CupertinoIcons.device_phone_landscape,
                            OrientationLock.auto => CupertinoIcons.rotate_right,
                          },
                          color: _textColor,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _isHorizontal = !_isHorizontal);
                        },
                        icon: Icon(
                          _isHorizontal
                              ? CupertinoIcons.arrow_up_down
                              : CupertinoIcons.arrow_left_right,
                          color: _textColor,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _isRightToLeft = !_isRightToLeft);
                        },
                        icon: Icon(
                          _isRightToLeft
                              ? CupertinoIcons.arrow_right
                              : CupertinoIcons.arrow_left,
                          color: _textColor,
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleSettingsPanel,
                        icon: Icon(
                          _readingTheme == ReadingTheme.dark
                              ? CupertinoIcons.moon_fill
                              : CupertinoIcons.sun_max,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailPanel() {
    final int totalPages = _isPdf ? _pdfTotalPages : _totalImageCount;
    final int currentPage = _isPdf ? _pdfPage : _currentPage;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.45,
        decoration: BoxDecoration(
          color: _controlBarColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '缩略图 (${currentPage + 1} / $totalPages)',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _toggleThumbnailPanel,
                    child: Icon(
                      CupertinoIcons.xmark,
                      color: _textColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                cacheExtent: 200.0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: totalPages,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentPage;
                  return GestureDetector(
                    onTap: () => _jumpToPage(index),
                    child: Container(
                      decoration: BoxDecoration(
                        border: isCurrent
                            ? Border.all(color: AppColors.primary, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        child: _isPdf
                            ? _buildPdfThumbnail(index)
                            : _buildImageThumbnail(index),
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

  Widget _buildImageThumbnail(int index) {
    return FutureBuilder<Uint8List>(
      future: _getPageData(index),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            cacheWidth: 300,
          );
        }
        final neutral = NeutralPalette.of(context);
        return Container(
          color: neutral.divider,
          child: const Center(
            child: CupertinoActivityIndicator(),
          ),
        );
      },
    );
  }

  Widget _buildPdfThumbnail(int index) {
    return FutureBuilder<PdfDocument>(
      future: _pdfDocFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          final neutral = NeutralPalette.of(context);
          return Container(
            color: neutral.divider,
            child: const Center(child: CupertinoActivityIndicator(radius: 10)),
          );
        }
        return PdfPageView(
          key: ValueKey('pdf_thumb_${index + 1}'),
          pdfDocument: snapshot.data!,
          pageNumber: index + 1,
          pageBuilder: (context, textureBuilder, pageSize) {
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: textureBuilder(size: pageSize),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChapterNavigationOverlay() {
    return ValueListenableBuilder<int>(
      valueListenable: _currentPageNotifier,
      builder: (context, currentPage, child) {
        final int lastPageIndex = _isPdf ? _pdfTotalPages - 1 : _totalImageCount - 1;
        final bool showPrev = _hasPrevChapter && currentPage == 0;
        final bool showNext = _hasNextChapter && currentPage >= lastPageIndex;
        if (!showPrev && !showNext) return const SizedBox.shrink();

        // 横向模式：左右边缘悬浮条；纵向模式：上下居中浮动按钮
        if (_isHorizontal) {
          return Positioned.fill(
            child: Stack(
              children: [
                if (showPrev)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _openPrevChapter,
                      child: Container(
                        width: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _controlBarColor.withOpacity(0.9),
                              _controlBarColor.withOpacity(0.0),
                            ],
                          ),
                        ),
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              '上一章节：${widget.chapters![_currentChapterIndex - 1].title ?? '第${_currentChapterIndex}章节'}',
                              style: TextStyle(
                                color: _textColor.withOpacity(0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showNext)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _openNextChapter,
                      child: Container(
                        width: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              _controlBarColor.withOpacity(0.9),
                              _controlBarColor.withOpacity(0.0),
                            ],
                          ),
                        ),
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              '下一章节：${widget.chapters![_currentChapterIndex + 1].title ?? '第${_currentChapterIndex + 2}章节'}',
                              style: TextStyle(
                                color: _textColor.withOpacity(0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        // 纵向模式：上下居中浮动按钮（保持原有行为）
        return Positioned.fill(
          child: Stack(
            children: [
              if (showPrev)
                Positioned(
                  top: MediaQuery.viewPaddingOf(context).top + 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _openPrevChapter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _controlBarColor.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(AppRadius.large),
                          boxShadow: Theme.of(context).brightness == Brightness.dark
                              ? null
                              : [
                                  AppShadows.ambient,
                                ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.chevron_up, color: _textColor, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '上一章节：${widget.chapters![_currentChapterIndex - 1].title ?? '第${_currentChapterIndex}章节'}',
                              style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (showNext)
                Positioned(
                  bottom: MediaQuery.viewPaddingOf(context).bottom + 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _openNextChapter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _controlBarColor.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(AppRadius.large),
                          boxShadow: Theme.of(context).brightness == Brightness.dark
                              ? null
                              : [
                                  AppShadows.ambient,
                                ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '下一章节：${widget.chapters![_currentChapterIndex + 1].title ?? '第${_currentChapterIndex + 2}章节'}',
                              style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 6),
                            Icon(CupertinoIcons.chevron_down, color: _textColor, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChapterPanel() {
    if (widget.chapters == null || widget.chapters!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: _controlBarColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '章节目录（${widget.chapters!.length} 章节）',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _toggleChapterPanel,
                    child: Icon(
                      CupertinoIcons.xmark,
                      color: _textColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                cacheExtent: 200.0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: widget.chapters!.length,
                itemBuilder: (context, index) {
                  final chapter = widget.chapters![index];
                  final isCurrent = index == _currentChapterIndex;
                  final label = chapter.title ??
                      (chapter.chapterNumber != null
                          ? '第 ${chapter.chapterNumber == chapter.chapterNumber!.toInt() ? chapter.chapterNumber!.toInt() : chapter.chapterNumber} 章节'
                          : '第 ${index + 1} 章节');
                  return GestureDetector(
                    onTap: () {
                      if (isCurrent) {
                        _toggleChapterPanel();
                        return;
                      }
                      _openChapter(chapter, index);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppColors.primary.withOpacity(0.1)
                            : _textColor.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: isCurrent
                            ? Border.all(color: AppColors.primary.withOpacity(0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 15,
                                color: isCurrent ? AppColors.primary : _textColor,
                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            const Icon(CupertinoIcons.checkmark, color: AppColors.primary, size: 18),
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

  Widget _buildBrightnessPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.38,
        decoration: BoxDecoration(
          color: _controlBarColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
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
                  Row(
                    children: [
                      Text(
                        '亮度与主题',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const Spacer(),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _toggleSettingsPanel,
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: _textColor.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '亮度',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textColor.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.sun_min,
                        color: _textColor.withOpacity(0.5),
                        size: 20,
                      ),
                      Expanded(
                        child: Slider(
                          value: _brightness,
                          min: 0.1,
                          max: 1.0,
                          activeColor: AppColors.primary,
                          onChanged: (v) {
                            setState(() => _brightness = v);
                          },
                          onChangeEnd: (v) {
                            setState(() => _brightness = v);
                            _saveSettings();
                          },
                        ),
                      ),
                      Icon(
                        CupertinoIcons.sun_max,
                        color: _textColor.withOpacity(0.5),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '背景主题',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textColor.withOpacity(0.7),
                    ),
                  ),
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
      ),
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
