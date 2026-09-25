import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
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
    await tap(tester, 'visualPlayerSearch');
    await tap(tester, 'youtubeUseInPlayer');
    await tap(tester, 'visualPlayerMore');
    await tester.tap(find.text('Guardar predefinição'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('presetName')), 'Saved test');
    await tap(tester, 'presetSave');
    final entries = await store.list();
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Saved test');
    expect(entries.single.pitch, -2);
    await tap(tester, 'visualPlayerMore');
    await tester.ensureVisible(find.text('Predefinições guardadas'));
    await tester.tap(find.text('Predefinições guardadas'));
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
    await tap(tester, 'visualPlayerSearch');
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
    expect(find.text('A música escolhida'), findsOneWidget);
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
    await tap(tester, 'visualPlayerPitchUp');
    expect(session.commands.last, ('pitch', 3));
    expect(find.text('+2'), findsOneWidget);
    await tap(tester, 'visualPlayerSpeed075');
    expect(session.commands.last, ('speed', .75));
    await tap(tester, 'visualPlayerPlay');
    expect(session.commands.last, ('play', null));
    final pinned = tester.getRect(find.byKey(const Key('pinnedYouTubeMedia')));
    expect(pinned.top, greaterThanOrEqualTo(0));
    expect(pinned.bottom, lessThan(844));
    expect(
      find.text('Resultados com miniaturas').hitTestable(),
      findsOneWidget,
    );
    await tap(tester, 'visualPlayerBack10');
    expect(session.commands.last, ('seekTo', 20));
    await tap(tester, 'visualPlayerMarkA');
    expect(session.commands.last, ('markA', null));
    await tap(tester, 'visualPlayerFullscreen');
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
    expect(find.text('Resultados com miniaturas'), findsOneWidget);
    expect(session.disposed, isFalse);
    await tap(tester, 'visualFullscreenBack');
    expect(creations, 1);
    expect(find.text('+2'), findsOneWidget);
    expect(session.disposed, isFalse);
    await tap(tester, 'visualPlayerSearch');
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
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualPlayerPlay')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualPlayerPitchUp')))
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
      await tap(tester, 'visualPlayerSearch');
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('youtubeBrowserViewport'))).height,
        greaterThan(180),
      );
    });
  }
}
