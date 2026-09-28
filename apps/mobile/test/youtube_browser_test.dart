import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  test('estimated music key accepts only a valid pitch class', () {
    final key = YouTubeMediaState.fromJson({
      'keyRoot': 7,
      'keyMode': 'major',
      'keyStatus': 'ready',
    });
    expect(key.keyRoot, 7);
    expect(key.keyMode, 'major');
    expect(key.keyStatus, 'ready');
    expect(YouTubeMediaState.fromJson({'keyRoot': 12}).keyRoot, isNull);
    expect(YouTubeMediaState.fromJson({'keyRoot': -1}).keyRoot, isNull);
  });

  test('loop observations parse only complete safe counter contracts', () {
    final YouTubeMediaState media = YouTubeMediaState.fromJson({
      'hasVideo': true,
      'loopCount': 7,
      'loopEpoch': 4,
      'loopEventsSupported': true,
      'playbackReady': true,
    });
    expect(media.loopCount, 7);
    expect(media.loopEpoch, 4);
    expect(media.loopEventsSupported, isTrue);
    expect(media.playbackReady, isTrue);
    final YouTubeMediaState legacy = YouTubeMediaState.fromJson({});
    expect(legacy.loopEventsSupported, isFalse);
    expect(legacy.playbackReady, isFalse);
    for (final Object? invalid in <Object?>[
      null,
      '1',
      -1,
      0.5,
      double.infinity,
      double.nan,
      9007199254740992,
    ]) {
      final YouTubeMediaState malformed = YouTubeMediaState.fromJson({
        'loopCount': invalid,
        'loopEpoch': 1,
        'loopEventsSupported': true,
      });
      expect(malformed.loopEventsSupported, isFalse);
      expect(malformed.loopCount, 0);
    }
    expect(
      YouTubeMediaState.fromJson({
        'hasVideo': true,
        'isAd': true,
        'playbackReady': true,
      }).playbackReady,
      isFalse,
    );
  });

  testWidgets('muted preview has explicit sound activation', (tester) async {
    final FakeYouTubeSession session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(
        hasVideo: true,
        playing: true,
        muted: true,
      );
    await tester.pumpWidget(
      MaterialApp(home: YouTubeBrowserScreen(session: session)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ativar som'), findsOneWidget);
    await tester.tap(find.byKey(const Key('youtubePlayPause')));
    expect(session.commands.last.$1, 'unmute');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('pitch waits for browser confirmation and background pauses', (
    tester,
  ) async {
    final FakeYouTubeSession session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(
        hasVideo: true,
        title: 'Música',
        duration: 180,
      );
    await tester.pumpWidget(
      MaterialApp(home: YouTubeBrowserScreen(session: session)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('youtubePitchUp')));
    await tester.pump();
    expect(session.commands.last, ('pitch', 1));
    expect(find.text('TOM 0 st'), findsOneWidget);
    session.state = const YouTubeMediaState(
      hasVideo: true,
      pitch: 1,
      pitchStatus: 'active',
    );
    session.notifyListeners();
    await tester.pump();
    expect(find.text('TOM +1 st'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(session.commands.last.$1, 'pause');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ads disable processing controls', (tester) async {
    final FakeYouTubeSession session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(hasVideo: true, isAd: true);
    await tester.pumpWidget(
      MaterialApp(home: YouTubeBrowserScreen(session: session)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('youtubePitchUp')))
          .onPressed,
      isNull,
    );
    expect(find.text('Anúncio · aguarde o vídeo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('small screen and landscape keep browser controls visible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final FakeYouTubeSession session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(
        hasVideo: true,
        title: 'Um título longo com nome da música e do artista',
        duration: 200,
        pitchMessage: 'O processamento ainda está a iniciar.',
      );
    for (final Size size in <Size>[
      const Size(320, 700),
      const Size(700, 320),
    ]) {
      tester.view.physicalSize = size;
      if (find.byType(YouTubeBrowserScreen).evaluate().isEmpty) {
        await tester.pumpWidget(
          MaterialApp(home: YouTubeBrowserScreen(session: session)),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('youtubeBrowserViewport'))).height,
        greaterThan(140),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
