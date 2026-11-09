import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/studio_appearance.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

/// The browse page draws its own text, so the two pages can be told apart.
class _BrowseSession extends FakeYouTubeSession {
  @override
  Widget buildView() => const Center(child: Text('Página de pesquisa'));
}

class _InteractivePlayerSession extends FakeYouTubeSession {
  int videoTaps = 0;

  @override
  Widget buildView() => GestureDetector(
    key: const Key('playerPageTapTarget'),
    onTap: () => videoTaps++,
    child: const ColoredBox(color: Colors.black),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    'duas páginas: escolher na pesquisa toca no leitor, encolher mostra a pesquisa',
    (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final browse = _BrowseSession();
      final player = _InteractivePlayerSession();
      await tester.pumpWidget(
        StudioVisualApp(
          openSearchWhenEmpty: true,
          youtubeSessionFactory: () => player,
          browseSessionFactory: () => browse,
        ),
      );
      await tester.pumpAndSettle();

      // The studio opens on the browse page; the player has no page yet.
      expect(browse.browseOnly, isTrue);
      expect(browse.startedUri, Uri.https('m.youtube.com', '/'));
      expect(find.text('Página de pesquisa'), findsOneWidget);
      expect(player.startedUri, isNull);

      // A video chosen in the browse page plays in the player page.
      final watch = Uri.https('m.youtube.com', '/watch', {'v': 'abcdefghijk'});
      browse.onOpenRequest!(watch);
      await tester.pumpAndSettle();
      expect(player.startedUri, watch);
      player.state = const YouTubeMediaState(
        videoId: 'abcdefghijk',
        title: 'Música',
        hasVideo: true,
        playing: true,
        duration: 200,
      );
      player.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Página de pesquisa'), findsNothing);
      expect(player.appMini, isTrue);

      // Dragging the video down shrinks it over the browse page, still playing.
      player.onMinimizeRequest!();
      await tester.pumpAndSettle();
      expect(find.text('Página de pesquisa'), findsOneWidget);
      expect(find.byKey(const Key('appMiniPlayer')), findsOneWidget);
      expect(player.commands.where((c) => c.$1 == 'pause'), isEmpty);
      expect(browse.publishesPageState, isTrue);
      expect(player.publishesPageState, isFalse);

      // Touches on the video in the mini player go to YouTube's WebView. A
      // separate, small control is used to restore the full player.
      final miniTopLeft = tester.getTopLeft(
        find.byKey(const Key('appMiniPlayerTouch')),
      );
      await tester.tapAt(miniTopLeft + const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(player.videoTaps, 1);
      expect(find.byKey(const Key('appMiniPlayer')), findsOneWidget);

      // It can be dragged and settles against a side.
      final mini = find.byKey(const Key('appMiniPlayerTouch'));
      final before = tester.getTopLeft(mini);
      await tester.drag(mini, const Offset(-250, -200));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(mini);
      expect(after.dx, closeTo(12, 0.5));
      expect(after.dy, lessThan(before.dy));

      // The dedicated expand button brings the video back to full size.
      await tester.tap(find.byKey(const Key('appMiniPlayerExpand')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appMiniPlayer')), findsNothing);
      expect(find.text('Página de pesquisa'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tema escuro/claro é propagado às duas páginas YouTube', (
    tester,
  ) async {
    final browse = _BrowseSession();
    final player = FakeYouTubeSession();
    Widget home(StudioAppearanceMode mode) => MaterialApp(
      home: StudioVisualHome(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => player,
        browseSessionFactory: () => browse,
        appearance: StudioAppearance(mode: mode),
      ),
    );

    await tester.pumpWidget(home(StudioAppearanceMode.dark));
    await tester.pumpAndSettle();
    expect(browse.appearanceModes, contains(StudioAppearanceMode.dark));

    browse.onOpenRequest!(
      Uri.https('m.youtube.com', '/watch', {'v': 'abcdefghijk'}),
    );
    await tester.pumpAndSettle();
    expect(player.appearanceModes, contains(StudioAppearanceMode.dark));

    await tester.pumpWidget(home(StudioAppearanceMode.light));
    await tester.pumpAndSettle();
    expect(browse.appearanceModes.last, StudioAppearanceMode.light);
    expect(player.appearanceModes.last, StudioAppearanceMode.light);
  });

  testWidgets('sem a fábrica da segunda página fica tudo numa só', (
    tester,
  ) async {
    final player = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => player,
      ),
    );
    await tester.pumpAndSettle();
    expect(player.browseOnly, isFalse);
    expect(player.startedUri, isNotNull);
  });
}
