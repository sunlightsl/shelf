import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/comic_chapter.dart';
import '../models/comic_reading_progress.dart';
import '../models/comic_series.dart';
import '../providers/comic_series_provider.dart';
import '../services/cover_service.dart';
import '../widgets/pressable.dart';
import 'readers/comic_reader_screen.dart';

class ComicSeriesDetailScreen extends StatefulWidget {
  final ComicSeries series;

  const ComicSeriesDetailScreen({super.key, required this.series});

  @override
  State<ComicSeriesDetailScreen> createState() => _ComicSeriesDetailScreenState();
}

class _ComicSeriesDetailScreenState extends State<ComicSeriesDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ComicSeriesProvider>().selectSeries(widget.series);
    });
  }

  void _openChapter(ComicChapter chapter, {int initialPage = 0}) {
    final provider = context.read<ComicSeriesProvider>();
    final chapters = provider.chapters;
    final currentIndex = chapters.indexWhere((c) => c.id == chapter.id);
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ComicReaderScreen(
          item: chapter.toLibraryItem(widget.series),
          series: widget.series,
          chapters: chapters,
          currentChapterIndex: currentIndex >= 0 ? currentIndex : 0,
          initialPage: initialPage,
        ),
      ),
    );
  }

  void _continueReading() {
    final provider = context.read<ComicSeriesProvider>();
    final progress = provider.progress;
    final chapters = provider.chapters;
    if (chapters.isEmpty) return;

    ComicChapter? targetChapter;
    if (progress?.chapterId != null) {
      targetChapter = chapters.cast<ComicChapter?>().firstWhere(
        (c) => c?.id == progress!.chapterId,
        orElse: () => null,
      );
    }
    targetChapter ??= chapters.firstWhere(
      (c) => !c.isRead,
      orElse: () => chapters.first,
    );
    final initialPage = (progress != null && targetChapter?.id == progress.chapterId)
        ? progress.currentPage
        : 0;
    _openChapter(targetChapter, initialPage: initialPage);
  }

  void _showChapterMenu(ComicChapter chapter) {
    final provider = context.read<ComicSeriesProvider>();
    final chapters = provider.chapters;
    final isFirst = chapters.isNotEmpty && chapters.first.id == chapter.id;
    final isLast = chapters.isNotEmpty && chapters.last.id == chapter.id;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(chapter.title ?? '第${chapter.chapterNumber?.toInt() ?? 0}章节'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showEditChapterNameDialog(chapter);
            },
            child: const Text('修改章节名称'),
          ),
          if (!isFirst)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _moveChapterUp(chapter);
              },
              child: const Text('上移'),
            ),
          if (!isLast)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _moveChapterDown(chapter);
              },
              child: const Text('下移'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showMoveToPositionDialog(chapter);
            },
            child: const Text('指定位置'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              await _pickChapterCover(chapter);
            },
            child: const Text('更换封面'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              provider.markChapterRead(chapter.id!, !chapter.isRead);
            },
            child: Text(chapter.isRead ? '标记为未读' : '标记为已读'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await showCupertinoDialog<bool>(
                context: context,
                builder: (context) => CupertinoAlertDialog(
                  title: const Text('确认删除'),
                  content: const Text('删除此章节后无法恢复，是否继续？'),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted && chapter.id != null) {
                await provider.deleteChapter(chapter.id!);
              }
            },
            child: const Text('删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showEditChapterNameDialog(ComicChapter chapter) {
    final controller = TextEditingController(text: chapter.title ?? '');
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('修改章节名称'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '章节名称',
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: NeutralPalette.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              if (chapter.id != null) {
                await context.read<ComicSeriesProvider>().updateChapterTitle(
                  chapter.id!,
                  controller.text.trim().isEmpty ? null : controller.text.trim(),
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _moveChapterUp(ComicChapter chapter) async {
    final provider = context.read<ComicSeriesProvider>();
    final chapters = provider.chapters;
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index <= 0) return;
    final prev = chapters[index - 1];
    final temp = prev.sortOrder;
    await provider.moveChapterOrder(prev.id!, chapter.sortOrder);
    await provider.moveChapterOrder(chapter.id!, temp);
  }

  Future<void> _moveChapterDown(ComicChapter chapter) async {
    final provider = context.read<ComicSeriesProvider>();
    final chapters = provider.chapters;
    final index = chapters.indexWhere((c) => c.id == chapter.id);
    if (index < 0 || index >= chapters.length - 1) return;
    final next = chapters[index + 1];
    final temp = next.sortOrder;
    await provider.moveChapterOrder(next.id!, chapter.sortOrder);
    await provider.moveChapterOrder(chapter.id!, temp);
  }

  void _showMoveToPositionDialog(ComicChapter chapter) {
    final provider = context.read<ComicSeriesProvider>();
    final chapters = provider.chapters;
    final controller = TextEditingController(text: (chapters.indexWhere((c) => c.id == chapter.id) + 1).toString());
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('指定位置'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Text('当前共 ${chapters.length} 章节'),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: controller,
                placeholder: '输入目标位置（1-${chapters.length}）',
                keyboardType: TextInputType.number,
                padding: const EdgeInsets.all(AppSpacing.s12),
                decoration: BoxDecoration(
                  color: NeutralPalette.of(context).surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              final targetPos = int.tryParse(controller.text.trim());
              if (targetPos != null && chapter.id != null) {
                final newOrder = targetPos - 1;
                await provider.moveChapterOrder(chapter.id!, newOrder);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _pickChapterCover(ComicChapter chapter) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null || chapter.id == null) return;
      final bytes = await image.readAsBytes();
      final coverPath = await CoverService.instance.saveCustomCover(bytes, chapter.title ?? 'chapter');
      if (coverPath != null && mounted) {
        await context.read<ComicSeriesProvider>().changeChapterCover(chapter.id!, coverPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('章节封面更换成功'), duration: Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      debugPrint('更换章节封面失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('封面更换失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ComicSeriesProvider>(
      builder: (context, provider, child) {
        final series = provider.selectedSeries ?? widget.series;
        final chapters = provider.chapters;
        final progress = provider.progress;
        final neutral = NeutralPalette.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          backgroundColor: neutral.background,
          body: CustomScrollView(
            slivers: [
              _buildSliverAppBar(series, isDark),
              SliverToBoxAdapter(
                child: _buildHeader(series, progress, chapters, isDark),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chapter = chapters[index];
                      return _buildChapterTile(chapter, progress, isDark);
                    },
                    childCount: chapters.length,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(ComicSeries series, bool isDark) {
    final neutral = NeutralPalette.of(context);
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: neutral.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (series.coverPath != null)
              Image.file(
                File(series.coverPath!),
                fit: BoxFit.cover,
              )
            else
              Container(color: neutral.surfaceElevated),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ],
        ),
        title: Text(
          series.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ComicSeries series, ComicReadingProgress? progress, List<ComicChapter> chapters, bool isDark) {
    final neutral = NeutralPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
      color: neutral.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (series.author != null)
            Text(
              series.author!,
              style: TextStyle(
                fontSize: 15,
                color: neutral.textSecondary,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatusBadge(series.status),
              const SizedBox(width: 12),
              Text(
                '${series.readChapters} / ${series.totalChapters} 章节',
                style: TextStyle(
                  fontSize: 14,
                  color: neutral.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (chapters.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 14),
                borderRadius: BorderRadius.circular(AppRadius.small),
                onPressed: _continueReading,
                child: Text(
                  progress != null ? '继续阅读' : '开始阅读',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SeriesStatus status) {
    final (label, color) = switch (status) {
      SeriesStatus.ongoing => ('连载中', FunctionalColors.success),
      SeriesStatus.completed => ('已完结', AppColors.primary),
      SeriesStatus.hiatus => ('停更', FunctionalColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildChapterTile(ComicChapter chapter, ComicReadingProgress? progress, bool isDark) {
    final neutral = NeutralPalette.of(context);
    final isCurrent = progress?.chapterId == chapter.id;
    final chapterLabel = chapter.chapterNumber != null
        ? '第 ${chapter.chapterNumber?.toStringAsFixed(chapter.chapterNumber! == chapter.chapterNumber!.toInt() ? 0 : 1)} 章节'
        : (chapter.title ?? '未知章节');

    return Pressable(
      onTap: () => _openChapter(chapter),
      onLongPress: () => _showChapterMenu(chapter),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: neutral.surface,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: isCurrent
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: chapter.isRead && chapter.coverPath == null
                    ? FunctionalColors.success.withOpacity(0.1)
                    : (isDark ? neutral.surfaceElevated : neutral.background),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              clipBehavior: Clip.antiAlias,
              child: chapter.coverPath != null
                  ? Image.file(
                      File(chapter.coverPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 150,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          chapter.isRead
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.book,
                          color: chapter.isRead
                              ? FunctionalColors.success
                              : (neutral.textTertiary),
                          size: 22,
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        chapter.isRead
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.book,
                        color: chapter.isRead
                            ? FunctionalColors.success
                            : (neutral.textTertiary),
                        size: 22,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.primary : (neutral.textPrimary),
                    ),
                  ),
                  if (chapter.title != null && chapter.title != chapterLabel)
                    Text(
                      chapter.title!,
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (chapter.pageCount > 0)
                    Text(
                      '${chapter.pageCount} 页',
                      style: TextStyle(
                        fontSize: 12,
                        color: neutral.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Text(
                  '读到这里',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
