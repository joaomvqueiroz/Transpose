import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/session_snapshot.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

final _savedVideo = SessionSnapshot(
  media: const PlayerPreset(
    id: 'video',
    name: 'Saved',
    title: 'Sessão de estudo',
    sourceId: 'aqz-KE-bpKQ',
    locator: 'aqz-KE-bpKQ',
    youtube: true,
    pitch: -2,
    speed: .8,
    positionMs: 3000,
    aMs: 2000,
    bMs: 6000,
    loop: true,
  ),
  savedAt: DateTime.utc(2026, 9, 25),
  screen: 'player',
  fullscreen: true,
);

class _Store extends SessionSnapshotRepository {
  _Store(this.result);
  final SessionRecoveryResult result;
  final List<SessionSnapshot> saves = [];
  int clears = 0;
  @override
  Future<SessionRecoveryResult> read() async => result;
  @override
  Future<void> save(SessionSnapshot snapshot) async => saves.add(snapshot);
  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  Future<void> close() async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
    'YouTube recovery needs a tap, stays paused and exits immersive view',
    (tester) async {
      final store = _Store(SessionRecoveryResult(snapshot: _savedVideo));
      final session = FakeYouTubeSession()
        ..state = const YouTubeMediaState(
          videoId: 'aqz-KE-bpKQ',
          title: 'Sessão de estudo',
          hasVideo: true,
          duration: 180,
          pitch: -2,
          speed: .8,
          loopA: 2,
          loopB: 6,
        );
      var creations = 0;
      await tester.pumpWidget(
        StudioVisualApp(
          recoveryRepository: store,
          youtubeSessionFactory: () {
            creations++;
            return session;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(creations, 0);
      expect(find.byKey(const Key('recoveryRestore')), findsOneWidget);
      expect(store.saves, isEmpty);
      await tester.tap(find.byKey(const Key('recoveryRestore')));
      await tester.pumpAndSettle();
      expect(creations, 1);
      expect(find.textContaining('Sessão recuperada'), findsNothing);
      expect(find.byKey(const Key('recoveryRestore')), findsNothing);
      expect(find.byKey(const Key('visualPlayerMenu')), findsOneWidget);
      expect(
        session.commands.where(
          (c) => ['playPause', 'play', 'unmute'].contains(c.$1),
        ),
        isEmpty,
      );
      expect(session.commands, contains(('seekTo', 3.0)));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'saved online session remains available without creating WebView',
    (tester) async {
      final store = _Store(SessionRecoveryResult(snapshot: _savedVideo));
      await tester.pumpWidget(
        StudioVisualApp(
          recoveryRepository: store,
          youtubeSessionFactory: () => throw StateError('No remote startup'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoveryRestore')), findsOneWidget);
      expect(find.byKey(const Key('recoveryStatus')), findsNothing);
      expect(find.byKey(const Key('recoveryDismiss')), findsNothing);
      expect(store.clears, 0);
      expect(store.saves, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final size in [const Size(320, 568), const Size(800, 250)]) {
    testWidgets('protected recovery banner remains usable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store(
        const SessionRecoveryResult(
          writeBlocked: true,
          warning: 'Os dados foram preservados. Atualize o app para recuperar esta sessão de uma versão mais recente.',
        ),
      );
      await tester.pumpWidget(StudioVisualApp(recoveryRepository: store));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoveryStatus')), findsOneWidget);
      expect(find.byKey(const Key('recoveryRetrySave')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('recoveryDismiss')));
      await tester.pumpAndSettle();
      expect(store.saves, isEmpty);
      expect(store.clears, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
