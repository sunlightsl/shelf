import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'recent_screen.dart';
import 'library_screen.dart';
import 'media_screen.dart';
import 'settings_screen.dart';
import 'media/music/mini_player.dart';
import '../services/music_player_service.dart';
import '../design_tokens/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const RecentScreen(),
    const LibraryScreen(),
    const MediaScreen(),
    const SettingsScreen(),
  ];

  final List<String> _titles = [
    '最近阅读',
    '书架',
    '影音',
    '设置',
  ];

  late Future<void> _initFuture;
  late final ValueNotifier<bool> _hasSongNotifier;
  StreamSubscription<int?>? _currentIndexSub;

  @override
  void initState() {
    super.initState();
    _initFuture = MusicPlayerService.instance.init();
    _hasSongNotifier = ValueNotifier<bool>(MusicPlayerService.instance.currentSong != null);
    MusicPlayerService.instance.addListener(_onPlayerUpdate);
    _currentIndexSub = MusicPlayerService.instance.currentIndexStream.listen((_) {
      if (mounted) {
        _hasSongNotifier.value = MusicPlayerService.instance.currentSong != null;
      }
    });
  }

  void _onPlayerUpdate() {
    if (mounted) {
      final hasSong = MusicPlayerService.instance.currentSong != null;
      if (_hasSongNotifier.value != hasSong) {
        _hasSongNotifier.value = hasSong;
      }
    }
  }

  @override
  void dispose() {
    MusicPlayerService.instance.removeListener(_onPlayerUpdate);
    _currentIndexSub?.cancel();
    _hasSongNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final neutral = NeutralPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark
              ? neutral.surface.withOpacity(0.85)
              : neutral.background.withOpacity(0.85),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _hasSongNotifier,
                builder: (context, hasSong, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: hasSong
                        ? const MiniPlayer(compact: true)
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  );
                },
              ),
              BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                backgroundColor: Colors.transparent,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.clock),
                    activeIcon: Icon(CupertinoIcons.clock_fill),
                    label: '最近',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.book),
                    activeIcon: Icon(CupertinoIcons.book_fill),
                    label: '书架',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.film),
                    activeIcon: Icon(CupertinoIcons.film_fill),
                    label: '影音',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(CupertinoIcons.gear),
                    activeIcon: Icon(CupertinoIcons.gear_solid),
                    label: '设置',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
