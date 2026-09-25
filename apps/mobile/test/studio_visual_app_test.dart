import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  testWidgets('empty startup opens YouTube with search focused', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () => session,
        openSearchWhenEmpty: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeSearchInput')), findsOneWidget);
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(session.commands.where((c) => c.$1 == 'play'), isEmpty);
  });

  Future<void> tap(WidgetTester tester, String key) async {
    if (key.startsWith('visualTab') &&
        find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('visualPlayerMenu')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tap(tester, 'visualPlayerMenu');
    final action = find.text('Pesquisar no YouTube').last;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  testWidgets('save dialog persists acknowledged media and restores it', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(
        videoId: 'aqz-KE-bpKQ',
        title: 'Song',
        hasVideo: true,
        duration: 180,
        pitch: -2,
        speed: .8,
        loopA: 2,
        loopB: 4,
      );
    final store = PlayerPresetStore();
    await tester.pumpWidget(
      StudioVisualApp(youtubeSessionFactory: () => session, presetStore: store),
    );
    await openSearch(tester);
    await tap(tester, 'youtubeUseInPlayer');
    await tap(tester, 'visualPlayerMenu');
    await tester.ensureVisible(find.text('Guardar predefinição'));
    await tester.tap(find.text('Guardar predefinição'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('presetName')), 'Saved test');
    await tap(tester, 'presetSave');
    final entries = await store.list();
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Saved test');
    expect(entries.single.pitch, -2);
    await tap(tester, 'visualPlayerMenu');
    await tester.ensureVisible(find.text('Predefinições e loops guardados'));
    await tester.tap(find.text('Predefinições e loops guardados'));
    await tester.pumpAndSettle();
    await tap(tester, 'collectionOpen-${entries.single.id}');
    expect(find.byKey(const Key('visualScrollplayer')), findsOneWidget);
    expect(
      session.commands.where(
        (c) => ['playPause', 'play', 'unmute'].contains(c.$1),
      ),
      isEmpty,
    );
    expect(session.disposed, isFalse);
  });

  testWidgets('tabs and real main menu stay reachable', (tester) async {
    await tester.pumpWidget(const StudioVisualApp());
    expect(find.byKey(const Key('visualMainAdjustments')), findsOneWidget);
    expect(find.byKey(const Key('visualTabpractice')), findsNothing);
    expect(find.byKey(const Key('visualPlayerControlsToggle')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPitchUp')), findsNothing);
    expect(find.byKey(const Key('visualPlayerChordPicker')), findsNothing);
    expect(find.byKey(const Key('visualPlayerEmptyFile')), findsNothing);
    expect(find.byKey(const Key('visualPlayerEmptySearch')), findsNothing);
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualPlayerChordPicker')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerEmptyFile')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerEmptySearch')), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.byKey(const Key('visualMainControlsOverlay')),
          )
          .ignoring,
      isFalse,
    );
    expect(find.byKey(const Key('visualFullscreenPitchUp')), findsOneWidget);
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualPlayerChordPicker')), findsNothing);
    expect(find.byKey(const Key('visualPlayerEmptyFile')), findsNothing);
    expect(find.byKey(const Key('visualPlayerEmptySearch')), findsNothing);
    expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
    for (final name in ['practice', 'chords', 'stage', 'player']) {
      await tap(tester, 'visualTab$name');
      expect(find.byKey(Key('visualScroll$name')), findsOneWidget);
    }
    await tap(tester, 'visualPlayerMenu');
    expect(find.text('Predefinições e loops guardados'), findsOneWidget);
    await tap(tester, 'visualSidebarClose');
    expect(find.byKey(const Key('visualScrollplayer')), findsOneWidget);
  });

  testWidgets('search selection and fullscreen preserve one YouTube session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = FakeYouTubeSession();
    int creations = 0;
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () {
          creations++;
          return session;
        },
      ),
    );
    await openSearch(tester);
    expect(find.text('Resultados com miniaturas'), findsOneWidget);
    expect(session.startedUri?.host, 'm.youtube.com');
    await tester.enterText(
      find.byKey(const Key('youtubeSearchInput')),
      'Gravity live',
    );
    await tap(tester, 'youtubeSearchSubmit');
    expect(session.lastQuery, 'Gravity live');
    session.state = const YouTubeMediaState(
      videoId: 'aqz-KE-bpKQ',
      title: 'A música escolhida',
      hasVideo: true,
      position: 30,
      duration: 180,
      pitch: 2,
      speed: .85,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    await tap(tester, 'youtubeUseInPlayer');
    expect(find.byKey(const Key('visualScrollplayer')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    expect(find.textContaining('Navegador integrado'), findsNothing);
    for (final name in ['practice', 'chords', 'stage', 'player']) {
      await tap(tester, 'visualTab$name');
      expect(find.byKey(Key('visualScroll$name')), findsOneWidget);
      expect(
        find.text('Resultados com miniaturas').hitTestable(),
        findsOneWidget,
      );
      expect(creations, 1);
      expect(session.disposed, isFalse);
    }
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualFullscreenPlay')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenBack10')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenForward10')), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('visualFullscreenPitchValue')),
          )
          .properties
          .label,
      'Tom +2 semitons',
    );
    await tap(tester, 'visualFullscreenPitchUp');
    expect(session.commands.last, ('pitch', 3));
    expect(find.byKey(const Key('visualFullscreenPitchValue')), findsOneWidget);
    await tap(tester, 'visualFullscreenSpeed');
    await tester.tap(find.text('0.75×').last);
    await tester.pumpAndSettle();
    expect(session.commands.last, ('speed', .75));
    expect(find.byKey(const Key('pinnedYouTubeMedia')), findsNothing);
    expect(find.text('Resultados com miniaturas'), findsOneWidget);
    expect(
      session.commands.where(
        (command) => ['play', 'playPause', 'seekTo'].contains(command.$1),
      ),
      isEmpty,
    );
    await tap(tester, 'visualFullscreenMarkA');
    expect(session.commands.last, ('markA', null));
    await tap(tester, 'visualPlayerMenu');
    await tester.ensureVisible(find.text('Tela cheia').last);
    await tester.tap(find.text('Tela cheia').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
    expect(find.byKey(const Key('visualFullscreenPlay')), findsNothing);
    expect(find.text('Resultados com miniaturas'), findsOneWidget);
    expect(session.disposed, isFalse);
    await tap(tester, 'visualFullscreenBack');
    expect(creations, 1);
    expect(find.byKey(const Key('visualFullscreenPitchValue')), findsOneWidget);
    expect(session.disposed, isFalse);
    await openSearch(tester);
    await tap(tester, 'youtubeClose');
    expect(creations, 1);
    expect(session.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(session.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty panel disables transport instead of opening legacy player',
    (tester) async {
      await tester.pumpWidget(
        const StudioVisualApp(functionalPlayer: Text('Legacy')),
      );
      expect(find.byKey(const Key('visualMainControlsOverlay')), findsNothing);
      await tap(tester, 'visualMainAdjustments');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('visualFullscreenPitchUp')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Legacy'), findsNothing);
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(430, 932),
    const Size(844, 390),
  ]) {
    testWidgets('shell and embedded search fit ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        StudioVisualApp(youtubeSessionFactory: FakeYouTubeSession.new),
      );
      for (final name in ['practice', 'chords', 'stage', 'player']) {
        await tap(tester, 'visualTab$name');
      }
      await openSearch(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('youtubeBrowserViewport'))).height,
        greaterThan(180),
      );
    });
  }
}
