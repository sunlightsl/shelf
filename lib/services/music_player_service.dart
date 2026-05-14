import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import '../models/song.dart';
import '../database/song_dao.dart';
import '../database/library_dao.dart';
import 'music_player_settings.dart';
import 'offline_cache_service.dart';

enum PlayMode { loopAll, loopOne, shuffle }

class MusicPlayerService extends ChangeNotifier {
  static final MusicPlayerService instance = MusicPlayerService._internal();

  late final AndroidEqualizer _equalizer;
  late final AudioPlayer _player;
  final SongDao _dao = SongDao();
  final LibraryDao _libraryDao = LibraryDao();

  MusicPlayerService._internal() {
    if (Platform.isAndroid) {
      _equalizer = AndroidEqualizer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: [_equalizer],
        ),
      );
    } else {
      _player = AudioPlayer();
    }
  }

  List<Song> _queue = [];
  List<Song> get queue => List.unmodifiable(_queue);

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  Song? get currentSong => _queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;

  bool get isPlaying => _player.playing;
  bool get hasQueue => _queue.isNotEmpty;

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;

  PlayMode _playMode = PlayMode.loopAll;
  PlayMode get playMode => _playMode;

  double _speed = 1.0;
  double get speed => _speed;

  List<int> _shuffleIndices = [];

  // Streams
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get processingStateStream => _player.processingStateStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  bool _initialized = false;
  bool _disposed = false;
  Timer? _fadeTimer;
  Timer? _saveDebounceTimer;
  StreamSubscription<ProcessingState>? _processingStateSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 音频焦点被占用时自动暂停/恢复音量
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume((_player.volume * 0.5).clamp(0.0, 1.0));
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_player.playing) pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume((_player.volume * 2.0).clamp(0.0, 1.0));
            break;
          default:
            break;
        }
      }
    });

    // 耳机拔出时自动暂停
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) pause();
    });

    _processingStateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onCompleted();
      }
    });

    _currentIndexSub = _player.currentIndexStream.listen((index) async {
      if (index != null) {
        _currentIndex = index;
        final song = currentSong;
        if (song != null) {
          final item = await _libraryDao.getItemByPath(song.filePath);
          if (item?.id != null) {
            await _libraryDao.updateLastOpened(item!.id!);
          }
        }
        _debouncedSaveState();
        notifyListeners();
      }
    });

    // 播放状态变化时通知 UI（确保 just_audio 内部状态稳定后再通知）
    _playingSub = _player.playingStream.listen((playing) {
      notifyListeners();
    });

    // 播放位置变化时自动保存（debounce 5秒）
    _positionSub = _player.positionStream.listen((_) {
      _debouncedSaveState();
    });

    await _restoreState();
    await _restoreEqualizer();
  }

  AudioSource _buildAudioSource(Song song, {String? lyric}) {
    final file = File(song.filePath);
    if (!file.existsSync()) {
      debugPrint('音频文件不存在: ${song.filePath}');
    }
    return AudioSource.file(
      song.filePath,
      tag: MediaItem(
        id: song.id?.toString() ?? song.filePath,
        title: song.displayTitle,
        artist: lyric != null && lyric.isNotEmpty ? lyric : song.displayArtist,
        album: song.displayAlbum,
        duration: song.duration != null ? Duration(milliseconds: song.duration!) : null,
        artUri: song.coverPath != null && File(song.coverPath!).existsSync()
            ? Uri.file(song.coverPath!)
            : null,
      ),
    );
  }

  void _onCompleted() {
    // loopAll / loopOne / shuffle: just_audio 的 ConcatenatingAudioSource 会自动处理
  }

  Future<void> _restoreEqualizer() async {
    try {
      final eqEnabled = await MusicPlayerSettings.getEqEnabled();
      final eqPreset = await MusicPlayerSettings.getEqPreset();
      if (eqEnabled && eqPreset != EqPreset.off) {
        final gains = eqPreset == EqPreset.custom
            ? await MusicPlayerSettings.getEqGains()
            : MusicPlayerSettings.getPresetGains(eqPreset);
        await applyEqualizer(true, gains);
      } else {
        await applyEqualizer(false, [0, 0, 0, 0, 0]);
      }
    } catch (e) {
      debugPrint('恢复均衡器失败: $e');
    }
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    final sources = songs.map((s) => _buildAudioSource(s)).toList();
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: startIndex.clamp(0, songs.length - 1),
      );
      _queue = List.from(songs);
      _currentIndex = startIndex.clamp(0, _queue.length - 1);
      saveState();
      notifyListeners();
    } catch (e, st) {
      debugPrint('setAudioSource 失败: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> playSong(Song song) async {
    final index = _queue.indexWhere((s) => s.id == song.id);
    try {
      if (index >= 0) {
        _currentIndex = index;
        await _player.seek(Duration.zero, index: index);
        await _playWithFadeIn();
      } else {
        await setQueue([song]);
        await _playWithFadeIn();
      }
      if (song.id != null) {
        await _dao.addPlayHistory(song.id!, 0, false);
      }
      // 同步更新 LibraryItem 的 lastOpenedDate，使最近阅读能显示
      final libraryItem = await _libraryDao.getItemByPath(song.filePath);
      if (libraryItem?.id != null) {
        await _libraryDao.updateLastOpened(libraryItem!.id!);
      }
      // 更新离线缓存访问时间
      await OfflineCacheService.instance.touchAccess(song.filePath);
      notifyListeners();
    } catch (e, st) {
      debugPrint('playSong 失败: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _setAudioSessionActive(bool active) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(active);
    } catch (e) {
      debugPrint('设置音频会话状态失败: $e');
    }
  }

  Future<void> _playWithFadeIn() async {
    _fadeTimer?.cancel();
    await _setAudioSessionActive(true);
    await _player.play();
    _startFade(_player.volume, 1.0, const Duration(milliseconds: 300));
  }

  Future<void> play() async {
    await _playWithFadeIn();
    notifyListeners();
  }

  Future<void> pause() async {
    _fadeTimer?.cancel();
    await _startFadeAndWait(_player.volume, 0.0, const Duration(milliseconds: 300));
    await _player.pause();
    await _setAudioSessionActive(false);
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.shuffle) {
      await _playShuffleNext();
      return;
    }
    if (_currentIndex < _queue.length - 1) {
      await _player.seekToNext();
    } else if (_playMode == PlayMode.loopAll) {
      await _player.seek(Duration.zero, index: 0);
      await _playWithFadeIn();
    }
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_playMode == PlayMode.shuffle) {
      await _playShufflePrevious();
      return;
    }
    if (_currentIndex > 0) {
      await _player.seekToPrevious();
    } else if (_playMode == PlayMode.loopAll) {
      await _player.seek(Duration.zero, index: _queue.length - 1);
      await _playWithFadeIn();
    }
  }

  Future<void> _playShuffleNext() async {
    if (_shuffleIndices.isEmpty) _buildShuffleIndices();
    final currentShuffle = _shuffleIndices.indexOf(_currentIndex);
    final nextShuffle = (currentShuffle + 1) % _shuffleIndices.length;
    final nextIndex = _shuffleIndices[nextShuffle];
    await _player.seek(Duration.zero, index: nextIndex);
    await _playWithFadeIn();
  }

  Future<void> _playShufflePrevious() async {
    if (_shuffleIndices.isEmpty) _buildShuffleIndices();
    final currentShuffle = _shuffleIndices.indexOf(_currentIndex);
    final prevShuffle = (currentShuffle - 1 + _shuffleIndices.length) % _shuffleIndices.length;
    final prevIndex = _shuffleIndices[prevShuffle];
    await _player.seek(Duration.zero, index: prevIndex);
    await _playWithFadeIn();
  }

  void _buildShuffleIndices() {
    _shuffleIndices = List.generate(_queue.length, (i) => i);
    _shuffleIndices.shuffle();
    // 确保当前歌曲不在第一个位置（切歌时有变化感）
    if (_shuffleIndices.isNotEmpty && _shuffleIndices.first == _currentIndex && _shuffleIndices.length > 1) {
      final temp = _shuffleIndices.first;
      _shuffleIndices[0] = _shuffleIndices[1];
      _shuffleIndices[1] = temp;
    }
  }

  void togglePlayMode() {
    const modes = PlayMode.values;
    _playMode = modes[(_playMode.index + 1) % modes.length];

    switch (_playMode) {
      case PlayMode.loopAll:
        _player.setLoopMode(LoopMode.all);
        break;
      case PlayMode.loopOne:
        _player.setLoopMode(LoopMode.one);
        break;
      case PlayMode.shuffle:
        _player.setLoopMode(LoopMode.all);
        _buildShuffleIndices();
        break;
    }
    notifyListeners();
  }

  Future<void> addToQueue(Song song) async {
    _queue.add(song);
    final source = _buildAudioSource(song);
    final currentSource = _player.audioSource;
    if (currentSource is ConcatenatingAudioSource) {
      await currentSource.add(source);
    }
    saveState();
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    final currentSource = _player.audioSource;
    if (currentSource is ConcatenatingAudioSource) {
      await currentSource.removeAt(index);
    }
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
    }
    saveState();
    notifyListeners();
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);
    final currentSource = _player.audioSource;
    if (currentSource is ConcatenatingAudioSource) {
      await currentSource.move(oldIndex, newIndex);
    }
    saveState();
    notifyListeners();
  }

  Future<void> clearQueue() async {
    await _player.stop();
    await _setAudioSessionActive(false);
    _queue = [];
    _currentIndex = -1;
    await _dao.savePlayerState('queue_ids', '');
    notifyListeners();
  }

  Future<void> saveState() async {
    if (_queue.isEmpty) return;
    await _dao.savePlayerState('queue_ids', _queue.map((s) => s.id).join(','));
    await _dao.savePlayerState('current_index', _currentIndex.toString());
    await _dao.savePlayerState('position', _player.position.inMilliseconds.toString());
    await _dao.savePlayerState('play_mode', _playMode.index.toString());
    await _dao.savePlayerState('speed', _speed.toString());
  }

  void _debouncedSaveState() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 3), () {
      saveState();
    });
  }

  Future<void> _restoreState() async {
    final queueIdsStr = await _dao.getPlayerState('queue_ids');
    final currentIndexStr = await _dao.getPlayerState('current_index');
    final positionStr = await _dao.getPlayerState('position');
    final playModeStr = await _dao.getPlayerState('play_mode');
    final speedStr = await _dao.getPlayerState('speed');

    if (queueIdsStr != null && queueIdsStr.isNotEmpty) {
      final ids = queueIdsStr.split(',').map((s) => int.tryParse(s)).whereType<int>().toList();
      final songs = await _dao.getSongsByIds(ids);
      if (songs.isNotEmpty) {
        _queue = songs;
        _currentIndex = int.tryParse(currentIndexStr ?? '0') ?? 0;
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);

        final savedPosition = int.tryParse(positionStr ?? '0') ?? 0;

        if (playModeStr != null) {
          final modeIndex = int.tryParse(playModeStr);
          if (modeIndex != null && modeIndex >= 0 && modeIndex < PlayMode.values.length) {
            _playMode = PlayMode.values[modeIndex];
          }
        }

        if (speedStr != null) {
          final savedSpeed = double.tryParse(speedStr);
          if (savedSpeed != null) {
            _speed = savedSpeed.clamp(0.5, 2.0);
            await _player.setSpeed(_speed);
          }
        }

        final sources = _queue.map((s) => _buildAudioSource(s)).toList();
        try {
          await _player.setAudioSource(
            ConcatenatingAudioSource(children: sources),
            initialIndex: _currentIndex,
            initialPosition: Duration(milliseconds: savedPosition),
          );
          // 恢复后自动暂停，等待用户手动播放
          await _player.pause();
        } catch (e, st) {
          debugPrint('_restoreState setAudioSource 失败: $e');
          debugPrint(st.toString());
        }
        notifyListeners();
      }
    }
  }

  void updateSongInQueue(Song updatedSong) {
    final index = _queue.indexWhere((s) => s.id == updatedSong.id);
    if (index >= 0) {
      _queue[index] = updatedSong;
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) async {
    _fadeTimer?.cancel();
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  double get volume => _player.volume;

  void _startFade(double from, double to, Duration duration) {
    const steps = 10;
    final stepDuration = duration ~/ steps;
    final stepDelta = (to - from) / steps;
    int currentStep = 0;

    // 立即执行第一步，避免 30ms 空窗期
    _player.setVolume((from + stepDelta).clamp(0.0, 1.0));
    currentStep++;

    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      if (currentStep > steps) {
        timer.cancel();
        return;
      }
      _player.setVolume((from + stepDelta * currentStep).clamp(0.0, 1.0));
    });
  }

  Future<void> _startFadeAndWait(double from, double to, Duration duration) async {
    const steps = 10;
    final stepDuration = duration ~/ steps;
    final stepDelta = (to - from) / steps;

    for (int i = 1; i <= steps; i++) {
      await _player.setVolume((from + stepDelta * i).clamp(0.0, 1.0));
      await Future.delayed(stepDuration);
    }
  }

  Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0);
    _speed = clamped;
    await _player.setSpeed(clamped);
    notifyListeners();
  }

  Future<void> applyEqualizer(bool enabled, List<double> gains) async {
    if (!Platform.isAndroid) return;
    try {
      await _equalizer.setEnabled(enabled);
      if (enabled) {
        final parameters = await _equalizer.parameters;
        final bands = parameters.bands;
        for (int i = 0; i < bands.length && i < gains.length; i++) {
          await bands[i].setGain(gains[i]);
        }
      }
    } catch (e) {
      debugPrint('应用均衡器失败: $e');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fadeTimer?.cancel();
    _saveDebounceTimer?.cancel();
    _processingStateSub?.cancel();
    _currentIndexSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    saveState().then((_) {
      _player.dispose();
    });
    super.dispose();
  }
}
