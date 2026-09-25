import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'studio_native_pages.dart';
import 'youtube_browser.dart';
import 'main_player_controller.dart';
import 'main_player_panel.dart';
import 'player_presets.dart';
import 'study_tools.dart';
import 'chord_sheet.dart';
import 'stage_panel.dart';
import 'practice_panel.dart';
import 'practice_controller.dart';
import 'player_collections.dart';
import 'session_recovery_controller.dart';
import 'session_snapshot.dart';

part 'studio_player_home.dart';

/// Resolution-independent shell based on the six references supplied with the
/// project. Actions without a product implementation remain explicitly pending.
class StudioVisualApp extends StatelessWidget {
  const StudioVisualApp({
    super.key,
    this.functionalPlayer,
    this.youtubeSessionFactory,
    this.playerController,
    this.presetStore,
    this.recoveryRepository,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  final SessionSnapshotRepository? recoveryRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transpono',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF051424),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00E5FF),
        surface: Color(0xFF07121F),
      ),
    ),
    home: StudioVisualHome(
      functionalPlayer: functionalPlayer,
      youtubeSessionFactory: youtubeSessionFactory,
      playerController: playerController,
      presetStore: presetStore,
      recoveryRepository: recoveryRepository,
    ),
  );
}

enum StudioTab { player, practice, chords, stage }

class StudioVisualHome extends StatefulWidget {
  const StudioVisualHome({
    super.key,
    this.functionalPlayer,
    this.youtubeSessionFactory,
    this.playerController,
    this.presetStore,
    this.recoveryRepository,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  final SessionSnapshotRepository? recoveryRepository;

  @override
  State<StudioVisualHome> createState() => _StudioVisualHomeState();
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.selected, required this.onSelect});
  final StudioTab selected;
  final ValueChanged<StudioTab> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    height: 65,
    decoration: const BoxDecoration(
      color: Color(0xFF07121F),
      border: Border(top: BorderSide(color: Color(0xFF16283D))),
    ),
    child: Row(
      children: <Widget>[
        _tab(StudioTab.player, Icons.play_circle_outline, 'PLAYER'),
        _tab(StudioTab.practice, Icons.graphic_eq, 'PRÁTICA'),
        _tab(StudioTab.chords, Icons.music_note, 'ACORDES'),
        _tab(StudioTab.stage, Icons.tune, 'PALCO'),
      ],
    ),
  );

  Widget _tab(StudioTab tab, IconData icon, String label) {
    final bool active = tab == selected;
    final Color color = active
        ? const Color(0xFF00E5FF)
        : const Color(0xFF94A3B8);
    return Expanded(
      child: InkWell(
        key: Key('visualTab${tab.name}'),
        onTap: () => onSelect(tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            if (active)
              const CircleAvatar(radius: 2, backgroundColor: Color(0xFF00E5FF)),
          ],
        ),
      ),
    );
  }
}
