import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/fullscreen_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets(
    'fullscreen reuses the player, hides controls and preserves state',
    (WidgetTester tester) async {
      final _FakeLoader loader = _FakeLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'shared-session',
        loader: loader,
      );
      final LocalFileSource source = LocalFileSource.fromPath(
        id: 'one',
        displayName: 'Fixture',
        path: '/fixture.wav',
      );
      await session.load(source);
      await session.play();
      final VideoPlayerController controller = VideoPlayerController.file(
        File('/fixture.wav'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => FullscreenPlayer(
                        session: session,
                        controller: controller,
                      ),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fullscreenSurface')), findsOneWidget);
      expect(find.byKey(const Key('exitFullscreenButton')), findsNothing);
      expect(session.sessionId, 'shared-session');
      expect(session.state, PlayerState.playing);
      expect(session.source, same(source));
      expect(loader.loadCount, 1);

      await tester.tap(find.byKey(const Key('fullscreenSurface')));
      await tester.pump();
      expect(find.byKey(const Key('exitFullscreenButton')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('exitFullscreenButton')), findsNothing);

      await tester.tap(find.byKey(const Key('fullscreenSurface')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('fullscreenPlayPauseButton')));
      await tester.pumpAndSettle();
      expect(session.state, PlayerState.paused);

      await tester.tap(find.byKey(const Key('exitFullscreenButton')));
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(session.sessionId, 'shared-session');
      expect(session.state, PlayerState.paused);
      expect(session.source, same(source));
      expect(loader.loadCount, 1);
      expect(loader.releaseCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _FakeLoader implements MediaLoader {
  int loadCount = 0;
  int releaseCount = 0;

  @override
  Future<LoadedMedia> load(MediaSource source) async {
    loadCount += 1;
    return _FakeMedia(this);
  }
}

final class _FakeMedia implements LoadedMedia {
  _FakeMedia(this.loader);

  final _FakeLoader loader;

  @override
  Duration? get duration => const Duration(seconds: 12);

  @override
  Duration get position => Duration.zero;

  @override
  Stream<void> get endEvents => const Stream<void>.empty();

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<Duration> seek(Duration position) async => position;

  @override
  Future<void> release() async {
    loader.releaseCount += 1;
  }
}
