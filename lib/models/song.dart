class Song {
  final int? id;
  final String filePath;
  final String? folderPath;
  final String? title;
  final String? artist;
  final String? album;
  final int? duration;
  final int? fileSize;
  final String? coverPath;
  final String? lyricsPath;
  final String? embeddedLyrics;
  final DateTime? createdAt;
  bool isPrivate;

  Song({
    this.id,
    required this.filePath,
    this.folderPath,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.fileSize,
    this.coverPath,
    this.lyricsPath,
    this.embeddedLyrics,
    this.createdAt,
    this.isPrivate = false,
  });

  String get displayTitle => title?.trim().isNotEmpty == true ? title! : _fileName;
  String get displayArtist => artist?.trim().isNotEmpty == true ? artist! : '未知艺术家';
  String get displayAlbum => album?.trim().isNotEmpty == true ? album! : '未知专辑';

  String get _fileName {
    final name = filePath.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'folder_path': folderPath,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'file_size': fileSize,
      'cover_path': coverPath,
      'lyrics_path': lyricsPath,
      'embedded_lyrics': embeddedLyrics,
      'created_at': createdAt != null ? createdAt!.millisecondsSinceEpoch ~/ 1000 : null,
      'isPrivate': isPrivate ? 1 : 0,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as int?,
      filePath: map['file_path'] as String,
      folderPath: map['folder_path'] as String?,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: map['duration'] as int?,
      fileSize: map['file_size'] as int?,
      coverPath: map['cover_path'] as String?,
      lyricsPath: map['lyrics_path'] as String?,
      embeddedLyrics: map['embedded_lyrics'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int) * 1000)
          : null,
      isPrivate: (map['isPrivate'] as int? ?? 0) == 1,
    );
  }

  Song copyWith({
    int? id,
    String? filePath,
    String? folderPath,
    String? title,
    String? artist,
    String? album,
    int? duration,
    int? fileSize,
    String? coverPath,
    String? lyricsPath,
    String? embeddedLyrics,
    DateTime? createdAt,
    bool? isPrivate,
  }) {
    return Song(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      folderPath: folderPath ?? this.folderPath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      coverPath: coverPath ?? this.coverPath,
      lyricsPath: lyricsPath ?? this.lyricsPath,
      embeddedLyrics: embeddedLyrics ?? this.embeddedLyrics,
      createdAt: createdAt ?? this.createdAt,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }
}

class Playlist {
  final int? id;
  final String name;
  final String? coverPath;
  final String? description;
  final DateTime? createdAt;

  Playlist({
    this.id,
    required this.name,
    this.coverPath,
    this.description,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_path': coverPath,
      'description': description,
      'created_at': createdAt != null ? createdAt!.millisecondsSinceEpoch ~/ 1000 : null,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      coverPath: map['cover_path'] as String?,
      description: map['description'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int) * 1000)
          : null,
    );
  }

  Playlist copyWith({
    int? id,
    String? name,
    String? coverPath,
    String? description,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPath: coverPath ?? this.coverPath,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Artist {
  final int? id;
  final String name;
  final String? coverPath;
  final String? description;
  final DateTime? createdAt;

  Artist({
    this.id,
    required this.name,
    this.coverPath,
    this.description,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_path': coverPath,
      'description': description,
      'created_at': createdAt != null ? createdAt!.millisecondsSinceEpoch ~/ 1000 : null,
    };
  }

  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      id: map['id'] as int?,
      name: map['name'] as String,
      coverPath: map['cover_path'] as String?,
      description: map['description'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int) * 1000)
          : null,
    );
  }

  Artist copyWith({
    int? id,
    String? name,
    String? coverPath,
    String? description,
    DateTime? createdAt,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPath: coverPath ?? this.coverPath,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Album {
  final int? id;
  final String name;
  final String? artistNames;
  final String? coverPath;
  final DateTime? createdAt;

  Album({
    this.id,
    required this.name,
    this.artistNames,
    this.coverPath,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'artist_names': artistNames,
      'cover_path': coverPath,
      'created_at': createdAt != null ? createdAt!.millisecondsSinceEpoch ~/ 1000 : null,
    };
  }

  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: map['id'] as int?,
      name: map['name'] as String,
      artistNames: map['artist_names'] as String?,
      coverPath: map['cover_path'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int) * 1000)
          : null,
    );
  }

  Album copyWith({
    int? id,
    String? name,
    String? artistNames,
    String? coverPath,
    DateTime? createdAt,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      artistNames: artistNames ?? this.artistNames,
      coverPath: coverPath ?? this.coverPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
