import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import '../models/library_item.dart';
import '../services/video_filename_parser.dart';
import 'readers/video_player_screen.dart';

class VideoSeriesDetailScreen extends StatelessWidget {
  final String seriesName;
  final List<LibraryItem> episodes;

  const VideoSeriesDetailScreen({
    super.key,
    required this.seriesName,
    required this.episodes,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 按季、集排序
    final sorted = List<LibraryItem>.from(episodes);
    sorted.sort((a, b) {
      final pa = VideoFilenameParser.parse(a.filePath);
      final pb = VideoFilenameParser.parse(b.filePath);
      final sa = pa.seasonNumber ?? 1;
      final sb = pb.seasonNumber ?? 1;
      if (sa != sb) return sa.compareTo(sb);
      final ea = pa.episodeNumber ?? 0;
      final eb = pb.episodeNumber ?? 0;
      return ea.compareTo(eb);
    });

    return Scaffold(
      backgroundColor: neutral.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: neutral.background,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                seriesName,
                style: TextStyle(
                  color: neutral.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              background: Container(
                color: neutral.surfaceElevated,
                child: _buildHeaderCover(isDark, neutral),
              ),
            ),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: Icon(CupertinoIcons.chevron_back, color: neutral.textPrimary),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '共 ${sorted.length} 集',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: neutral.textPrimary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverList.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = sorted[index];
                final parse = VideoFilenameParser.parse(item.filePath);
                return _EpisodeTile(
                  item: item,
                  label: parse.displayLabel,
                  subtitle: parse.episodeTitle.isNotEmpty ? parse.episodeTitle : null,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          item: item,
                          episodes: sorted.length > 1 ? sorted : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 20),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCover(bool isDark, NeutralPalette neutral) {
    // 尝试用第一集封面或通用封面
    final firstWithCover = episodes.isEmpty
        ? null
        : episodes.firstWhere(
            (e) => e.coverPath != null,
            orElse: () => episodes.first,
          );
    if (firstWithCover?.coverPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(firstWithCover!.coverPath!),
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  neutral.background.withOpacity(0.3),
                  neutral.background.withOpacity(0.9),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Icon(
        CupertinoIcons.play_circle,
        size: 64,
        color: neutral.textTertiary,
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final LibraryItem item;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _EpisodeTile({
    required this.item,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: neutral.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: neutral.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.coverPath != null
                    ? Image.file(
                        File(item.coverPath!),
                        fit: BoxFit.cover,
                        width: 48,
                        height: 48,
                        cacheWidth: 200,
                      )
                    : Center(
                        child: Icon(
                          CupertinoIcons.play_circle,
                          color: neutral.textTertiary,
                          size: 24,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: neutral.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: neutral.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (item.totalProgress != null && item.totalProgress! > 0)
                    Text(
                      _formatDuration(item.totalProgress!),
                      style: TextStyle(
                        fontSize: 12,
                        color: neutral.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: neutral.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
