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
import 'chord_browser.dart';
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
    this.chordBrowserFactory,
    this.openSearchWhenEmpty = false,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  final SessionSnapshotRepository? recoveryRepository;
  final ChordBrowserSession Function()? chordBrowserFactory;
  final bool openSearchWhenEmpty;

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
      chordBrowserFactory: chordBrowserFactory,
      openSearchWhenEmpty: openSearchWhenEmpty,
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
    this.chordBrowserFactory,
    this.openSearchWhenEmpty = false,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  final SessionSnapshotRepository? recoveryRepository;
  final ChordBrowserSession Function()? chordBrowserFactory;
  final bool openSearchWhenEmpty;

  @override
  State<StudioVisualHome> createState() => _StudioVisualHomeState();
}

class _MainAdjustmentsBar extends StatelessWidget {
  const _MainAdjustmentsBar({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    height: 52,
    child: OutlinedButton.icon(
      key: const Key('visualMainAdjustments'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xB3143544),
        foregroundColor: const Color(0xFF00E5FF),
        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
      ),
      icon: Icon(
        expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
        size: 30,
      ),
      label: Text(
        expanded ? 'Fechar ajustes' : 'Ajustes',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
  );
}
