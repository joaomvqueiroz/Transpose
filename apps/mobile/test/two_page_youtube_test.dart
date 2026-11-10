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

/// Counts the pointer events that reach the player page.
class _PointerCountingSession extends FakeYouTubeSession {
  int downs = 0, ups = 0, cancels = 0;

  @override
  Widget buildView() => Listener(
    key: const Key('playerPointerSurface'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => downs++,
    onPointerUp: (_) => ups++,
    onPointerCancel: (_) => cancels++,
    child: const ColoredBox(color: Colors.black),
  );
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
      expect(player.appMiniSurface, isTrue);
      expect(player.commands.where((c) => c.$1 == 'pause'), isEmpty);
      expect(browse.publishesPageState, isTrue);
      expect(player.publishesPageState, isFalse);

      // The scaled mini-player surface never forwards native hit coordinates.
      // Tapping it restores the full-size WebView before YouTube gets touches.
      final miniTopLeft = tester.getTopLeft(
        find.byKey(const Key('appMiniPlayerTouch')),
      );
      await tester.tapAt(miniTopLeft + const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(player.videoTaps, 0);
      expect(find.byKey(const Key('appMiniPlayer')), findsNothing);
      expect(player.appMiniSurface, isFalse);
      expect(find.text('Página de pesquisa'), findsNothing);

      // It can be minimized again, dragged and settled against a side.
      player.onMinimizeRequest!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('appMiniPlayer')), findsOneWidget);

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
      expect(player.appMiniSurface, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'encolher espera o dedo levantar: o leitor nunca muda de sítio a meio de um toque',
    (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final browse = _BrowseSession();
      final player = _PointerCountingSession();
      await tester.pumpWidget(
        StudioVisualApp(
          openSearchWhenEmpty: true,
          youtubeSessionFactory: () => player,
          browseSessionFactory: () => browse,
        ),
      );
      await tester.pumpAndSettle();
      browse.onOpenRequest!(
        Uri.https('m.youtube.com', '/watch', {'v': 'abcdefghijk'}),
      );
      await tester.pumpAndSettle();
      player.state = const YouTubeMediaState(
        videoId: 'abcdefghijk',
        title: 'Música',
        hasVideo: true,
        playing: true,
        duration: 200,
      );
      player.notifyListeners();
      await tester.pumpAndSettle();
      final mini = find.byKey(const Key('appMiniPlayer'));
      final surface = find.byKey(const Key('playerPointerSurface'));

      for (var cycle = 0; cycle < 6; cycle++) {
        // The finger goes down on the video and drags; the page asks for
        // the mini player while it is still down.
        final at = tester.getTopLeft(surface) + const Offset(120, 120);
        final gesture = await tester.startGesture(at);
        await gesture.moveBy(const Offset(0, 90));
        player.onMinimizeRequest!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(mini, findsNothing, reason: 'ciclo $cycle: dedo ainda em baixo');
        expect(player.downs - player.ups - player.cancels, 1);

        // Odd cycles end with a cancelled gesture instead of a lift.
        if (cycle.isOdd) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(mini, findsOneWidget, reason: 'ciclo $cycle: encolhe ao largar');
        expect(
          player.downs,
          player.ups + player.cancels,
          reason: 'ciclo $cycle: o leitor recebeu o fim do toque',
        );

        // Restore and check a plain tap reaches the player again.
        await tester.tap(find.byKey(const Key('appMiniPlayerExpand')));
        await tester.pumpAndSettle();
        expect(mini, findsNothing);
        final before = player.ups;
        await tester.tapAt(
          tester.getTopLeft(surface) + const Offset(120, 120),
        );
        await tester.pumpAndSettle();
        expect(player.ups, before + 1, reason: 'ciclo $cycle: toque chega');
        expect(mini, findsNothing, reason: 'ciclo $cycle: pedido já consumido');
      }
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
