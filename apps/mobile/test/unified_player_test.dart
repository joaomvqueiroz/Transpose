import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('fechado mostra só vídeo e Abrir ajustes', (tester) async {
    await tester.pumpWidget(const StudioVisualApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsOneWidget);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('unifiedSectionchords')), findsNothing);
    expect(find.byKey(const Key('unifiedPitchUp')), findsNothing);

    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedYouTubeSearch')), findsNothing);
    expect(find.byKey(const Key('unifiedFullscreen')), findsNothing);
    expect(find.text('Fechar ajustes'), findsNothing);
    expect(find.byKey(const Key('unifiedMore')), findsNothing);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    expect(find.byKey(const Key('unifiedSectionchords')), findsOneWidget);
    expect(find.byKey(const Key('unifiedSectionpractice')), findsOneWidget);
    expect(find.byKey(const Key('transponoWordmark')), findsNothing);
    final activeTab = tester.widget<OutlinedButton>(
      find.byKey(const Key('unifiedSectionchords')),
    );
    expect(activeTab.style!.backgroundColor!.resolve({}), Colors.white);
    final closeButton = tester.widget<IconButton>(
      find.byKey(const Key('visualMainAdjustments')),
    );
    expect(closeButton.tooltip, 'Fechar ajustes');
    expect(find.byKey(const Key('unifiedSectioninstruments')), findsNothing);
    expect(find.byKey(const Key('unifiedChooseChord')), findsOneWidget);
    expect(find.byKey(const Key('unifiedSpeedSlider')), findsNothing);
    expect(find.byKey(const Key('unifiedLoopToggle')), findsNothing);

    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedPracticeScroll')), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsNothing);
    expect(find.byKey(const Key('unifiedChooseChord')), findsNothing);
    expect(find.byKey(const Key('unifiedSpeedSlider')), findsOneWidget);
    expect(find.byKey(const Key('unifiedLoopToggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedPracticeScroll')), findsNothing);
    expect(find.byKey(const Key('visualPlayerMenu')), findsNothing);
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedPracticeScroll')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('YouTube usa transporte nativo e mantém a sessão', (
    tester,
  ) async {
    final session = FakeYouTubeSession();
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
    session.state = const YouTubeMediaState(
      videoId: 'unified-video',
      title: 'Música escolhida',
      hasVideo: true,
      duration: 180,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtubeUseInPlayer')), findsNothing);
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualPlayerPlay')), findsNothing);
    expect(find.byKey(const Key('visualPlayerBack10')), findsNothing);
    expect(find.byKey(const Key('unifiedLocalSeek')), findsNothing);
    expect(find.byKey(const Key('unifiedPitchUp')), findsOneWidget);
    expect(find.byKey(const Key('unifiedSpeedSlider')), findsNothing);
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    final speed = tester.widget<Slider>(
      find.byKey(const Key('unifiedSpeedSlider')),
    );
    expect(speed.min, .25);
    expect(speed.max, 2);
    expect(find.byKey(const Key('unifiedSpeedPreset100')), findsNothing);
    expect(find.byKey(const Key('visualPracticePause')), findsNothing);
    await tester.tap(find.byKey(const Key('unifiedSectionchords')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    expect(creations, 1);
    expect(session.disposed, isFalse);
    expect(find.byKey(const Key('visualMainMediaViewport')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('colunas adicionais são acessíveis ao arrastar a faixa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StudioVisualApp());
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const Key('visualMainMediaViewport'));
    final mediaHeight = tester.getSize(viewport).height;
    final strip = find.byKey(const Key('unifiedSectionStrip'));
    await tester.drag(strip, const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('unifiedSectionsetlist')));
    await tester.tap(find.byKey(const Key('unifiedSectionsetlist')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedSetlist')), findsOneWidget);
    expect(find.byKey(const Key('collectionAddCurrent')), findsOneWidget);
    expect(find.byKey(const Key('unifiedMore')), findsNothing);
    expect(find.byKey(const Key('setlistAddCurrent')), findsNothing);
    expect(find.byKey(const Key('setlistPrevious')), findsOneWidget);

    expect(find.byKey(const Key('unifiedSectionmetronome')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('unifiedSectionpractice')));
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practiceProgressionContent')), findsNothing);
    expect(find.byKey(const Key('practiceMetronomeContent')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('practiceProgression')));
    await tester.tap(find.byKey(const Key('practiceProgression')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practiceProgressionContent')), findsOneWidget);
    await tester.tap(find.byKey(const Key('practiceProgression')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practiceProgressionContent')), findsNothing);
    expect(find.byKey(const Key('metronomePlayback')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('practiceMetronome')));
    await tester.tap(find.byKey(const Key('practiceMetronome')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('metronomePlayback')), findsOneWidget);
    await tester.tap(find.byKey(const Key('practiceMetronome')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('metronomePlayback')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('unifiedSectionaudioSettings')),
    );
    await tester.tap(find.byKey(const Key('unifiedSectionaudioSettings')));
    await tester.pumpAndSettle();
    expect(find.text('Repor tom, velocidade e loop'), findsOneWidget);
    expect(find.byKey(const Key('audioMidSlider')), findsOneWidget);
    expect(find.byKey(const Key('audioDelaySlider')), findsOneWidget);

    expect(find.byKey(const Key('unifiedSectiontuner')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('audioTuner')));
    await tester.tap(find.byKey(const Key('audioTuner')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tunerMicrophoneToggle')), findsOneWidget);

    expect(tester.getSize(viewport).height, mediaHeight);
    expect(tester.takeException(), isNull);
  });
}
