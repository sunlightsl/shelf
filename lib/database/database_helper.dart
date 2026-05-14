import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../services/app_directories.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      try {
        // 检测连接是否仍存活，若已关闭则重新初始化
        await _database!.rawQuery('SELECT 1');
        return _database!;
      } catch (_) {
        _database = null;
      }
    }
    _database = await _initDB('local_library.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final path = AppDirectories.databasePath;

    // 检查数据库文件是否存在但表结构不完整（残留的空文件或损坏文件）
    final dbFile = File(path);
    if (await dbFile.exists()) {
      var isValid = false;
      try {
        final testDb = await openDatabase(path, readOnly: true, singleInstance: false);
        final tables = await testDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='library_items'",
        );
        await testDb.close();
        isValid = tables.isNotEmpty;
      } catch (_) {
        isValid = false;
      }
      if (!isValid) {
        // 使用 sqflite 的 deleteDatabase 而非 File.delete()，
        // 可正确清理 journal/WAL 文件并处理已打开的连接
        try {
          await deleteDatabase(path);
        } catch (_) {
          // 忽略删除失败
        }
      }
    }

    return await openDatabase(
      path,
      version: 16,
      onCreate: _createDB,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // 防御：若之前迁移中断导致某些表缺失，在此兜底创建
        await _ensureTablesExist(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE reading_progress ADD COLUMN chapterIndex INTEGER NOT NULL DEFAULT -1');
          await db.execute('ALTER TABLE reading_progress ADD COLUMN chapterOffset REAL NOT NULL DEFAULT -1.0');
        }
        if (oldVersion < 3) {
          await _createComicTables(db);
        }
        if (oldVersion < 4) {
          final columns = await db.rawQuery("PRAGMA table_info(comic_chapters)");
          final hasCoverPath = columns.any((c) => c['name'] == 'coverPath');
          if (!hasCoverPath) {
            await db.execute('ALTER TABLE comic_chapters ADD COLUMN coverPath TEXT');
          }
        }
        if (oldVersion < 5) {
          await _createMusicTables(db);
        }
        if (oldVersion < 6) {
          await _migrateV5ToV6(db);
        }
        if (oldVersion < 7) {
          final libraryCols = await db.rawQuery("PRAGMA table_info(library_items)");
          if (!libraryCols.any((c) => c['name'] == 'deletedAt')) {
            await db.execute('ALTER TABLE library_items ADD COLUMN deletedAt TEXT');
          }
          final seriesCols = await db.rawQuery("PRAGMA table_info(comic_series)");
          if (!seriesCols.any((c) => c['name'] == 'deletedAt')) {
            await db.execute('ALTER TABLE comic_series ADD COLUMN deletedAt TEXT');
          }
        }
        if (oldVersion < 8) {
          final columns = await db.rawQuery("PRAGMA table_info(songs)");
          final hasFolderPath = columns.any((c) => c['name'] == 'folder_path');
          if (!hasFolderPath) {
            await db.execute('ALTER TABLE songs ADD COLUMN folder_path TEXT');
          }
        }
        if (oldVersion < 9) {
          await _migrateV8ToV9(db);
        }
        if (oldVersion < 10) {
          await _migrateV9ToV10(db);
        }
        if (oldVersion < 11) {
          await _migrateV10ToV11(db);
        }
        if (oldVersion < 12) {
          await _migrateV11ToV12(db);
        }
        if (oldVersion < 13) {
          await _migrateV12ToV13(db);
        }
        if (oldVersion < 14) {
          await _migrateV13ToV14(db);
        }
        if (oldVersion < 15) {
          await _createVideoTables(db);
        }
        if (oldVersion < 16) {
          await _migrateV15ToV16(db);
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE library_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        mediaType INTEGER NOT NULL,
        format INTEGER NOT NULL,
        filePath TEXT NOT NULL UNIQUE,
        relativeFolderPath TEXT,
        coverPath TEXT,
        author TEXT,
        description TEXT,
        tags TEXT,
        addedDate TEXT NOT NULL,
        lastOpenedDate TEXT,
        fileSize INTEGER,
        totalProgress INTEGER,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        isPrivate INTEGER NOT NULL DEFAULT 0,
        deletedAt TEXT,
        sourceType TEXT,
        sourceAccountId TEXT,
        remoteId TEXT,
        remoteCoverUrl TEXT,
        streamUrl TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemId INTEGER NOT NULL,
        position INTEGER NOT NULL,
        positionText TEXT NOT NULL,
        percentage REAL NOT NULL DEFAULT 0,
        lastReadAt TEXT NOT NULL,
        deviceId TEXT,
        chapterIndex INTEGER NOT NULL DEFAULT -1,
        chapterOffset REAL NOT NULL DEFAULT -1.0,
        FOREIGN KEY (itemId) REFERENCES library_items (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemId INTEGER NOT NULL,
        position INTEGER NOT NULL,
        positionText TEXT NOT NULL,
        note TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (itemId) REFERENCES library_items (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_library_items_mediaType ON library_items(mediaType)
    ''');

    await db.execute('''
      CREATE INDEX idx_library_items_lastOpened ON library_items(lastOpenedDate)
    ''');

    await db.execute('''
      CREATE INDEX idx_reading_progress_itemId ON reading_progress(itemId)
    ''');

    await _createComicTables(db);
    await _createMusicTables(db);
    await _createOfflineCacheTable(db);
    await _createBookParsingRulesTable(db);
    await _createVideoTables(db);

    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createComicTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        folderPath TEXT,
        coverPath TEXT,
        author TEXT,
        description TEXT,
        status INTEGER DEFAULT 0,
        totalChapters INTEGER DEFAULT 0,
        readChapters INTEGER DEFAULT 0,
        isFavorite INTEGER DEFAULT 0,
        isPrivate INTEGER NOT NULL DEFAULT 0,
        tags TEXT,
        sourceType INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s','now')),
        updatedAt INTEGER,
        lastReadAt INTEGER,
        deletedAt INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seriesId INTEGER NOT NULL,
        title TEXT,
        chapterNumber REAL,
        volumeNumber INTEGER,
        filePath TEXT NOT NULL,
        format INTEGER,
        pageCount INTEGER DEFAULT 0,
        fileSize INTEGER,
        sortOrder INTEGER DEFAULT 0,
        isRead INTEGER DEFAULT 0,
        coverPath TEXT,
        createdAt INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(seriesId, filePath),
        FOREIGN KEY (seriesId) REFERENCES comic_series (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comic_reading_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seriesId INTEGER NOT NULL,
        chapterId INTEGER,
        currentPage INTEGER DEFAULT 0,
        totalPages INTEGER DEFAULT 0,
        percentage REAL DEFAULT 0,
        lastReadAt INTEGER DEFAULT (strftime('%s','now')),
        UNIQUE(seriesId),
        FOREIGN KEY (seriesId) REFERENCES comic_series (id) ON DELETE CASCADE,
        FOREIGN KEY (chapterId) REFERENCES comic_chapters (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_comic_chapters_seriesId ON comic_chapters(seriesId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_comic_reading_progress_seriesId ON comic_reading_progress(seriesId)
    ''');
  }

  Future _createMusicTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        folder_path TEXT,
        title TEXT,
        artist TEXT,
        album TEXT,
        duration INTEGER,
        file_size INTEGER,
        cover_path TEXT,
        lyrics_path TEXT,
        embedded_lyrics TEXT,
        isPrivate INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        cover_path TEXT,
        description TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS artists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        cover_path TEXT,
        description TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        artist_names TEXT,
        cover_path TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_songs (
        playlist_id INTEGER REFERENCES playlists(id) ON DELETE CASCADE,
        song_id INTEGER REFERENCES songs(id) ON DELETE CASCADE,
        sort_order INTEGER DEFAULT 0,
        PRIMARY KEY (playlist_id, song_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS song_favorites (
        song_id INTEGER PRIMARY KEY REFERENCES songs(id) ON DELETE CASCADE,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS play_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id INTEGER REFERENCES songs(id) ON DELETE CASCADE,
        played_at INTEGER,
        play_duration INTEGER,
        completed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS player_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_songs_artist ON songs(artist)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_songs_album ON songs(album)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_play_history_song ON play_history(song_id)
    ''');
  }

  Future _migrateV5ToV6(Database db) async {
    await db.execute('DROP TABLE IF EXISTS play_history_new');
    await db.execute('''
      CREATE TABLE play_history_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id INTEGER REFERENCES songs(id) ON DELETE CASCADE,
        played_at INTEGER,
        play_duration INTEGER,
        completed INTEGER DEFAULT 0
      )
    ''');
    await db.execute('INSERT INTO play_history_new SELECT * FROM play_history');
    await db.execute('DROP TABLE play_history');
    await db.execute('ALTER TABLE play_history_new RENAME TO play_history');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_play_history_song ON play_history(song_id)');
  }

  Future _migrateV8ToV9(Database db) async {
    // 扩展 playlists 表
    final playlistCols = await db.rawQuery("PRAGMA table_info(playlists)");
    final hasPlaylistCover = playlistCols.any((c) => c['name'] == 'cover_path');
    final hasPlaylistDesc = playlistCols.any((c) => c['name'] == 'description');
    if (!hasPlaylistCover) {
      await db.execute('ALTER TABLE playlists ADD COLUMN cover_path TEXT');
    }
    if (!hasPlaylistDesc) {
      await db.execute('ALTER TABLE playlists ADD COLUMN description TEXT');
    }

    // 创建 artists 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS artists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        cover_path TEXT,
        description TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    // 创建 albums 表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        artist_names TEXT,
        cover_path TEXT,
        created_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');
  }

  Future _migrateV9ToV10(Database db) async {
    // 补全可能被之前失败 migration 遗漏的 deletedAt 字段
    final libraryCols = await db.rawQuery("PRAGMA table_info(library_items)");
    if (!libraryCols.any((c) => c['name'] == 'deletedAt')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN deletedAt TEXT');
    }
    final seriesCols = await db.rawQuery("PRAGMA table_info(comic_series)");
    if (!seriesCols.any((c) => c['name'] == 'deletedAt')) {
      await db.execute('ALTER TABLE comic_series ADD COLUMN deletedAt TEXT');
    }
  }

  Future _migrateV10ToV11(Database db) async {
    final libraryCols = await db.rawQuery("PRAGMA table_info(library_items)");
    if (!libraryCols.any((c) => c['name'] == 'isPrivate')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN isPrivate INTEGER NOT NULL DEFAULT 0');
    }
    final seriesCols = await db.rawQuery("PRAGMA table_info(comic_series)");
    if (!seriesCols.any((c) => c['name'] == 'isPrivate')) {
      await db.execute('ALTER TABLE comic_series ADD COLUMN isPrivate INTEGER NOT NULL DEFAULT 0');
    }
    final songCols = await db.rawQuery("PRAGMA table_info(songs)");
    if (!songCols.any((c) => c['name'] == 'isPrivate')) {
      await db.execute('ALTER TABLE songs ADD COLUMN isPrivate INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// 版本 11 → 12：数据库安全加固
  /// 1. library_items 重建，添加 filePath UNIQUE 约束
  /// 2. library_items 新增 relativeFolderPath 字段
  /// 3. comic_chapters 新增 deletedAt 字段
  Future _migrateV11ToV12(Database db) async {
    // 关闭外键检查，以便重建被引用的表
    await db.execute('PRAGMA foreign_keys = OFF');

    try {
      // ─── 重建 library_items 表 ───
      await db.execute('''
        CREATE TABLE library_items_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          mediaType INTEGER NOT NULL,
          format INTEGER NOT NULL,
          filePath TEXT NOT NULL UNIQUE,
          relativeFolderPath TEXT,
          coverPath TEXT,
          author TEXT,
          description TEXT,
          tags TEXT,
          addedDate TEXT NOT NULL,
          lastOpenedDate TEXT,
          fileSize INTEGER,
          totalProgress INTEGER,
          isFavorite INTEGER NOT NULL DEFAULT 0,
          isPrivate INTEGER NOT NULL DEFAULT 0,
          deletedAt TEXT
        )
      ''');

      // 迁移数据：按 filePath 去重，保留最新记录（id 最大）
      // 必须显式列名：旧表没有 relativeFolderPath，新表有，不能 SELECT *
      await db.execute('''
        INSERT INTO library_items_new (
          id, title, mediaType, format, filePath,
          coverPath, author, description, tags, addedDate, lastOpenedDate,
          fileSize, totalProgress, isFavorite, isPrivate, deletedAt
        )
        SELECT
          id, title, mediaType, format, filePath,
          coverPath, author, description, tags, addedDate, lastOpenedDate,
          fileSize, totalProgress, isFavorite, isPrivate, deletedAt
        FROM library_items
        WHERE id IN (
          SELECT MAX(id) FROM library_items GROUP BY filePath
        )
      ''');

      // 删除旧表（外键检查已关闭，不会级联删除 reading_progress/bookmarks）
      await db.execute('DROP TABLE IF EXISTS library_items');

      // 重命名新表
      await db.execute('ALTER TABLE library_items_new RENAME TO library_items');

      // 重建索引
      await db.execute('CREATE INDEX idx_library_items_mediaType ON library_items(mediaType)');
      await db.execute('CREATE INDEX idx_library_items_lastOpened ON library_items(lastOpenedDate)');

      // 清理孤儿记录（reading_progress/bookmarks 中引用了被删除的 library_items 记录）
      await db.execute('''
        DELETE FROM reading_progress
        WHERE itemId NOT IN (SELECT id FROM library_items)
      ''');
      await db.execute('''
        DELETE FROM bookmarks
        WHERE itemId NOT IN (SELECT id FROM library_items)
      ''');

      // ─── comic_chapters 添加 deletedAt ───
      final chapterCols = await db.rawQuery("PRAGMA table_info(comic_chapters)");
      if (!chapterCols.any((c) => c['name'] == 'deletedAt')) {
        await db.execute('ALTER TABLE comic_chapters ADD COLUMN deletedAt INTEGER');
      }
    } finally {
      // 重新开启外键检查
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future _createOfflineCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filePath TEXT NOT NULL UNIQUE,
        mediaType INTEGER NOT NULL,
        fileSize INTEGER NOT NULL DEFAULT 0,
        downloadedAt INTEGER NOT NULL,
        lastAccessedAt INTEGER NOT NULL,
        keepOffline INTEGER NOT NULL DEFAULT 0,
        accountId TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_cache_mediaType ON offline_cache(mediaType)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_offline_cache_accessed ON offline_cache(lastAccessedAt)
    ''');
  }

  Future _migrateV12ToV13(Database db) async {
    await _createOfflineCacheTable(db);
  }

  Future _migrateV13ToV14(Database db) async {
    await _createBookParsingRulesTable(db);
    // 防御：若之前创建的表缺少 chapterEdits 字段
    final cols = await db.rawQuery("PRAGMA table_info(book_parsing_rules)");
    if (!cols.any((c) => c['name'] == 'chapterEdits')) {
      await db.execute('ALTER TABLE book_parsing_rules ADD COLUMN chapterEdits TEXT');
    }
  }

  Future _createBookParsingRulesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_parsing_rules (
        itemId INTEGER PRIMARY KEY,
        enabledChapterRules TEXT,
        textEncoding INTEGER,
        chineseConversion INTEGER,
        chapterEdits TEXT,
        FOREIGN KEY (itemId) REFERENCES library_items (id) ON DELETE CASCADE
      )
    ''');
  }

  /// 版本 15 → 16：云端媒体元数据支持
  /// 给 library_items 新增 sourceType / sourceAccountId / remoteId / remoteCoverUrl / streamUrl
  Future _migrateV15ToV16(Database db) async {
    final columns = await db.rawQuery("PRAGMA table_info(library_items)");
    final colNames = columns.map((c) => c['name'] as String).toSet();
    if (!colNames.contains('sourceType')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN sourceType TEXT');
    }
    if (!colNames.contains('sourceAccountId')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN sourceAccountId TEXT');
    }
    if (!colNames.contains('remoteId')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN remoteId TEXT');
    }
    if (!colNames.contains('remoteCoverUrl')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN remoteCoverUrl TEXT');
    }
    if (!colNames.contains('streamUrl')) {
      await db.execute('ALTER TABLE library_items ADD COLUMN streamUrl TEXT');
    }
  }

  /// 视频剧集/分集表（与 VideoSeriesDao 模型对齐）
  Future _createVideoTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        folderPath TEXT,
        coverPath TEXT,
        description TEXT,
        totalEpisodes INTEGER DEFAULT 0,
        watchedEpisodes INTEGER DEFAULT 0,
        isFavorite INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER,
        lastWatchedAt INTEGER,
        isPrivate INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seriesId INTEGER NOT NULL,
        title TEXT NOT NULL,
        filePath TEXT NOT NULL,
        seasonNumber INTEGER,
        episodeNumber INTEGER,
        fileSize INTEGER,
        duration INTEGER,
        position INTEGER,
        percentage REAL,
        isWatched INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (seriesId) REFERENCES video_series (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_video_episodes_seriesId ON video_episodes(seriesId)
    ''');
  }

  /// 防御性兜底：确保所有预期表存在（处理之前迁移中断的残留数据库）
  Future _ensureTablesExist(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tables.map((t) => t['name'] as String).toSet();

    if (!tableNames.contains('library_items')) {
      await db.execute('''
        CREATE TABLE library_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          mediaType INTEGER NOT NULL,
          format INTEGER NOT NULL,
          filePath TEXT NOT NULL UNIQUE,
          relativeFolderPath TEXT,
          coverPath TEXT,
          author TEXT,
          description TEXT,
          tags TEXT,
          addedDate TEXT NOT NULL,
          lastOpenedDate TEXT,
          fileSize INTEGER,
          totalProgress INTEGER,
          isFavorite INTEGER NOT NULL DEFAULT 0,
          isPrivate INTEGER NOT NULL DEFAULT 0,
          deletedAt TEXT,
          sourceType TEXT,
          sourceAccountId TEXT,
          remoteId TEXT,
          remoteCoverUrl TEXT,
          streamUrl TEXT
        )
      ''');
      await db.execute('CREATE INDEX idx_library_items_mediaType ON library_items(mediaType)');
      await db.execute('CREATE INDEX idx_library_items_lastOpened ON library_items(lastOpenedDate)');
    }

    if (!tableNames.contains('reading_progress')) {
      await db.execute('''
        CREATE TABLE reading_progress (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itemId INTEGER NOT NULL,
          position INTEGER NOT NULL,
          positionText TEXT NOT NULL,
          percentage REAL NOT NULL DEFAULT 0,
          lastReadAt TEXT NOT NULL,
          deviceId TEXT,
          chapterIndex INTEGER NOT NULL DEFAULT -1,
          chapterOffset REAL NOT NULL DEFAULT -1.0,
          FOREIGN KEY (itemId) REFERENCES library_items (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX idx_reading_progress_itemId ON reading_progress(itemId)');
    }

    if (!tableNames.contains('bookmarks')) {
      await db.execute('''
        CREATE TABLE bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          itemId INTEGER NOT NULL,
          position INTEGER NOT NULL,
          positionText TEXT NOT NULL,
          note TEXT,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (itemId) REFERENCES library_items (id) ON DELETE CASCADE
        )
      ''');
    }

    if (!tableNames.contains('comic_series')) {
      await _createComicTables(db);
    }

    if (!tableNames.contains('songs')) {
      await _createMusicTables(db);
    }

    if (!tableNames.contains('offline_cache')) {
      await _createOfflineCacheTable(db);
    }

    if (!tableNames.contains('book_parsing_rules')) {
      await _createBookParsingRulesTable(db);
    }

    if (!tableNames.contains('video_series')) {
      await _createVideoTables(db);
    }
  }

  Future close() async {
    final db = await instance.database;
    await db.close();
    _database = null;
  }
}
