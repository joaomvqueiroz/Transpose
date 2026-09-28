import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'studio_native_pages.dart';
import 'studio_column_theme.dart';
import 'youtube_browser.dart';
import 'main_player_controller.dart';
import 'main_player_panel.dart';
import 'player_chord_sheet.dart';
import 'player_presets.dart';
import 'study_tools.dart';
import 'band_session.dart';
import 'chord_sheet.dart';
import 'chord_browser.dart';
import 'practice_progression_card.dart';
import 'practice_controller.dart';
import 'player_collections.dart';
import 'session_snapshot.dart';
import 'premium_branding.dart';
import 'microphone_tuner.dart';
import 'home_widget_bridge.dart';
import 'studio_appearance.dart';
import 'stem_panel.dart';
import 'ambient_rhythm_trial.dart';

part 'studio_player_home.dart';

/// Resolution-independent shell based on the six references supplied with the
/// project. Actions without a product implementation remain explicitly pending.
class StudioVisualApp extends StatefulWidget {
  const StudioVisualApp({
    super.key,
    this.functionalPlayer,
    this.youtubeSessionFactory,
    this.playerController,
    this.presetStore,
    this.recoveryRepository,
    this.chordBrowserFactory,
    this.openSearchWhenEmpty = false,
    this.deferHomeUntilLaunch = false,
    this.waitForStartupBrowser = false,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  @Deprecated('A recuperação automática de sessões foi removida.')
  final SessionSnapshotRepository? recoveryRepository;
  final ChordBrowserSession Function()? chordBrowserFactory;
  final bool openSearchWhenEmpty;
  final bool deferHomeUntilLaunch;
  final bool waitForStartupBrowser;

  @override
  State<StudioVisualApp> createState() => _StudioVisualAppState();
}

class _StudioVisualAppState extends State<StudioVisualApp> {
  final StudioAppearanceStore _appearanceStore = StudioAppearanceStore();
  StudioAppearance _appearance = const StudioAppearance();
  Future<void> _appearanceWrites = Future<void>.value();
  bool _appearanceTouched = false;
  late final ValueNotifier<bool> _startupBrowserReady = ValueNotifier(
    !widget.waitForStartupBrowser,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
  }

  Future<void> _loadAppearance() async {
    final saved = await _appearanceStore.read();
    if (mounted && !_appearanceTouched) setState(() => _appearance = saved);
  }

  void _changeAppearance(StudioAppearance next) {
    _appearanceTouched = true;
    setState(() => _appearance = next);
    _appearanceWrites = _appearanceWrites
        .then((_) => _appearanceStore.save(next))
        .catchError((Object error, StackTrace stack) {
          debugPrint('Não foi possível guardar a aparência: $error');
        });
  }

  @override
  void dispose() {
    _startupBrowserReady.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Transpono',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: _appearance.mode == StudioAppearanceMode.light
          ? Brightness.light
          : Brightness.dark,
      scaffoldBackgroundColor: _appearance.mode == StudioAppearanceMode.light
          ? const Color(0xFFF4F7FB)
          : studioBg,
      colorScheme: _appearance.mode == StudioAppearanceMode.light
          ? const ColorScheme.light(
              primary: Color(0xFF163E51),
              onPrimary: Colors.white,
              surface: Color(0xFFF4F7FB),
            )
          : const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Color(0xFF101013),
              surface: Color(0xFF18181B),
            ),
    ),
    home: TransponoLaunchGate(
      deferChild: widget.deferHomeUntilLaunch,
      revealWhen: widget.waitForStartupBrowser ? _startupBrowserReady : null,
      child: StudioVisualHome(
        functionalPlayer: widget.functionalPlayer,
        youtubeSessionFactory: widget.youtubeSessionFactory,
        playerController: widget.playerController,
        presetStore: widget.presetStore,
        recoveryRepository: widget.recoveryRepository,
        chordBrowserFactory: widget.chordBrowserFactory,
        openSearchWhenEmpty: widget.openSearchWhenEmpty,
        appearance: _appearance,
        onAppearanceChanged: _changeAppearance,
        onInitialBrowserReady: () => _startupBrowserReady.value = true,
      ),
    ),
  );
}

enum StudioTab {
  player,
  practice,
  chords,
  stage,
  instruments,
  setlist,
  metronome,
  tuner,
  audioSettings,
  appearanceSettings,
}

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
    this.appearance = const StudioAppearance(),
    this.onAppearanceChanged,
    this.onInitialBrowserReady,
  });

  final Widget? functionalPlayer;
  final YouTubeBrowserSession Function()? youtubeSessionFactory;
  final MainPlayerController? playerController;
  final PlayerPresetStore? presetStore;
  @Deprecated('A recuperação automática de sessões foi removida.')
  final SessionSnapshotRepository? recoveryRepository;
  final ChordBrowserSession Function()? chordBrowserFactory;
  final bool openSearchWhenEmpty;
  final StudioAppearance appearance;
  final ValueChanged<StudioAppearance>? onAppearanceChanged;
  final VoidCallback? onInitialBrowserReady;

  @override
  State<StudioVisualHome> createState() => _StudioVisualHomeState();
}

class _MainAdjustmentsBar extends StatelessWidget {
  const _MainAdjustmentsBar({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: double.infinity,
    child: LayoutBuilder(
      builder: (context, box) {
        final buttonWidth = (box.maxWidth - 112).clamp(140.0, 230.0);
        return Stack(
          children: [
            Center(
              child: SizedBox(
                width: buttonWidth,
                height: 52,
                child: OutlinedButton.icon(
                  key: const Key('visualMainAdjustments'),
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: expanded
                        ? Colors.white
                        : const Color(0xEA18181B),
                    foregroundColor: expanded
                        ? const Color(0xFF161618)
                        : const Color(0xFFF4F4F5),
                    side: BorderSide(
                      color: expanded ? Colors.white : const Color(0xFFBABAC0),
                      width: 1.2,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: buttonWidth < 210 ? 24 : 30,
                  ),
                  label: Text(
                    expanded ? 'Fechar ajustes' : 'Abrir ajustes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: buttonWidth < 210 ? 14 : 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
