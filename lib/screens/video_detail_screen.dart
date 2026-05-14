import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_library/design_tokens/app_spacing.dart';
import 'package:local_library/design_tokens/app_radius.dart';
import 'package:local_library/design_tokens/app_colors.dart';
import '../database/library_dao.dart';
import '../models/library_item.dart';
import '../models/reading_progress.dart';
import '../services/video_filename_parser.dart';
import '../services/tmdb_service.dart';
import '../widgets/pressable.dart';
import 'readers/video_player_screen.dart';

class VideoDetailScreen extends StatefulWidget {
  final LibraryItem item;
  final List<LibraryItem>? episodes;

  const VideoDetailScreen({
    super.key,
    required this.item,
    this.episodes,
  });

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  final LibraryDao _dao = LibraryDao();
  ReadingProgress? _progress;
  bool _isLoading = true;

  // 各集观看进度
  final Map<int, ReadingProgress> _episodeProgress = {};

  // TMDB 刮削数据
  TMDBDetails? _tmdbDetails;
  TMDBCredits? _tmdbCredits;
  bool _isTmdbLoading = false;

  List<LibraryItem> get _episodes {
    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      final list = List<LibraryItem>.from(widget.episodes!);
      if (list.length > 1) {
        list.sort((a, b) {
          final sourceA = a.isCloudSource ? a.title : a.filePath;
          final sourceB = b.isCloudSource ? b.title : b.filePath;
          final pa = VideoFilenameParser.parse(sourceA);
          final pb = VideoFilenameParser.parse(sourceB);
          final sa = pa.seasonNumber ?? 0;
          final sb = pb.seasonNumber ?? 0;
          if (sa != sb) return sa.compareTo(sb);
          final ea = pa.episodeNumber ?? 0;
          final eb = pb.episodeNumber ?? 0;
          return ea.compareTo(eb);
        });
      }
      return list;
    }
    return [widget.item];
  }

  bool get _isSeries => _episodes.length > 1;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _loadTmdbData();
  }

  Future<void> _loadTmdbData() async {
    if (!TMDBService.instance.hasApiKey) return;
    setState(() => _isTmdbLoading = true);

    try {
      final query = TMDBService.extractQuery(widget.item.title);
      final results = await TMDBService.instance.search(query);
      if (results.isNotEmpty) {
        final top = results.first;
        final tmdbResults = await Future.wait([
          TMDBService.instance.getDetails(top.id, top.mediaType),
          TMDBService.instance.getCredits(top.id, top.mediaType),
        ]);
        final details = tmdbResults[0] as TMDBDetails?;
        final credits = tmdbResults[1] as TMDBCredits?;
        if (mounted) {
          if (details != null) setState(() => _tmdbDetails = details);
          if (credits != null) setState(() => _tmdbCredits = credits);
        }
      }
    } catch (e) {
      debugPrint('[VideoDetail] TMDB 加载失败: $e');
    } finally {
      if (mounted) setState(() => _isTmdbLoading = false);
    }
  }

  Future<void> _loadProgress() async {
    final firstEpisode = _episodes.first;
    if (firstEpisode.id != null) {
      final progress = await _dao.getProgress(firstEpisode.id!);
      // 加载所有分集的观看进度
      for (final ep in _episodes) {
        if (ep.id != null) {
          final epProgress = await _dao.getProgress(ep.id!);
          if (epProgress != null) {
            _episodeProgress[ep.id!] = epProgress;
          }
        }
      }
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

  void _playEpisode(LibraryItem episode) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => VideoPlayerScreen(
          item: episode,
          streamUrl: episode.streamUrl,
          episodes: _episodes.length > 1 ? _episodes : null,
        ),
      ),
    );
  }

  void _continuePlaying() {
    final targetEpisode = _progress != null
        ? _episodes.firstWhere(
            (e) => e.id == _progress!.itemId,
            orElse: () => _episodes.first,
          )
        : _episodes.first;
    _playEpisode(targetEpisode);
  }

  String? get _coverPath {
    // 优先远程封面
    for (final e in _episodes) {
      if (e.remoteCoverUrl != null) return e.remoteCoverUrl;
    }
    if (widget.item.remoteCoverUrl != null) return widget.item.remoteCoverUrl;
    for (final e in _episodes) {
      if (e.coverPath != null) return e.coverPath;
    }
    return widget.item.coverPath;
  }

  bool get _hasRemoteCover {
    return widget.item.remoteCoverUrl != null ||
        _episodes.any((e) => e.remoteCoverUrl != null);
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: neutral.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(isDark, neutral),
          SliverToBoxAdapter(
            child: _buildHeader(neutral),
          ),
          if (_isSeries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  '剧集列表 (${_episodes.length} 集)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: neutral.textPrimary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverList.separated(
                itemCount: _episodes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final episode = _episodes[index];
                  final parse = episode.isCloudSource
                      ? null
                      : VideoFilenameParser.parse(episode.filePath);
                  // 云端条目用 title 作为标签，本地文件用文件名解析
                  final label = episode.isCloudSource
                      ? episode.title
                      : (parse?.displayLabel ?? '');
                  final subtitle = episode.isCloudSource
                      ? null
                      : (parse?.episodeTitle.isNotEmpty == true ? parse!.episodeTitle : null);
                  return _EpisodeTile(
                    episode: episode,
                    label: label,
                    subtitle: subtitle,
                    progress: episode.id != null ? _episodeProgress[episode.id] : null,
                    onTap: () => _playEpisode(episode),
                  );
                },
              ),
            ),
          ],
          // 演职人员
          if (_tmdbCredits != null && _tmdbCredits!.cast.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildCastSection(neutral),
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
    final backdropUrl = _tmdbDetails?.backdropPath != null
        ? TMDBService.posterUrl(_tmdbDetails!.backdropPath, size: 'original')
        : null;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: neutral.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (backdropUrl != null)
              Image.network(
                backdropUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackCover(),
              )
            else if (_coverPath != null)
              _buildCoverImage(_coverPath!, fit: BoxFit.cover)
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

  Widget _fallbackCover() {
    final neutral = NeutralPalette.of(context);
    if (_coverPath != null) {
      return _buildCoverImage(_coverPath!, fit: BoxFit.cover);
    }
    return Container(color: neutral.surfaceElevated);
  }

  /// 根据路径判断使用网络图片还是本地文件图片
  Widget _buildCoverImage(String path, {required BoxFit fit}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          color: NeutralPalette.of(context).surfaceElevated,
          child: Icon(CupertinoIcons.film, color: NeutralPalette.of(context).textTertiary),
        ),
      );
    }
    return Image.file(
      File(path),
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: NeutralPalette.of(context).surfaceElevated,
        child: Icon(CupertinoIcons.film, color: NeutralPalette.of(context).textTertiary),
      ),
    );
  }

  Widget _buildHeader(NeutralPalette neutral) {
    final hasProgress = _progress != null && _progress!.position > 0;
    final progressText = hasProgress
        ? '已观看 ${_progress!.percentage >= 0.99 ? '99' : (_progress!.percentage * 100).toInt()}%'
        : null;
    final tmdb = _tmdbDetails;
    final posterUrl = tmdb?.posterPath != null
        ? TMDBService.posterUrl(tmdb!.posterPath, size: 'w500')
        : widget.item.remoteCoverUrl;
    final description = tmdb?.overview ?? widget.item.description;

    return Container(
      padding: const EdgeInsets.all(20),
      color: neutral.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报 + 信息行（TMDB 优先，其次远程封面）
          if (posterUrl != null || tmdb != null || widget.item.remoteCoverUrl != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (posterUrl != null)
                  Hero(
                    tag: 'hero_video_cover_${widget.item.filePath.hashCode}',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        child: SizedBox(
                          width: 120,
                          height: 180,
                          child: _buildCoverImage(posterUrl!, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                if (posterUrl != null) const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tmdb?.voteAverage != null && tmdb!.voteAverage > 0)
                        Row(
                          children: [
                            Icon(CupertinoIcons.star_fill, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${tmdb.voteAverage.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: neutral.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      if (tmdb?.runtime != null && tmdb!.runtime! > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          '时长: ${tmdb.runtime} 分钟',
                          style: TextStyle(fontSize: 13, color: neutral.textSecondary),
                        ),
                      ],
                      if (tmdb?.genres.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: tmdb!.genres.map((g) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: neutral.surfaceElevated,
                                borderRadius: BorderRadius.circular(AppRadius.small),
                              ),
                              child: Text(
                                g,
                                style: TextStyle(fontSize: 11, color: neutral.textSecondary),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (tmdb?.releaseDate != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '上映: ${tmdb!.releaseDate}',
                          style: TextStyle(fontSize: 13, color: neutral.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          if (posterUrl != null || tmdb != null) const SizedBox(height: 16),
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
              _buildInfoBadge(
                _isSeries ? '剧集' : '电影',
                AppColors.primary,
              ),
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
          // 主播放按钮
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: BorderRadius.circular(AppRadius.medium),
              color: AppColors.primary,
              onPressed: _continuePlaying,
              child: Text(
                hasProgress ? '继续播放' : '开始播放',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 次级操作按钮行
          _buildActionRow(neutral),
          if (description != null && description.isNotEmpty) ...[
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
            _ExpandableDescription(text: description, neutral: neutral),
          ],
        ],
      ),
    );
  }

  /// 次级操作按钮行：收藏 / 标记已看
  Widget _buildActionRow(NeutralPalette neutral) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            borderRadius: BorderRadius.circular(AppRadius.medium),
            color: neutral.surfaceElevated,
            onPressed: () async {
              if (widget.item.id != null) {
                await _dao.toggleFavorite(widget.item.id!);
                if (mounted) {
                  final updated = await _dao.getItemById(widget.item.id!);
                  if (updated != null) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(updated.isFavorite ? '已加入收藏' : '已取消收藏'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.item.isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  color: widget.item.isFavorite ? AppColors.primary : neutral.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.item.isFavorite ? '已收藏' : '收藏',
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.item.isFavorite ? AppColors.primary : neutral.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            borderRadius: BorderRadius.circular(AppRadius.medium),
            color: neutral.surfaceElevated,
            onPressed: () async {
              if (_progress != null && _progress!.itemId != null) {
                await _dao.saveProgress(ReadingProgress(
                  itemId: _progress!.itemId,
                  position: 0,
                  positionText: '00:00',
                  percentage: 1.0,
                  lastReadAt: DateTime.now(),
                  chapterIndex: -1,
                  chapterOffset: 1.0,
                ));
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已标记为看完'), duration: Duration(seconds: 1)),
                  );
                }
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.checkmark_circle, color: neutral.textSecondary, size: 16),
                const SizedBox(width: 6),
                Text(
                  '标记已看',
                  style: TextStyle(
                    fontSize: 14,
                    color: neutral.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 演职人员横向滚动列表
  Widget _buildCastSection(NeutralPalette neutral) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '演职人员',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: neutral.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tmdbCredits!.cast.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final cast = _tmdbCredits!.cast[index];
                final avatarUrl = cast.profilePath != null
                    ? TMDBService.posterUrl(cast.profilePath, size: 'w185')
                    : null;
                return SizedBox(
                  width: 60,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 60,
                          height: 60,
                          color: neutral.surfaceElevated,
                          child: avatarUrl != null
                              ? Image.network(
                                  avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(
                                      CupertinoIcons.person_fill,
                                      color: neutral.textTertiary,
                                      size: 24,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(
                                    CupertinoIcons.person_fill,
                                    color: neutral.textTertiary,
                                    size: 24,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cast.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: neutral.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      if (cast.character != null && cast.character!.isNotEmpty)
                        Text(
                          cast.character!,
                          style: TextStyle(
                            fontSize: 10,
                            color: neutral.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
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
}

/// 可展开简介
class _ExpandableDescription extends StatefulWidget {
  final String text;
  final NeutralPalette neutral;

  const _ExpandableDescription({required this.text, required this.neutral});

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(
            widget.text,
            style: TextStyle(
              fontSize: 14,
              color: widget.neutral.textSecondary,
              height: 1.5,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          secondChild: Text(
            widget.text,
            style: TextStyle(
              fontSize: 14,
              color: widget.neutral.textSecondary,
              height: 1.5,
            ),
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const SizedBox(height: 4),
        Pressable(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Text(
            _isExpanded ? '收起' : '展开',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final LibraryItem episode;
  final String label;
  final String? subtitle;
  final ReadingProgress? progress;
  final VoidCallback onTap;

  const _EpisodeTile({
    required this.episode,
    required this.label,
    this.subtitle,
    this.progress,
    required this.onTap,
  });

  bool get _isWatched => progress != null && progress!.percentage >= 0.95;
  bool get _isInProgress => progress != null && progress!.percentage > 0 && progress!.percentage < 0.95;
  double get _progressPercent => progress?.percentage ?? 0.0;

  Widget _buildEpisodeCover(NeutralPalette neutral) {
    final cover = episode.remoteCoverUrl ?? episode.coverPath;
    if (cover != null) {
      if (cover.startsWith('http://') || cover.startsWith('https://')) {
        return Image.network(
          cover,
          fit: BoxFit.cover,
          width: 120,
          height: 68,
          errorBuilder: (_, __, ___) => _defaultEpisodeCover(neutral),
        );
      }
      return Image.file(
        File(cover),
        fit: BoxFit.cover,
        width: 120,
        height: 68,
        cacheWidth: 300,
        errorBuilder: (_, __, ___) => _defaultEpisodeCover(neutral),
      );
    }
    return _defaultEpisodeCover(neutral);
  }

  Widget _defaultEpisodeCover(NeutralPalette neutral) {
    return Center(
      child: Icon(
        CupertinoIcons.play_circle,
        color: neutral.textTertiary,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: neutral.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Row(
          children: [
            // 缩略图（16:9，带进度条和已看完标记）
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  child: Container(
                    width: 120,
                    height: 68,
                    color: neutral.surface,
                    child: _buildEpisodeCover(neutral),
                  ),
                ),
                // 已看完遮罩
                if (_isWatched)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                // 底部进度条
                if (_isInProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(AppRadius.small),
                          bottomRight: Radius.circular(AppRadius.small),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progressPercent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(AppRadius.small),
                              bottomRight: Radius.circular(AppRadius.small),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
                  if (episode.totalProgress != null && episode.totalProgress! > 0)
                    Text(
                      _formatDuration(episode.totalProgress!),
                      style: TextStyle(
                        fontSize: 12,
                        color: neutral.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.play_circle,
              color: neutral.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
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
}
