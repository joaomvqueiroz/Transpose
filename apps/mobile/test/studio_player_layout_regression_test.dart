import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/main_player_panel.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/session_snapshot.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('main player does not leave a legacy strip below the video', (
    tester,
  ) async {
    await tester.pumpWidget(const StudioVisualApp());
    await tester.pumpAndSettle();
    expect(find.byType(MainPlayerPanel), findsNothing);
    expect(find.byKey(const Key('visualMainAdjustmentsBackdrop')), findsNothing);
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byType(MainPlayerPanel), findsNothing);
    expect(
      find.byKey(const Key('visualMainAdjustmentsBackdrop')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('visualMainAdjustmentsBackdrop')),
          )
          .color,
      const Color(0xFF040F1C),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('recovery message remains dismissible without a top bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      StudioVisualApp(recoveryRepository: _WarningRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    final recovery = find.byKey(const Key('recoveryStatus'));
    expect(tester.getRect(recovery).top, greaterThanOrEqualTo(0));
    expect(find.text('Transpono').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const Key('recoveryDismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryStatus')), findsNothing);
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('pending YouTube recovery shows only the restore action', (
    tester,
  ) async {
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        recoveryRepository: _PendingVideoRepository(),
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryRestore')), findsOneWidget);
    expect(find.byKey(const Key('youtubeSearchInput')), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.byKey(const Key('recoveryStatus')), findsNothing);
    expect(find.byKey(const Key('recoveryDismiss')), findsNothing);
    expect(find.textContaining('Última sessão'), findsNothing);
    expect(
      session.commands.where(
        (command) => ['play', 'playPause', 'unmute'].contains(command.$1),
      ),
      isEmpty,
    );
    await tester.tap(find.byKey(const Key('recoveryRestore')));
    await tester.pumpAndSettle();
    expect(
      session.commands.where(
        (command) => ['play', 'playPause', 'unmute'].contains(command.$1),
      ),
      isEmpty,
    );
  });

  testWidgets('only video pins; successful restore removes its button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _TrackedBrowserSession();
    await tester.pumpWidget(
      StudioVisualApp(
        recoveryRepository: _PendingVideoRepository(),
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryRestore')), findsOneWidget);
    await tester.tap(find.byKey(const Key('visualPlayerPinVideo')));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byKey(const Key('visualScrollplayer')))
        .controller!;
    scroll.jumpTo(160);
    await tester.pump();
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);

    scroll.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('recoveryRestore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    expect(find.byKey(const Key('recoveryStatus')), findsNothing);
    expect(session.disposed, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('touch surface keeps the same browser view across navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _TrackedBrowserSession();
    var creations = 0;
    await tester.pumpWidget(
      StudioVisualApp(
        youtubeSessionFactory: () {
          creations++;
          return session;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('visualPlayerMenu')));
    await tester.pumpAndSettle();
    final searchAction = find.text('Pesquisar no YouTube').last;
    await tester.ensureVisible(searchAction);
    await tester.tap(searchAction);
    await tester.pumpAndSettle();
    final browser = find.byType(_BrowserView);
    final mountedView = tester.state(browser);
    expect(find.byType(MainPlayerFullscreen), findsNothing);
    await tester.tap(find.byKey(const Key('browserResultAction')));
    await tester.pump();
    expect(session.browserTaps, 1);
    await tester.tap(find.byKey(const Key('youtubeUseInPlayer')));
    await tester.pumpAndSettle();
    expect(find.byType(MainPlayerFullscreen), findsOneWidget);
    expect(find.byKey(const Key('pinnedYouTubeMedia')), findsNothing);
    final surface = find.byKey(const Key('visualFullscreenSurface'));
    final beforeScroll = tester.getRect(surface);
    expect(beforeScroll.height, greaterThan(200));
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(surface).height,
      beforeScroll.height,
      reason: 'Ajustes must not reserve an empty strip below YouTube',
    );
    expect(
      tester.getRect(find.byKey(const Key('visualMainControlsOverlay'))).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('visualMainAdjustments'))).top,
      ),
      reason: 'The floating Ajustes button must not cover player controls',
    );
    expect(
      tester.getRect(find.byKey(const Key('visualMainAdjustmentsBackdrop'))).top,
      tester.getRect(find.byKey(const Key('visualMainControlsOverlay'))).bottom,
      reason: 'The dark controls background must fill the gap below controls',
    );
    expect(
      tester.getSize(find.byKey(const Key('visualMainControlsOverlay'))).height,
      greaterThan(beforeScroll.height * .4),
      reason: 'The main Ajustes panel has 25% more height than before',
    );
    final marker = tester.getSize(find.byKey(const Key('visualFullscreenMarkA')));
    expect(marker.width, lessThan(140));
    expect(marker.height, lessThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const Key('visualScrollplayer')),
        )
        .controller!;
    scroll.jumpTo(100);
    await tester.pump();
    expect(tester.getRect(surface).top, beforeScroll.top - 100);
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    scroll.jumpTo(0);
    await tester.pump();

    await tester.tap(find.byKey(const Key('visualPlayerPinVideo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pinnedPlayerMedia')), findsOneWidget);
    final pinnedVideo = tester.getRect(
      find.byKey(const Key('visualFullscreenSurface')),
    );
    scroll.jumpTo(100);
    await tester.pump();
    final pinnedAtTop = tester.getRect(
      find.byKey(const Key('visualFullscreenSurface')),
    );
    expect(pinnedAtTop.top, lessThanOrEqualTo(pinnedVideo.top));
    scroll.jumpTo(200);
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('visualFullscreenSurface'))),
      pinnedAtTop,
      reason: 'Pinning holds the video while the controls scroll',
    );
    expect(
      find.byKey(const Key('visualPlayerHeader')),
      findsNothing,
      reason: 'Only the video, not Transpono, is pinned',
    );
    expect(session.viewMounts, 1);
    expect(session.viewDisposals, 0);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('visualPlayerPinVideo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pinnedPlayerMedia')), findsNothing);
    expect(session.viewMounts, 1);
    expect(session.viewDisposals, 0);
    final releasedVideo = tester.getRect(
      find.byKey(const Key('visualFullscreenSurface')),
    );
    scroll.jumpTo(100);
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('visualFullscreenSurface'))).top,
      releasedVideo.top - 100,
    );
    scroll.jumpTo(0);
    await tester.pump();

    void expectSameBrowser() {
      expect(creations, 1);
      expect(session.viewBuilds, 1);
      expect(session.viewMounts, 1);
      expect(session.viewDisposals, 0);
      expect(session.disposed, isFalse);
      expect(identical(tester.state(browser), mountedView), isTrue);
    }

    expectSameBrowser();
    for (final tab in ['practice', 'chords', 'stage', 'player']) {
      await tester.tap(find.byKey(const Key('visualPlayerMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('visualTab$tab')));
      await tester.pumpAndSettle();
      expectSameBrowser();
    }
    await tester.tap(find.byKey(const Key('visualPlayerMenu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tela cheia').last);
    await tester.tap(find.text('Tela cheia').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
    expectSameBrowser();
    await tester.tap(find.byKey(const Key('visualFullscreenBack')));
    await tester.pumpAndSettle();
    expectSameBrowser();

    await tester.tap(find.byKey(const Key('visualPlayerMenu')));
    await tester.pumpAndSettle();
    final searchAgain = find.text('Pesquisar no YouTube').last;
    await tester.ensureVisible(searchAgain);
    await tester.tap(searchAgain);
    await tester.pumpAndSettle();
    expect(find.byType(MainPlayerFullscreen), findsNothing);
    await tester.tap(find.byKey(const Key('browserResultAction')));
    await tester.pump();
    expect(session.browserTaps, 2);
    expectSameBrowser();
    expect(
      session.commands.where(
        (command) => ['play', 'playPause', 'unmute'].contains(command.$1),
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.viewDisposals, 1);
    expect(session.disposed, isTrue);
  });
}

class _WarningRepository extends SessionSnapshotRepository {
  @override
  Future<SessionRecoveryResult> read() async => const SessionRecoveryResult(
    writeBlocked: true,
    warning: 'Os dados foram preservados. Atualize o app para recuperar esta sessão de uma versão mais recente.',
  );

  @override
  Future<void> save(SessionSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

class _PendingVideoRepository extends _WarningRepository {
  @override
  Future<SessionRecoveryResult> read() async => SessionRecoveryResult(
    snapshot: SessionSnapshot(
      media: const PlayerPreset(
        id: 'saved-video',
        name: 'Estudo',
        title: 'Vídeo guardado',
        sourceId: 'aqz-KE-bpKQ',
        locator: 'aqz-KE-bpKQ',
        youtube: true,
        pitch: 0,
        speed: 1,
        positionMs: 1000,
      ),
      savedAt: DateTime.utc(2026, 9, 25),
    ),
  );
}

class _TrackedBrowserSession extends FakeYouTubeSession {
  _TrackedBrowserSession() {
    state = const YouTubeMediaState(
      videoId: 'aqz-KE-bpKQ',
      title: 'Vídeo de estudo',
      hasVideo: true,
      duration: 180,
    );
  }

  int viewBuilds = 0, viewMounts = 0, viewDisposals = 0, browserTaps = 0;

  @override
  Widget buildView() {
    viewBuilds++;
    return _BrowserView(session: this);
  }
}

class _BrowserView extends StatefulWidget {
  const _BrowserView({required this.session});

  final _TrackedBrowserSession session;

  @override
  State<_BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<_BrowserView> {
  @override
  void initState() {
    super.initState();
    widget.session.viewMounts++;
  }

  @override
  void dispose() {
    widget.session.viewDisposals++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      key: const Key('browserResultAction'),
      onPressed: () => widget.session.browserTaps++,
      child: const Text('Abrir resultado do YouTube'),
    ),
  );
}
