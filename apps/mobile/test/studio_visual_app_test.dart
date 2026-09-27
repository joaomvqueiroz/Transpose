import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('empty startup opens YouTube without duplicate search', (
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
    expect(find.byKey(const Key('youtubeSearchInput')), findsNothing);
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsOneWidget);
    expect(find.text('YouTube · Transpono'), findsNothing);
    expect(find.byKey(const Key('youtubeClose')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(session.commands.where((c) => c.$1 == 'play'), isEmpty);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('open button is centred and close button lives in tabs', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await tester.pumpWidget(const StudioVisualApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final open = tester.getRect(find.byKey(const Key('visualMainAdjustments')));
    expect((open.center.dx - screenWidth / 2).abs(), lessThan(1));
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    final close = tester.getRect(
      find.byKey(const Key('visualMainAdjustments')),
    );
    expect(close.center.dx, greaterThan(screenWidth / 2));
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('visualMainAdjustments')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> tap(WidgetTester tester, String key) async {
    if (key == 'visualPlayerMenu') return;
    if (key.startsWith('unifiedSection') &&
        find.byKey(Key(key)).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('visualMainAdjustments')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsOneWidget);
  }

  Future<void> selectVideo(
    WidgetTester tester,
    FakeYouTubeSession session,
    YouTubeMediaState selected,
  ) async {
    session.state = const YouTubeMediaState();
    session.notifyListeners();
    await tester.pump();
    session.state = selected;
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeUseInPlayer')), findsNothing);
  }

  testWidgets('save dialog persists acknowledged media and restores it', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final session = FakeYouTubeSession();
    final store = PlayerPresetStore();
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () => session,
        presetStore: store,
        openSearchWhenEmpty: true,
      ),
    );
    await openSearch(tester);
    await selectVideo(
      tester,
      session,
      const YouTubeMediaState(
        videoId: 'aqz-KE-bpKQ',
        title: 'Song',
        hasVideo: true,
        duration: 180,
        pitch: -2,
        speed: .8,
        loopA: 2,
        loopB: 4,
      ),
    );
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'unifiedSectionpractice');
    await tap(tester, 'visualPracticeSaveLoop');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('presetName')), 'Saved test');
    await tap(tester, 'presetSave');
    final entries = await store.list();
    expect(entries, hasLength(1));
    expect(entries.single.name, 'Saved test');
    expect(entries.single.pitch, -2);
    await tap(tester, 'practiceSavedLoops');
    await tester.pumpAndSettle();
    await tap(tester, 'collectionOpen-${entries.single.id}');
    expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    expect(
      session.commands.where(
        (c) => ['playPause', 'play', 'unmute'].contains(c.$1),
      ),
      isEmpty,
    );
    expect(session.disposed, isFalse);
  });

  testWidgets('secções e menu do player unificado ficam acessíveis', (
    tester,
  ) async {
    await tester.pumpWidget(const StudioVisualApp());
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('unifiedSectionpractice')), findsNothing);
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('unifiedPitchUp')), findsOneWidget);
    for (final name in ['practice', 'chords', 'setlist']) {
      await tap(tester, 'unifiedSection$name');
      expect(find.byKey(Key('unifiedSection$name')), findsOneWidget);
      expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    }
    expect(find.byKey(const Key('unifiedSectionsetlist')), findsOneWidget);
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('unifiedSectionpractice')), findsNothing);
    expect(find.text('Abrir ajustes'), findsOneWidget);
  });
  testWidgets('pesquisa e secções preservam uma sessão YouTube', (
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
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () {
          creations++;
          return session;
        },
      ),
    );
    await openSearch(tester);
    expect(session.startedUri?.host, 'm.youtube.com');
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
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsNothing);
    expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    await tap(tester, 'visualMainAdjustments');
    expect(find.byKey(const Key('visualFullscreenPlay')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenBack10')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenForward10')), findsNothing);
    await tap(tester, 'unifiedPitchUp');
    expect(session.commands.last, ('pitch', 3));
    for (final name in ['practice', 'chords', 'setlist']) {
      await tap(tester, 'unifiedSection$name');
      expect(creations, 1);
      expect(session.disposed, isFalse);
    }
    await tap(tester, 'unifiedSectionchords');
    expect(find.byKey(const Key('unifiedMore')), findsNothing);
    expect(find.text('Tela cheia'), findsNothing);
    expect(creations, 1);
    expect(session.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(session.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('opening a YouTube chord sheet gives it room below the video', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await ChordSheetStore().save(
      'youtube:aqz-KE-bpKQ',
      ChordSheet(
        notes: List.generate(
          50,
          (i) => 'C     G\nLinha $i da cifra',
        ).join('\n'),
      ),
    );
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () => session,
        openSearchWhenEmpty: true,
      ),
    );
    await openSearch(tester);
    await selectVideo(
      tester,
      session,
      const YouTubeMediaState(
        videoId: 'aqz-KE-bpKQ',
        title: 'Song',
        hasVideo: true,
        duration: 180,
      ),
    );
    final viewport = find.byKey(const Key('visualMainMediaViewport'));
    final fullHeight = tester.getSize(viewport).height;
    await tap(tester, 'visualMainAdjustments');
    await tap(tester, 'unifiedChooseChord');
    expect(find.byKey(const Key('playerChordSheet')), findsOneWidget);
    expect(tester.getSize(viewport).height, fullHeight);
    final chordOverlay = find.byKey(const Key('unifiedChordOverlay'));
    final overlayTop = tester.getTopLeft(chordOverlay).dy;
    final tabsTop = tester
        .getTopLeft(find.byKey(const Key('unifiedSectionchords')))
        .dy;
    // Initial controls keep their lowered position, but the scrollable sheet
    // can later occupy the title area immediately below the video.
    expect(tabsTop - overlayTop, greaterThan(50));
    expect(
      tester.widget<ClipRRect>(chordOverlay).borderRadius,
      const BorderRadius.vertical(top: Radius.circular(18)),
    );
    expect(
      find.byKey(const Key('unifiedSectionchords')).hitTestable(),
      findsOneWidget,
    );
    final initialSheetTop = tester
        .getTopLeft(find.byKey(const Key('playerChordSheet')))
        .dy;
    final initialTabsTop = tester
        .getTopLeft(find.byKey(const Key('unifiedSectionchords')))
        .dy;
    final backdrop = find.byKey(const Key('unifiedChordBackdrop'));
    expect(tester.getSize(backdrop).width, tester.getSize(chordOverlay).width);
    await tester.drag(
      find.byKey(const Key('unifiedChordTextScroll')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('unifiedSectionchords'))).dy,
      lessThan(initialTabsTop),
      reason: 'Os botões da Cifra devem subir com a rolagem do texto.',
    );
    await tester.drag(
      find.byKey(const Key('unifiedChordScroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedChordScroll')), findsOneWidget);
    expect(find.byKey(const Key('pinnedChordTextScroll')), findsNothing);
    final raisedSheet = tester.getRect(
      find.byKey(const Key('playerChordSheet')),
    );
    expect(raisedSheet.top, lessThan(initialSheetTop));
    expect(raisedSheet.left, greaterThan(0));
    final frame = find.byKey(const Key('unifiedChordFrame'));
    final frameTop = tester.getTopLeft(frame).dy;
    expect(frameTop, closeTo(overlayTop, 2));
    await tester.drag(
      find.byKey(const Key('unifiedChordTextScroll')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(frame).dy, closeTo(frameTop, 1));
    expect(
      tester
          .widget<Container>(find.byKey(const Key('playerChordSheet')))
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.borderRadius,
        'rounded top',
        BorderRadius.circular(18),
      ),
    );
    await tester.drag(
      find.byKey(const Key('unifiedChordTextScroll')),
      const Offset(0, 1500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedChordScroll')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('playerChordSheet'))).dy,
      greaterThan(raisedSheet.top),
    );
    expect(
      find.byKey(const Key('unifiedSectionchords')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(const Key('visualFullscreenSeek')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cifra sem folha cobre o fundo até ao fim dos ajustes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () => session,
        openSearchWhenEmpty: true,
      ),
    );
    await openSearch(tester);
    await selectVideo(
      tester,
      session,
      const YouTubeMediaState(
        videoId: 'aqz-KE-bpKQ',
        title: 'Song',
        hasVideo: true,
        duration: 180,
      ),
    );
    await tap(tester, 'visualMainAdjustments');
    final overlay = tester.getRect(
      find.byKey(const Key('unifiedChordOverlay')),
    );
    final backdrop = tester.getRect(
      find.byKey(const Key('unifiedChordControlsBackdrop')),
    );
    expect(backdrop.bottom, closeTo(overlay.bottom, 1));
    expect(backdrop.width, closeTo(overlay.width, 1));
  });

  testWidgets(
    'empty panel disables transport instead of opening legacy player',
    (tester) async {
      await tester.pumpWidget(
        const StudioVisualApp(functionalPlayer: Text('Legacy')),
      );
      expect(find.byKey(const Key('unifiedPitchUp')), findsNothing);
      await tap(tester, 'visualMainAdjustments');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualPlayerPlay')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('unifiedPitchUp')))
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
      await tester.pumpAndSettle();
      await tap(tester, 'visualMainAdjustments');
      final adjustments = tester.getRect(
        find.byKey(const Key('visualMainAdjustments')),
      );
      expect(adjustments.center.dx, greaterThan(size.width / 2));
      for (final name in ['practice', 'chords', 'setlist']) {
        await tap(tester, 'unifiedSection$name');
        expect(tester.takeException(), isNull, reason: 'secção $name');
      }
      await tap(tester, 'unifiedSectionaudioSettings');
      if (size.height >= 500) {
        await tester.ensureVisible(find.byKey(const Key('audioTuner')));
        await tester.tap(find.byKey(const Key('audioTuner')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: 'áudio/afinador');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        StudioVisualApp(
          youtubeSessionFactory: FakeYouTubeSession.new,
          openSearchWhenEmpty: true,
        ),
      );
      await openSearch(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('youtubeBrowserViewport'))).height,
        greaterThan(180),
      );
    });
  }
}
