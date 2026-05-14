import 'package:sqflite/sqflite.dart';
import '../models/song.dart';
import 'database_helper.dart';

class SongDao {
  final DatabaseHelper _helper = DatabaseHelper.instance;

  Future<int> insertSong(Song song) async {
    final db = await _helper.database;
    final existing = await db.query('songs', columns: ['id'], where: 'file_path = ?', whereArgs: [song.filePath]);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('songs', song.toMap()..remove('id'), where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('songs', song.toMap());
  }

  Future<void> insertSongs(List<Song> songs) async {
    final db = await _helper.database;
    final all = await db.query('songs', columns: ['id', 'file_path']);
    final pathToId = <String, int>{};
    for (final row in all) {
      pathToId[row['file_path'] as String] = row['id'] as int;
    }

    final batch = db.batch();
    final seenPaths = <String>{};
    for (final song in songs) {
      // 跳过同一批次中重复的路径，避免 UNIQUE 约束冲突
      if (!seenPaths.add(song.filePath)) continue;

      final existingId = pathToId[song.filePath];
      final map = song.toMap()..remove('id');
      if (existingId != null) {
        batch.update('songs', map, where: 'id = ?', whereArgs: [existingId]);
      } else {
        batch.insert('songs', map);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<Song>> getAllSongs() async {
    final db = await _helper.database;
    final maps = await db.query('songs', where: 'isPrivate = 0', orderBy: 'title COLLATE NOCASE');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  /// 获取所有私密歌曲
  Future<List<Song>> getPrivateSongs() async {
    final db = await _helper.database;
    final maps = await db.query('songs', where: 'isPrivate = 1', orderBy: 'title COLLATE NOCASE');
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<void> setSongPrivate(int songId, bool isPrivate) async {
    final db = await _helper.database;
    await db.update(
      'songs',
      {'isPrivate': isPrivate ? 1 : 0},
      where: 'id = ?',
      whereArgs: [songId],
    );
  }

  Future<List<Song>> getSongsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await _helper.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final maps = await db.rawQuery(
      'SELECT * FROM songs WHERE id IN ($placeholders) AND isPrivate = 0',
      ids.map((id) => id.toString()).toList(),
    );
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<Song?> getSongById(int id) async {
    final db = await _helper.database;
    final maps = await db.query('songs', where: 'id = ? AND isPrivate = 0', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Song.fromMap(maps.first);
  }

  Future<Song?> getSongByPath(String filePath) async {
    final db = await _helper.database;
    final maps = await db.query('songs', where: 'file_path = ? AND isPrivate = 0', whereArgs: [filePath], limit: 1);
    if (maps.isEmpty) return null;
    return Song.fromMap(maps.first);
  }

  Future<void> deleteSong(int id) async {
    final db = await _helper.database;
    await db.delete('songs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSongsByPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final db = await _helper.database;
    final placeholders = List.filled(paths.length, '?').join(',');
    await db.rawDelete('DELETE FROM songs WHERE file_path IN ($placeholders)', paths);
  }

  Future<void> updateSongCover(int id, String coverPath) async {
    final db = await _helper.database;
    await db.update('songs', {'cover_path': coverPath}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSongMetadata(Song song) async {
    final db = await _helper.database;
    if (song.id != null) {
      await db.update(
        'songs',
        {
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'duration': song.duration,
          'cover_path': song.coverPath,
          'embedded_lyrics': song.embeddedLyrics,
        },
        where: 'id = ?',
        whereArgs: [song.id],
      );
    }
  }

  Future<void> updateSongPath(String oldPath, String newPath, String newFolderPath) async {
    final db = await _helper.database;
    await db.update(
      'songs',
      {
        'file_path': newPath,
        'folder_path': newFolderPath,
      },
      where: 'file_path = ?',
      whereArgs: [oldPath],
    );
  }

  // 收藏
  Future<void> toggleFavorite(int songId) async {
    final db = await _helper.database;
    final existing = await db.query('song_favorites', where: 'song_id = ?', whereArgs: [songId]);
    if (existing.isEmpty) {
      await db.insert('song_favorites', {'song_id': songId});
    } else {
      await db.delete('song_favorites', where: 'song_id = ?', whereArgs: [songId]);
    }
  }

  Future<bool> isFavorite(int songId) async {
    final db = await _helper.database;
    final result = await db.query('song_favorites', where: 'song_id = ?', whereArgs: [songId]);
    return result.isNotEmpty;
  }

  Future<List<int>> getFavoriteSongIds() async {
    final db = await _helper.database;
    final maps = await db.query('song_favorites');
    return maps.map((m) => m['song_id'] as int).toList();
  }

  // 播放历史
  Future<void> addPlayHistory(int songId, int playDurationMs, bool completed) async {
    final db = await _helper.database;
    await db.insert('play_history', {
      'song_id': songId,
      'played_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'play_duration': playDurationMs,
      'completed': completed ? 1 : 0,
    });
  }

  Future<List<int>> getRecentSongIds({int limit = 50}) async {
    final db = await _helper.database;
    final maps = await db.rawQuery(
      '''
      SELECT ph.song_id, MAX(ph.played_at) as max_time
      FROM play_history ph
      INNER JOIN songs s ON ph.song_id = s.id
      WHERE s.isPrivate = 0
      GROUP BY ph.song_id
      ORDER BY max_time DESC
      LIMIT ?
      ''',
      [limit],
    );
    return maps.map((m) => m['song_id'] as int).toList();
  }

  /// 获取所有歌曲的最后播放时间
  Future<Map<int, DateTime>> getAllLastPlayedTimes() async {
    final db = await _helper.database;
    final maps = await db.rawQuery(
      '''
      SELECT song_id, MAX(played_at) as max_time
      FROM play_history
      GROUP BY song_id
      '''
    );
    final result = <int, DateTime>{};
    for (final map in maps) {
      final songId = map['song_id'] as int;
      final timestamp = map['max_time'] as int;
      result[songId] = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }
    return result;
  }

  // 播放器状态持久化
  Future<void> savePlayerState(String key, String value) async {
    final db = await _helper.database;
    await db.insert('player_state', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getPlayerState(String key) async {
    final db = await _helper.database;
    final maps = await db.query('player_state', where: 'key = ?', whereArgs: [key], limit: 1);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  // 歌单
  Future<int> createPlaylist(String name) async {
    final db = await _helper.database;
    return db.insert('playlists', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  Future<void> deletePlaylist(int id) async {
    final db = await _helper.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renamePlaylist(int id, String name) async {
    final db = await _helper.database;
    await db.update('playlists', {'name': name}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _helper.database;
    final maps = await db.query('playlists', orderBy: 'created_at DESC');
    return maps.map((m) => Playlist.fromMap(m)).toList();
  }

  Future<void> addSongToPlaylist(int playlistId, int songId) async {
    final db = await _helper.database;
    await db.insert(
      'playlist_songs',
      {'playlist_id': playlistId, 'song_id': songId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final db = await _helper.database;
    await db.delete(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
  }

  Future<List<Song>> getPlaylistSongs(int playlistId) async {
    final db = await _helper.database;
    final maps = await db.rawQuery('''
      SELECT s.* FROM songs s
      INNER JOIN playlist_songs ps ON s.id = ps.song_id
      WHERE ps.playlist_id = ? AND s.isPrivate = 0
      ORDER BY ps.sort_order ASC
    ''', [playlistId]);
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  Future<bool> isSongInPlaylist(int playlistId, int songId) async {
    final db = await _helper.database;
    final result = await db.query(
      'playlist_songs',
      where: 'playlist_id = ? AND song_id = ?',
      whereArgs: [playlistId, songId],
    );
    return result.isNotEmpty;
  }

  // ===================== 文件夹浏览 =====================

  /// 获取所有唯一的文件夹路径
  Future<List<String>> getAllFolders() async {
    final db = await _helper.database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT folder_path FROM songs WHERE folder_path IS NOT NULL AND isPrivate = 0 ORDER BY folder_path COLLATE NOCASE'
    );
    return maps.map((m) => m['folder_path'] as String).toList();
  }

  /// 获取指定文件夹下的所有歌曲
  Future<List<Song>> getSongsByFolder(String folderPath) async {
    final db = await _helper.database;
    final maps = await db.query(
      'songs',
      where: 'folder_path = ? AND isPrivate = 0',
      whereArgs: [folderPath],
      orderBy: 'title COLLATE NOCASE',
    );
    return maps.map((m) => Song.fromMap(m)).toList();
  }

  /// 搜索文件夹（按路径关键词）
  Future<List<String>> searchFolders(String keyword) async {
    final db = await _helper.database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT folder_path FROM songs WHERE folder_path LIKE ? AND isPrivate = 0 ORDER BY folder_path COLLATE NOCASE',
      ['%$keyword%']
    );
    return maps.map((m) => m['folder_path'] as String).toList();
  }

  // ===================== 歌单封面/简介 =====================

  Future<void> updatePlaylistCover(int id, String? coverPath) async {
    final db = await _helper.database;
    await db.update('playlists', {'cover_path': coverPath}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePlaylistDescription(int id, String? description) async {
    final db = await _helper.database;
    await db.update('playlists', {'description': description}, where: 'id = ?', whereArgs: [id]);
  }

  // ===================== 艺术家 =====================

  Future<Artist?> getArtistByName(String name) async {
    final db = await _helper.database;
    final maps = await db.query('artists', where: 'name = ?', whereArgs: [name], limit: 1);
    if (maps.isEmpty) return null;
    return Artist.fromMap(maps.first);
  }

  Future<Artist> getOrCreateArtist(String name) async {
    final existing = await getArtistByName(name);
    if (existing != null) return existing;
    final db = await _helper.database;
    final id = await db.insert('artists', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return Artist(id: id, name: name);
  }

  Future<void> updateArtistCover(int id, String? coverPath) async {
    final db = await _helper.database;
    await db.update('artists', {'cover_path': coverPath}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateArtistDescription(int id, String? description) async {
    final db = await _helper.database;
    await db.update('artists', {'description': description}, where: 'id = ?', whereArgs: [id]);
  }

  // ===================== 专辑 =====================

  Future<Album?> getAlbumByName(String name) async {
    final db = await _helper.database;
    final maps = await db.query('albums', where: 'name = ?', whereArgs: [name], limit: 1);
    if (maps.isEmpty) return null;
    return Album.fromMap(maps.first);
  }

  Future<Album> getOrCreateAlbum(String name, {String? artistNames, String? coverPath}) async {
    final existing = await getAlbumByName(name);
    if (existing != null) return existing;
    final db = await _helper.database;
    final id = await db.insert('albums', {
      'name': name,
      'artist_names': artistNames,
      'cover_path': coverPath,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    return Album(id: id, name: name, artistNames: artistNames, coverPath: coverPath);
  }

  Future<void> updateAlbumCover(int id, String? coverPath) async {
    final db = await _helper.database;
    await db.update('albums', {'cover_path': coverPath}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllData() async {
    final db = await _helper.database;
    await db.delete('songs');
    await db.delete('playlists');
    await db.delete('playlist_songs');
    await db.delete('song_favorites');
    await db.delete('play_history');
    await db.delete('player_state');
    await db.delete('artists');
    await db.delete('albums');
    await db.execute("DELETE FROM sqlite_sequence WHERE name='songs'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='playlists'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='artists'");
    await db.execute("DELETE FROM sqlite_sequence WHERE name='albums'");
  }
}
