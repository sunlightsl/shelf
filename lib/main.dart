import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'app.dart';
import 'services/app_directories.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppDirectories.init();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.sunlight.shelf.channel.audio',
    androidNotificationChannelName: '音乐播放',
    androidNotificationOngoing: true,
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const LocalLibraryApp());
}
