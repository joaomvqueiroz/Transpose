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

  testWidgets('player fechado não mostra faixa de controlos redundante', (
    tester,
  ) async {
    await tester.pumpWidget(const StudioVisualApp());
    await tester.pumpAndSettle();
    expect(find.byType(MainPlayerPanel), findsNothing);
    expect(
      find.byKey(const Key('visualMainAdjustmentsBackdrop')),
      findsNothing,
    );
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedPitchUp')), findsOneWidget);
    expect(
      find.byKey(const Key('visualMainAdjustmentsBackdrop')),
      findsNothing,
    );
    expect(find.byKey(const Key('visualCloseAdjustments')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('visualMainAdjustments')))
          .tooltip,
      'Expandir ou fechar ajustes',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('recovery warning does not cover the video', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      StudioVisualApp(recoveryRepository: _WarningRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    expect(find.byKey(const Key('recoveryStatus')), findsNothing);
    expect(find.text('Transpono').hitTestable(), findsNothing);
    expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerHeader')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('pending YouTube recovery does not show a restore action', (
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
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    expect(find.byKey(const Key('youtubeSearchInput')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(const Key('recoveryStatus')), findsNothing);
    expect(find.byKey(const Key('recoveryDismiss')), findsNothing);
    expect(find.textContaining('Última sessão'), findsNothing);
    expect(
      session.commands.where(
        (command) => ['play', 'playPause', 'unmute'].contains(command.$1),
      ),
      isEmpty,
    );
  });

  testWidgets('choosing a video removes the pending restore button', (
    tester,
  ) async {
    final session = FakeYouTubeSession()
      ..state = const YouTubeMediaState(
        videoId: 'different-video',
        title: 'Vídeo escolhido',
        hasVideo: true,
        duration: 180,
      );
    await tester.pumpWidget(
      StudioVisualApp(
        recoveryRepository: _PendingVideoRepository(),
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    session.state = const YouTubeMediaState();
    session.notifyListeners();
    await tester.pump();
    session.state = const YouTubeMediaState(
      videoId: 'different-video',
      title: 'Vídeo escolhido',
      hasVideo: true,
      duration: 180,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    expect(find.text('Restaurar vídeo'), findsNothing);
    expect(session.disposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fechar ajustes deixa vídeo e botão, sem fixação separada', (
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
    expect(find.byKey(const Key('recoveryRestore')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPinVideo')), findsNothing);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('visualFullscreenSurface')), findsOneWidget);
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('visualPlayerPinVideo')), findsNothing);
    expect(session.disposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mesmo WebView permanece montado nas secções e ao fechar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _TrackedBrowserSession();
    var creations = 0;
    await tester.pumpWidget(
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () {
          creations++;
          return session;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeBrowserViewport')), findsOneWidget);
    final browser = find.byType(_BrowserView);
    final mountedView = tester.state(browser);
    await tester.tap(find.byKey(const Key('browserResultAction')));
    await tester.pump();
    expect(session.browserTaps, 1);
    await tester.pumpAndSettle();
    final surface = find.byKey(const Key('visualFullscreenSurface'));
    final closedHeight = tester.getSize(surface).height;
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, closedHeight);
    for (final section in ['practice', 'chords', 'setlist']) {
      await tester.tap(find.byKey(Key('unifiedSection$section')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
      expect(identical(tester.state(browser), mountedView), isTrue);
      expect(session.viewMounts, 1);
      expect(session.viewDisposals, 0);
    }
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, closedHeight);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(identical(tester.state(browser), mountedView), isTrue);
    expect(creations, 1);
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
      onPressed: () {
        widget.session.browserTaps++;
        widget.session.state = const YouTubeMediaState();
        widget.session.notifyListeners();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.session.state = const YouTubeMediaState(
            videoId: 'aqz-KE-bpKQ',
            title: 'Vídeo de estudo',
            hasVideo: true,
            duration: 180,
          );
          widget.session.notifyListeners();
        });
      },
      child: const Text('Abrir resultado do YouTube'),
    ),
  );
}
