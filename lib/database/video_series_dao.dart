import 'package:sqflite/sqflite.dart';
import '../models/video_series.dart';
import '../models/video_episode.dart';
import 'database_helper.dart';

class VideoSeriesDao {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ===================== VideoSeries CRUD =====================

  Future<VideoSeries> insertSeries(VideoSeries series) async {
    final db = await _db.database;
    final id = await db.insert('video_series', series.toMap());
    return series.copyWith(id: id);
  }

  Future<List<VideoSeries>> getAllSeries() async {
    final db = await _db.database;
    final maps = await db.query(
      'video_series',
      where: 'isPrivate = 0',
      orderBy: 'lastWatchedAt DESC, updatedAt DESC',
    );
    return maps.map((e) => VideoSeries.fromMap(e)).toList();
  }

  Future<VideoSeries?> getSeriesById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'video_series',
      where: 'id = ? AND isPrivate = 0',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return VideoSeries.fromMap(maps.first);
    return null;
  }

  Future<VideoSeries?> getSeriesByTitle(String title) async {
    final db = await _db.database;
    final maps = await db.query(
      'video_series',
      where: 'title = ? AND isPrivate = 0',
      whereArgs: [title],
    );
    if (maps.isNotEmpty) return VideoSeries.fromMap(maps.first);
    return null;
  }

  Future<int> updateSeries(VideoSeries series) async {
    final db = await _db.database;
    return await db.update(
      'video_series',
      series.toMap(),
      where: 'id = ?',
      whereArgs: [series.id],
    );
  }

  Future<void> toggleFavorite(int seriesId, bool isFavorite) async {
    final db = await _db.database;
    await db.update(
      'video_series',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> updateSeriesCover(int seriesId, String? coverPath) async {
    final db = await _db.database;
    await db.update(
      'video_series',
      {'coverPath': coverPath},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<int> deleteSeries(int id) async {
    final db = await _db.database;
    return await db.delete(
      'video_series',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<VideoSeries>> getPrivateSeries() async {
    final db = await _db.database;
    final maps = await db.query(
      'video_series',
      where: 'isPrivate = 1',
      orderBy: 'lastWatchedAt DESC, updatedAt DESC',
    );
    return maps.map((e) => VideoSeries.fromMap(e)).toList();
  }

  Future<void> setSeriesPrivate(int seriesId, bool isPrivate) async {
    final db = await _db.database;
    await db.update(
      'video_series',
      {'isPrivate': isPrivate ? 1 : 0},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> updateSeriesEpisodeCount(int seriesId) async {
    final db = await _db.database;
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM video_episodes WHERE seriesId = ?',
      [seriesId],
    );
    final watchedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM video_episodes WHERE seriesId = ? AND isWatched = 1',
      [seriesId],
    );
    final total = (totalResult.first['count'] as int? ?? 0);
    final watched = (watchedResult.first['count'] as int? ?? 0);
    await db.update(
      'video_series',
      {'totalEpisodes': total, 'watchedEpisodes': watched},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  // ===================== VideoEpisode CRUD =====================

  Future<VideoEpisode> insertEpisode(VideoEpisode episode) async {
    final db = await _db.database;
    final id = await db.insert('video_episodes', episode.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return episode.copyWith(id: id);
  }

  Future<List<VideoEpisode>> getEpisodesBySeries(int seriesId) async {
    final db = await _db.database;
    final maps = await db.query(
      'video_episodes',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
      orderBy: 'seasonNumber ASC, episodeNumber ASC, title ASC',
    );
    return maps.map((e) => VideoEpisode.fromMap(e)).toList();
  }

  Future<VideoEpisode?> getEpisodeById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'video_episodes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return VideoEpisode.fromMap(maps.first);
    return null;
  }

  Future<VideoEpisode?> getEpisodeByFilePath(String filePath) async {
    final db = await _db.database;
    final maps = await db.query(
      'video_episodes',
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (maps.isNotEmpty) return VideoEpisode.fromMap(maps.first);
    return null;
  }

  Future<int> updateEpisode(VideoEpisode episode) async {
    final db = await _db.database;
    return await db.update(
      'video_episodes',
      episode.toMap(),
      where: 'id = ?',
      whereArgs: [episode.id],
    );
  }

  Future<void> markEpisodeWatched(int episodeId, bool watched) async {
    final db = await _db.database;
    await db.update(
      'video_episodes',
      {'isWatched': watched ? 1 : 0},
      where: 'id = ?',
      whereArgs: [episodeId],
    );
  }

  Future<void> updateEpisodeProgress(int episodeId, Duration position, double percentage) async {
    final db = await _db.database;
    await db.update(
      'video_episodes',
      {
        'position': position.inSeconds,
        'percentage': percentage,
      },
      where: 'id = ?',
      whereArgs: [episodeId],
    );
  }

  Future<int> deleteEpisode(int id) async {
    final db = await _db.database;
    return await db.delete(
      'video_episodes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEpisodesBySeries(int seriesId) async {
    final db = await _db.database;
    await db.delete(
      'video_episodes',
      where: 'seriesId = ?',
      whereArgs: [seriesId],
    );
  }
}

extension on VideoEpisode {
  VideoEpisode copyWith({
    int? id,
    int? seriesId,
    String? title,
    String? filePath,
    int? seasonNumber,
    int? episodeNumber,
    int? fileSize,
    Duration? duration,
    Duration? position,
    double? percentage,
    bool? isWatched,
    DateTime? createdAt,
  }) {
    return VideoEpisode(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      percentage: percentage ?? this.percentage,
      isWatched: isWatched ?? this.isWatched,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
