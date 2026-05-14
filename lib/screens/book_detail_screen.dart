import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import '../database/library_dao.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import 'readers/novel_reader_screen.dart';

class BookDetailScreen extends StatefulWidget {
  final LibraryItem item;

  const BookDetailScreen({
    super.key,
    required this.item,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  final LibraryDao _dao = LibraryDao();
  ReadingProgress? _progress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    if (widget.item.id != null) {
      final progress = await _dao.getProgress(widget.item.id!);
      if (mounted) {
        setState(() {
          _progress = progress;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _openReader() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => NovelReaderScreen(item: widget.item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasProgress = _progress != null && _progress!.position > 0;

    return Scaffold(
      backgroundColor: neutral.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(isDark, neutral),
          SliverToBoxAdapter(
            child: _buildHeader(neutral, hasProgress),
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDark, NeutralPalette neutral) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: neutral.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.item.coverPath != null)
              Image.file(
                File(widget.item.coverPath!),
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
          widget.item.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(NeutralPalette neutral, bool hasProgress) {
    final progressText = hasProgress
        ? '已读 ${_progress!.percentage >= 0.99 ? '99' : (_progress!.percentage * 100).toInt()}%'
        : null;
    final formatLabel = switch (widget.item.format) {
      FileFormat.epub => 'EPUB',
      FileFormat.txt => 'TXT',
      FileFormat.pdf => 'PDF',
      FileFormat.mobi => 'MOBI',
      FileFormat.azw3 => 'AZW3',
      _ => '未知格式',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      color: neutral.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.item.author != null && widget.item.author!.isNotEmpty)
            Text(
              widget.item.author!,
              style: TextStyle(
                fontSize: 15,
                color: neutral.textSecondary,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoBadge(formatLabel, AppColors.primary),
              const SizedBox(width: 12),
              if (widget.item.fileSize != null)
                Text(
                  _formatFileSize(widget.item.fileSize!),
                  style: TextStyle(
                    fontSize: 14,
                    color: neutral.textSecondary,
                  ),
                ),
            ],
          ),
          if (progressText != null) ...[
            const SizedBox(height: 8),
            Text(
              progressText,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: BorderRadius.circular(AppRadius.small),
              onPressed: _openReader,
              child: Text(
                hasProgress ? '继续阅读' : '开始阅读',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (widget.item.tags.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.item.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: neutral.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: neutral.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (widget.item.description != null && widget.item.description!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              '简介',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: neutral.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.item.description!,
              style: TextStyle(
                fontSize: 14,
                color: neutral.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildMetaInfo(neutral),
        ],
      ),
    );
  }

  Widget _buildMetaInfo(NeutralPalette neutral) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '文件信息',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: neutral.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _buildMetaRow('添加时间', _formatDate(widget.item.addedDate)),
        if (widget.item.lastOpenedDate != null)
          _buildMetaRow('上次阅读', _formatDate(widget.item.lastOpenedDate!)),
        _buildMetaRow('文件路径', widget.item.filePath),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    final neutral = NeutralPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: neutral.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: neutral.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String label, Color color) {
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
