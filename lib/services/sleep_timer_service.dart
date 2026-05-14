import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'music_player_service.dart';

enum SleepTimerType { off, byDuration, bySongs }

class SleepTimerService extends ChangeNotifier {
  static final SleepTimerService instance = SleepTimerService._internal();
  SleepTimerService._internal();

  Timer? _timer;
  SleepTimerType _type = SleepTimerType.off;
  SleepTimerType get type => _type;

  Duration? _remaining;
  Duration? get remaining => _remaining;

  int? _songsRemaining;
  int? get songsRemaining => _songsRemaining;

  StreamSubscription? _songChangeSub;

  bool get isActive => _type != SleepTimerType.off;

  /// 按时间定时关闭（分钟）
  void startByDuration(int minutes) {
    cancel();
    _type = SleepTimerType.byDuration;
    _remaining = Duration(minutes: minutes);
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining = _remaining! - const Duration(seconds: 1);
      if (_remaining!.inSeconds <= 0) {
        _fadeOutAndStop();
      }
      notifyListeners();
    });
  }

  /// 按曲目数定时关闭
  void startBySongs(int count) {
    cancel();
    _type = SleepTimerType.bySongs;
    _songsRemaining = count;
    notifyListeners();

    _songChangeSub = MusicPlayerService.instance.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _songsRemaining = _songsRemaining! - 1;
        if (_songsRemaining! <= 0) {
          _stopPlayback();
        }
        notifyListeners();
      }
    });
  }

  /// 播完当前歌曲停止
  void stopAfterCurrent() {
    cancel();
    _type = SleepTimerType.bySongs;
    _songsRemaining = 1;
    notifyListeners();

    _songChangeSub = MusicPlayerService.instance.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _stopPlayback();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _songChangeSub?.cancel();
    _songChangeSub = null;
    _type = SleepTimerType.off;
    _remaining = null;
    _songsRemaining = null;
    notifyListeners();
  }

  Future<void> _fadeOutAndStop() async {
    final player = MusicPlayerService.instance;
    for (int i = 10; i >= 0; i--) {
      if (_type == SleepTimerType.off) return;
      await player.setVolume(i / 10);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (_type == SleepTimerType.off) return;
    await player.pause();
    await player.setVolume(1.0);
    cancel();
  }

  void _stopPlayback() {
    MusicPlayerService.instance.pause();
    cancel();
  }
}
