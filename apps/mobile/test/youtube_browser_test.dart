import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  test('sampled YouTube timeline invalidates seeks, pauses, ads, rates and stale replies', () {
    final tracker = YouTubeTimelineTracker();
    Map<String, dynamic> snapshot(
      int revision,
      double position, {
      int seek = 0,
      int rate = 0,
      int source = 1,
      double speed = 1,
      bool playing = true,
      bool ad = false,
      bool seeking = false,
      bool ready = true,
      String videoId = 'abcdefghijk',
      double browserTime = 1000,
    }) => <String, dynamic>{
      'snapshotRevision': revision,
      'sampleTimeMs': browserTime,
      'videoId': videoId,
      'hasVideo': true,
      'position': position,
      'duration': 180,
      'speed': speed,
      'timelineSeekEpoch': seek,
      'timelineRateEpoch': rate,
      'timelineSourceEpoch': source,
      'playing': playing,
      'isAd': ad,
      'seeking': seeking,
      'playbackReady': ready,
    };
    expect(
      tracker.observe(snapshot(0, 9.9), startUs: 900000, endUs: 920000),
      isFalse,
    );
    expect(
      tracker.observe(snapshot(1, 10), startUs: 1000000, endUs: 1020000),
      isTrue,
    );
    expect(tracker.latest!.hostMidpointUs, 1010000);
    expect(tracker.latest!.uncertaintyMs, 10);
    expect(
      tracker.observe(snapshot(1, 99), startUs: 1100000, endUs: 1110000),
      isFalse,
    );
    expect(tracker.latest!.positionMs, 10000);
    expect(
      tracker.observe(
        snapshot(2, 10.2, browserTime: 1200),
        startUs: 1200000,
        endUs: 1220000,
      ),
      isTrue,
    );
    final beforeSeek = tracker.latest!.epoch;
    expect(
      tracker.observe(
        snapshot(3, 25, seek: 1, seeking: true),
        startUs: 1300000,
        endUs: 1310000,
      ),
      isFalse,
    );
    expect(tracker.latest, isNull);
    expect(tracker.epoch, greaterThan(beforeSeek));
    expect(
      tracker.observe(
        snapshot(4, 25, seek: 1, browserTime: 1400),
        startUs: 1400000,
        endUs: 1410000,
      ),
      isTrue,
    );
    expect(tracker.observe(snapshot(5, 25, seek: 1, playing: false)), isFalse);
    expect(tracker.latest, isNull);
    expect(tracker.observe(snapshot(6, 25, seek: 1, ad: true)), isFalse);
    expect(tracker.observe(snapshot(7, 25.1, seek: 1, ready: false)), isFalse);
    expect(
      tracker.observe(
        snapshot(8, 25.2, seek: 1, browserTime: 1800),
        startUs: 1800000,
        endUs: 1810000,
      ),
      isTrue,
    );
    expect(
      tracker.observe(
        snapshot(9, 25.3, seek: 1, rate: 1, speed: 1.5, browserTime: 1900),
        startUs: 1900000,
        endUs: 1910000,
      ),
      isFalse,
    );
    expect(tracker.latest, isNull);
    expect(
      tracker.observe(
        snapshot(10, 25.4, seek: 1, rate: 1, speed: 1.5, browserTime: 2000),
        startUs: 2000000,
        endUs: 2010000,
      ),
      isTrue,
    );
    expect(tracker.latest!.epoch, greaterThan(beforeSeek));
    expect(
      tracker.observe(
        snapshot(
          11,
          25.5,
          seek: 1,
          rate: 1,
          speed: 1.5,
          videoId: 'zyxwvutsrqp',
          browserTime: 2100,
        ),
        startUs: 2100000,
        endUs: 2110000,
      ),
      isFalse,
    );
    expect(tracker.latest, isNull);
    expect(
      tracker.observe(
        snapshot(
          12,
          25.6,
          seek: 1,
          rate: 1,
          speed: 1.5,
          videoId: 'zyxwvutsrqp',
          browserTime: 2200,
        ),
        startUs: 2200000,
        endUs: 2210000,
      ),
      isTrue,
    );
    expect(tracker.latest!.videoId, 'zyxwvutsrqp');
    expect(
      tracker.observe(
        snapshot(
          13,
          25.7,
          seek: 1,
          rate: 1,
          speed: 1.5,
          videoId: 'zyxwvutsrqp',
          browserTime: 2300,
        ),
        startUs: 2300000,
        endUs: 2700000,
      ),
      isFalse,
    );
    expect(tracker.latest, isNull);
  });

  test('timeline rejects unannounced jumps and malformed timing', () {
    final tracker = YouTubeTimelineTracker();
    Map<String, dynamic> state(
      int revision,
      double position,
      double browserTime,
    ) => {
      'snapshotRevision': revision,
      'sampleTimeMs': browserTime,
      'videoId': 'abcdefghijk',
      'hasVideo': true,
      'position': position,
      'duration': 120,
      'speed': 1,
      'timelineSeekEpoch': 0,
      'timelineRateEpoch': 0,
      'timelineSourceEpoch': 1,
      'playing': true,
      'isAd': false,
      'seeking': false,
      'playbackReady': true,
    };
    expect(
      tracker.observe(state(0, 2, 1000), startUs: 0, endUs: 10000),
      isFalse,
    );
    expect(
      tracker.observe(state(1, 2.1, 1100), startUs: 100000, endUs: 110000),
      isTrue,
    );
    expect(
      tracker.observe(state(2, 40, 1200), startUs: 200000, endUs: 210000),
      isFalse,
    );
    expect(tracker.latest, isNull);
    expect(
      tracker.observe(state(3, 40.1, 1300), startUs: 300000, endUs: 310000),
      isTrue,
    );
    expect(
      tracker.observe(
        {...state(4, 40.2, 1400), 'sampleTimeMs': double.nan},
        startUs: 400000,
        endUs: 410000,
      ),
      isFalse,
    );
    expect(tracker.latest, isNull);
  });

  test('audio effect snapshots accept finite bounded engine values', () {
    final media = YouTubeMediaState.fromJson({
      'audioEffects': {
        'bass': 6,
        'mid': -30,
        'treble': double.nan,
        'gain': 99,
        'chorus': .2,
        'delay': -.2,
        'reverb': 'bad',
      },
    });
    expect(media.audioEffects, {
      'bass': 6.0,
      'mid': -12.0,
      'treble': 0.0,
      'gain': 6.0,
      'chorus': .2,
      'feedback': 0.0,
      'delay': 0.0,
      'reverb': 0.0,
    });
    expect(YouTubeMediaState.fromJson({}).audioEffects.values, everyElement(0));
    expect(() => media.audioEffects['bass'] = 8, throwsUnsupportedError);
  });

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
