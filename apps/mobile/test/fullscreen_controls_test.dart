import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/main_player_panel.dart';
import 'package:transpose_mobile/player_panel_model.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    final Finder target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  testWidgets(
    'fullscreen pitch, speed, markers and transport use shared state',
    (tester) async {
      final model = _Model();
      await tester.pumpWidget(_app(model));
      await tap(tester, 'visualFullscreenPitchUp');
      expect(model.pitch, 1);
      await tap(tester, 'visualFullscreenPitchDown');
      expect(model.pitch, 0);
      await tap(tester, 'visualFullscreenPitchDown');
      await tap(tester, 'visualFullscreenPitchReset');
      expect(model.pitch, 0);

      await tap(tester, 'visualFullscreenSpeedDown');
      expect(model.speed, .95);
      await tap(tester, 'visualFullscreenSpeedUp');
      expect(model.speed, 1);
      await tap(tester, 'visualFullscreenSpeed');
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.75×'));
      await tester.pumpAndSettle();
      expect(model.speed, .75);
      await tap(tester, 'visualFullscreenSpeedReset');
      expect(model.speed, 1);

      await tap(tester, 'visualFullscreenMarkA');
      expect(model.markerA, const Duration(seconds: 20));
      model.position = const Duration(seconds: 40);
      await tap(tester, 'visualFullscreenMarkB');
      expect(model.markerB, const Duration(seconds: 40));
      await tap(tester, 'visualFullscreenLoopToggle');
      expect(model.loopEnabled, isTrue);
      await tap(tester, 'visualFullscreenLoopToggle');
      expect(model.loopEnabled, isFalse);
      expect(model.markerB, isNotNull);
      await tap(tester, 'visualFullscreenClearLoop');
      expect(model.markerA, isNull);
      expect(model.markerB, isNull);

      await tap(tester, 'visualFullscreenBack10');
      expect(model.position, const Duration(seconds: 30));
      await tap(tester, 'visualFullscreenForward10');
      expect(model.position, const Duration(seconds: 40));
      await tap(tester, 'visualFullscreenPlay');
      expect(model.playing, isTrue);
      await tap(tester, 'visualFullscreenPlay');
      expect(model.playing, isFalse);
      final seek = find.byKey(const Key('visualFullscreenSeek'));
      await tester.ensureVisible(seek);
      await tester.drag(seek, const Offset(100, 0));
      await tester.pump();
      expect(model.position, greaterThan(const Duration(seconds: 40)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('YouTube uses only its native seek bar', (tester) async {
    final model = _Model();
    await tester.pumpWidget(_app(model, youtubeNativeTransport: true));
    expect(find.byKey(const Key('visualFullscreenSeek')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenPitchUp')), findsOneWidget);
    expect(find.byKey(const Key('visualFullscreenMarkA')), findsOneWidget);

    await tester.pumpWidget(_app(model));
    expect(find.byKey(const Key('visualFullscreenSeek')), findsOneWidget);
  });

  testWidgets('main player has no redundant reveal button on the right', (
    tester,
  ) async {
    final model = _Model()..playing = true;
    await tester.pumpWidget(_app(model, mainMode: true));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('visualFullscreenReveal')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'more menu connects real tools and reset, without hiding under popup',
    (tester) async {
      final model = _Model()..playing = true;
      final tools = <String>[];
      await tester.pumpWidget(_app(model, onTool: tools.add));
      for (final item in <(String, String)>[
        ('Guardar ajustes', 'save'),
        ('Metrônomo', 'metronome'),
        ('Acordes', 'chords'),
        ('Afinador por referência', 'tuner'),
        ('Ferramentas de áudio', 'advanced'),
      ]) {
        await tap(tester, 'visualFullscreenMore');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
        expect(_opacity(tester), 1);
        await tester.tap(find.text(item.$1));
        await tester.pumpAndSettle();
        expect(tools.last, item.$2);
      }
      model
        ..pitch = 3
        ..speed = .75
        ..markerA = Duration.zero
        ..markerB = const Duration(seconds: 5)
        ..update();
      await tap(tester, 'visualFullscreenMore');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repor tom, velocidade e A–B'));
      await tester.pumpAndSettle();
      expect(model.pitch, 0);
      expect(model.speed, 1);
      expect(model.markerA, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'auto-hide is playing-only and position ticks do not postpone it',
    (tester) async {
      final model = _Model();
      int mediaTaps = 0;
      await tester.pumpWidget(
        _app(
          model,
          media: GestureDetector(
            key: const Key('existingMedia'),
            behavior: HitTestBehavior.opaque,
            onTap: () => mediaTaps++,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      );
      final mediaSize = tester.getSize(find.byKey(const Key('existingMedia')));
      await tester.pump(const Duration(seconds: 6));
      expect(_opacity(tester), 1);
      model
        ..playing = true
        ..update();
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        model
          ..position += const Duration(seconds: 1)
          ..update();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_opacity(tester), 0);
      expect(find.byKey(const Key('visualFullscreenReveal')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('existingMedia'))), mediaSize);
      await tester.tap(find.byKey(const Key('existingMedia')));
      await tester.pump();
      expect(mediaTaps, 1);
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_opacity(tester), 0);
      await tap(tester, 'visualFullscreenReveal');
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(seconds: 5));
      model
        ..playing = false
        ..update();
      await tester.pump();
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(seconds: 6));
      expect(_opacity(tester), 1);
    },
  );

  testWidgets('held touch and accessibility prevent disappearing controls', (
    tester,
  ) async {
    final model = _Model()..playing = true;
    await tester.pumpWidget(_app(model));
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(seconds: 6));
    expect(_opacity(tester), 1);
    await gesture.up();
    await tester.pump(const Duration(seconds: 5));
    expect(_opacity(tester), 0);
    await tester.pumpWidget(_app(model, accessible: true));
    await tester.pump(const Duration(seconds: 8));
    expect(_opacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('both locks disable all commands and only long hold unlocks', (
    tester,
  ) async {
    final model = _Model();
    int exited = 0;
    await tester.pumpWidget(_app(model, onExit: () => exited++));
    await tap(tester, 'visualFullscreenLockSurface');
    for (final key in <String>[
      'visualFullscreenPlay',
      'visualFullscreenBack10',
      'visualFullscreenForward10',
      'visualFullscreenPitchUp',
      'visualFullscreenPitchDown',
      'visualFullscreenSpeedUp',
      'visualFullscreenSpeedDown',
      'visualFullscreenBack',
    ]) {
      expect(
        tester.widget<IconButton>(find.byKey(Key(key))).onPressed,
        isNull,
        reason: key,
      );
    }
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('visualFullscreenSeek')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('visualFullscreenLoopToggle')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('visualFullscreenMore')),
          )
          .enabled,
      isFalse,
    );
    await tap(tester, 'visualFullscreenLock');
    expect(_opacity(tester), 0);
    await tester.longPress(find.byKey(const Key('visualFullscreenLock')));
    await tester.pump();
    expect(_opacity(tester), 1);
    await tap(tester, 'visualFullscreenBack');
    expect(exited, 1);
  });

  testWidgets(
    'pending pitch can be cancelled, failures reveal, unsupported actions disable',
    (tester) async {
      final model = _Model()..playing = true;
      await tester.pumpWidget(_app(model));
      await tester.pump(const Duration(seconds: 5));
      expect(_opacity(tester), 0);
      model
        ..canPitch = false
        ..pitchPending = true
        ..message = 'A preparar alteração de tom'
        ..update();
      await tester.pump();
      expect(_opacity(tester), 1);
      expect(find.text('A preparar alteração de tom'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('visualFullscreenPitchUp')),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 8));
      expect(_opacity(tester), 1);
      await tap(tester, 'visualFullscreenPitchReset');
      expect(model.pitchPending, isFalse);
      model
        ..canSpeed = false
        ..canLoop = false
        ..message = 'Esta fonte não permite estes ajustes.'
        ..update();
      await tester.pump();
      expect(find.text('Tom indisponível nesta fonte.'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('visualFullscreenSpeedUp')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('visualFullscreenMarkA')),
            )
            .onPressed,
        isNull,
      );
      model
        ..busy = true
        ..update();
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
            .onPressed,
        isNotNull,
        reason: 'Pause remains available while an adjustment is pending.',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(_opacity(tester), 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small portrait and landscape with 2x text keep every control reachable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final model = _Model();
      for (final size in <Size>[const Size(320, 640), const Size(640, 320)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(_app(model, scale: 2));
        for (final key in <String>[
          'visualFullscreenPitchUp',
          'visualFullscreenSpeedDown',
          'visualFullscreenMarkA',
          'visualFullscreenClearLoop',
          'visualFullscreenPlay',
        ]) {
          await tap(tester, key);
          expect(tester.takeException(), isNull, reason: '$key at $size');
        }
        model
          ..playing = false
          ..update();
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'model replacement detaches old listener and unmount cancels hide',
    (tester) async {
      final first = _Model()..playing = true;
      final second = _Model();
      await tester.pumpWidget(_app(first));
      expect(first.isObserved, isTrue);
      await tester.pumpWidget(_app(second));
      expect(first.isObserved, isFalse);
      expect(second.isObserved, isTrue);
      first
        ..message = 'stale'
        ..update();
      await tester.pump();
      expect(find.text('stale'), findsNothing);
      second
        ..playing = true
        ..update();
      await tester.pumpWidget(const SizedBox());
      expect(second.isObserved, isFalse);
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    },
  );
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('visualFullscreenOverlay')))
    .opacity;

Widget _app(
  _Model model, {
  double scale = 1,
  bool accessible = false,
  Widget media = const ColoredBox(color: Colors.black),
  VoidCallback? onExit,
  ValueChanged<String>? onTool,
  bool youtubeNativeTransport = false,
  bool mainMode = false,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        accessibleNavigation: accessible,
      ),
      child: MainPlayerFullscreen(
        model: model,
        media: media,
        onExit: onExit ?? () {},
        onTool: onTool,
        youtubeNativeTransport: youtubeNativeTransport,
        mainMode: mainMode,
        showHeader: !mainMode,
        controlsOpen: mainMode ? false : null,
      ),
    ),
  ),
);

class _Model extends PlayerPanelModel {
  bool get isObserved => hasListeners;
  @override
  bool loaded = true;
  @override
  bool playing = false;
  @override
  bool busy = false;
  @override
  bool canPitch = true;
  @override
  bool pitchPending = false;
  @override
  bool canSpeed = true;
  @override
  bool canLoop = true;
  @override
  bool muted = false;
  @override
  String title = 'A song with a long title to check clipping';
  @override
  String sourceLabel = 'Áudio local';
  @override
  String? message;
  @override
  Duration position = const Duration(seconds: 20);
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  double pitch = 0;
  @override
  double speed = 1;
  @override
  Duration? markerA;
  @override
  Duration? markerB;
  @override
  bool loopEnabled = false;
  void update() => notifyListeners();
  @override
  Future<void> playPause() async {
    playing = !playing;
    update();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    update();
  }

  @override
  Future<void> changePitch(double value) async {
    pitch = value;
    pitchPending = false;
    update();
  }

  @override
  Future<void> changeSpeed(double value) async {
    speed = value;
    update();
  }

  @override
  Future<void> markA() async {
    markerA = position;
    update();
  }

  @override
  Future<void> markB() async {
    markerB = position;
    update();
  }

  @override
  Future<void> toggleLoop() async {
    loopEnabled = !loopEnabled;
    update();
  }

  @override
  Future<void> clearLoop() async {
    markerA = markerB = null;
    loopEnabled = false;
    update();
  }

  @override
  Future<void> resetProcessing() async {
    pitch = 0;
    speed = 1;
    markerA = markerB = null;
    loopEnabled = false;
    update();
  }
}
