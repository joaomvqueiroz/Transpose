import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> openBrowser(WidgetTester tester, Widget app) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsOneWidget);
    expect(find.byKey(const Key('youtubeUseInPlayer')), findsNothing);
  }

  Future<void> chooseVideo(WidgetTester tester, _FocusSession session) async {
    session.state = const YouTubeMediaState();
    session.notifyListeners();
    await tester.pump();
    session.state = const YouTubeMediaState(
      videoId: 'aqz-KE-bpKQ',
      title: 'Selected video',
      hasVideo: true,
      duration: 180,
    );
    session.notifyListeners();
  }

  testWidgets('selected video is focused only after the final player layout', (
    tester,
  ) async {
    final session = _FocusSession();
    int creations = 0;
    await openBrowser(
      tester,
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () {
          creations++;
          return session;
        },
      ),
    );
    final browserWidth = tester
        .getSize(find.byKey(const Key('focusTestBrowser')))
        .width;
    bool? searchStillMounted, playerMounted;
    double? focusedWidth;
    session.onFocus = () {
      searchStillMounted = find
          .byKey(const Key('youtubeBrowserViewport'))
          .evaluate()
          .isNotEmpty;
      playerMounted = find
          .byKey(const Key('visualMainMediaViewport'))
          .evaluate()
          .isNotEmpty;
      focusedWidth = tester
          .getSize(find.byKey(const Key('focusTestBrowser')))
          .width;
    };
    await chooseVideo(tester, session);
    expect(session.focuses, 0, reason: 'Do not scroll using the old viewport');
    await tester.pumpAndSettle();
    expect(session.focuses, 1);
    expect(searchStillMounted, isFalse);
    expect(playerMounted, isTrue);
    expect(
      focusedWidth,
      browserWidth,
      reason: 'O Player principal usa agora o vídeo de largura total.',
    );
    expect(creations, 1);
    expect(session.views, 1);
    expect(session.disposed, isFalse);
    expect(_playCommands(session), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'changing browser owner before the layout frame skips old focus',
    (tester) async {
      final first = _FocusSession();
      final replacement = _FocusSession();
      final player = _ReplaceableBrowserPlayer(first);
      addTearDown(player.dispose);
      addTearDown(replacement.dispose);
      await openBrowser(
        tester,
        StudioVisualApp(playerController: player, openSearchWhenEmpty: true),
      );
      await chooseVideo(tester, first);
      expect(first.focuses, 0);
      player.replacement = replacement;
      await tester.pump();
      expect(first.focuses, 0, reason: 'The selected owner was superseded');
      expect(
        replacement.focuses,
        0,
        reason: 'No focus request belongs to this owner',
      );
      expect(_playCommands(first), isEmpty);
      expect(_playCommands(replacement), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disposing the home before the layout frame skips browser focus',
    (tester) async {
      final session = _FocusSession();
      await openBrowser(
        tester,
        StudioVisualApp(
          youtubeSessionFactory: () => session,
          openSearchWhenEmpty: true,
        ),
      );
      await chooseVideo(tester, session);
      expect(session.focuses, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(session.disposed, isTrue);
      expect(session.focuses, 0);
      expect(_playCommands(session), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

Iterable<(String, num?)> _playCommands(FakeYouTubeSession session) => session
    .commands
    .where((c) => ['play', 'playPause', 'unmute'].contains(c.$1));

class _FocusSession extends FakeYouTubeSession {
  _FocusSession() {
    state = const YouTubeMediaState(
      videoId: 'aqz-KE-bpKQ',
      title: 'Selected video',
      hasVideo: true,
      duration: 180,
    );
  }
  int focuses = 0, views = 0;
  VoidCallback? onFocus;
  @override
  Future<void> focusVideo() async {
    focuses++;
    onFocus?.call();
  }

  @override
  Widget buildView() {
    views++;
    return const ColoredBox(
      key: Key('focusTestBrowser'),
      color: Colors.black,
      child: Center(child: Text('Browser fixture')),
    );
  }
}

class _ReplaceableBrowserPlayer extends MainPlayerController {
  _ReplaceableBrowserPlayer(YouTubeBrowserSession first)
    : super(youtubeFactory: () => first);
  YouTubeBrowserSession? replacement;
  @override
  YouTubeBrowserSession? get youtube => replacement ?? super.youtube;
}
