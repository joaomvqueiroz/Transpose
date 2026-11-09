import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/home_button_visibility.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fake_youtube_session.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Abrir ajustes encolhe numa seta ao descer a página', (
    tester,
  ) async {
    addTearDown(() => pageScrolledDown.value = false);
    await tester.pumpWidget(const StudioVisualApp());
    await tester.pumpAndSettle();
    expect(find.text('Abrir ajustes'), findsOneWidget);
    pageScrolledDown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Abrir ajustes'), findsNothing);
    expect(
      find.byKey(const Key('visualOpenAdjustmentsCompact')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('visualOpenAdjustmentsCompact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visualCloseAdjustments')), findsOneWidget);
    pageScrolledDown.value = false;
    await tester.pumpAndSettle();
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
    expect(find.byKey(const Key('visualCloseAdjustments')), findsOneWidget);
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
    expect(closeButton.tooltip, 'Expandir ou fechar ajustes');
    expect(find.byKey(const Key('unifiedSectioninstruments')), findsNothing);
    expect(find.byKey(const Key('unifiedChooseChord')), findsOneWidget);
    final pitchButtonsInCifra =
        tester.getCenter(find.byKey(const Key('unifiedPitchUp'))).dx -
        tester.getCenter(find.byKey(const Key('unifiedPitchDown'))).dx;
    expect(pitchButtonsInCifra, lessThan(230));
    expect(
      tester.getTopLeft(find.byKey(const Key('unifiedChooseChord'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('unifiedPitchCard'))).dy,
      ),
    );
    expect(find.byKey(const Key('unifiedSpeedSlider')), findsNothing);
    expect(find.byKey(const Key('unifiedLoopToggle')), findsNothing);

    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unifiedPracticeScroll')), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsNothing);
    expect(find.byKey(const Key('unifiedChooseChord')), findsNothing);
    expect(find.byKey(const Key('unifiedSpeedSlider')), findsOneWidget);
    expect(find.byKey(const Key('unifiedLoopToggle')), findsOneWidget);
    final pitchButtonsInTreino =
        tester.getCenter(find.byKey(const Key('unifiedPitchUp'))).dx -
        tester.getCenter(find.byKey(const Key('unifiedPitchDown'))).dx;
    expect(pitchButtonsInTreino, lessThan(230));
    expect(find.text('TEMPO MASTER'), findsNothing);
    expect(find.text('VELOCIDADE'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
    expect(find.text('Repetir trecho continuamente'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('unifiedMarkA'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('unifiedLoopToggle'))).dy,
      ),
    );
    expect(tester.getSize(find.byKey(const Key('unifiedMarkA'))).height, 36);
    expect(tester.getSize(find.byKey(const Key('unifiedMarkB'))).height, 36);
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adjustmentsClose')));
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
    expect(speed.min, 0);
    expect(speed.max, 1);
    expect(speed.value, .5);
    speed.onChanged!(.7);
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byKey(const Key('unifiedSpeedSlider'))).value,
      closeTo(.7, .0001),
    );
    tester
        .widget<Slider>(find.byKey(const Key('unifiedSpeedSlider')))
        .onChangeEnd!(.7);
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byKey(const Key('unifiedSpeedSlider'))).value,
      closeTo(.7, .0001),
    );
    tester
        .widget<Slider>(find.byKey(const Key('unifiedSpeedSlider')))
        .onChanged!(.53);
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byKey(const Key('unifiedSpeedSlider'))).value,
      .5,
    );
    expect(find.text('1.00×'), findsOneWidget);
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

  testWidgets('quatro colunas cabem sem arrastar a faixa', (tester) async {
    tester.view.physicalSize = const Size(350, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const StudioVisualApp());
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const Key('visualMainMediaViewport'));
    final mediaHeight = tester.getSize(viewport).height;
    final strip = find.byKey(const Key('unifiedSectionStrip'));
    final stripRect = tester.getRect(strip);
    for (final tab in ['chords', 'practice', 'setlist', 'audioSettings']) {
      final rect = tester.getRect(find.byKey(Key('unifiedSection$tab')));
      expect(rect.left, greaterThanOrEqualTo(stripRect.left));
      expect(rect.right, lessThanOrEqualTo(stripRect.right));
    }
    expect(tester.takeException(), isNull);
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

  testWidgets('áudio mostra controles compactos e reposição individual', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    session.state = const YouTubeMediaState(
      videoId: 'audio-controls',
      hasVideo: true,
      duration: 180,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('unifiedSectionaudioSettings')),
    );
    await tester.tap(find.byKey(const Key('unifiedSectionaudioSettings')));
    await tester.pumpAndSettle();

    for (final name in <String>[
      'Gain',
      'Bass',
      'Mid',
      'Treble',
      'Chorus',
      'Feedback',
      'Delay',
      'Reverb',
    ]) {
      expect(find.byKey(Key('audio${name}Slider')), findsOneWidget);
      expect(find.byKey(Key('audio${name}SliderReset')), findsOneWidget);
    }
    expect(find.textContaining('Graves ('), findsNothing);
    expect(find.textContaining('Médios ('), findsNothing);
    expect(find.textContaining('Agudos ('), findsNothing);
    final bass = find.byKey(const Key('audioBassSlider'));
    final bassReset = find.byKey(const Key('audioBassSliderReset'));
    final bassRow = tester.getRect(bass);
    final resetRect = tester.getRect(bassReset);
    expect(resetRect.left, greaterThan(bassRow.right - 2));
    tester.widget<Slider>(bass).onChangeEnd?.call(4);
    await tester.pumpAndSettle();
    await tester.ensureVisible(bassReset);
    await tester.tap(bassReset);
    await tester.pumpAndSettle();
    expect(
      session.commands,
      containsAllInOrder(<(String, num?)>[('bass', 4), ('bass', 0)]),
    );
  });

  testWidgets('respostas antigas não desfazem ajustes de áudio mais recentes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = _DelayedAudioSession();
    await tester.pumpWidget(
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    session.state = const YouTubeMediaState(
      videoId: 'audio-order',
      hasVideo: true,
      duration: 180,
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('unifiedSectionaudioSettings')),
    );
    await tester.tap(find.byKey(const Key('unifiedSectionaudioSettings')));
    await tester.pumpAndSettle();

    final bass = find.byKey(const Key('audioBassSlider'));
    final mid = find.byKey(const Key('audioMidSlider'));
    tester.widget<Slider>(bass).onChangeEnd?.call(4);
    tester.widget<Slider>(mid).onChangeEnd?.call(6);
    await tester.pump();
    session.pending[1].complete();
    await tester.pump();
    session.pending[0].complete();
    await tester.pump();
    expect(tester.widget<Slider>(bass).value, 4);
    expect(tester.widget<Slider>(mid).value, 6);

    tester.widget<Slider>(bass).onChangeEnd?.call(2);
    tester.widget<Slider>(bass).onChangeEnd?.call(7);
    await tester.pump();
    session.pending[3].complete();
    await tester.pump();
    session.pending[2].complete();
    await tester.pump();
    expect(tester.widget<Slider>(bass).value, 7);
    session.state = const YouTubeMediaState(
      videoId: 'audio-order',
      hasVideo: true,
      duration: 180,
      audioEffects: {'bass': 0, 'mid': 0},
    );
    session.notifyListeners();
    await tester.pump();
    expect(
      tester.widget<Slider>(bass).value,
      0,
      reason:
          'Same-song video replacement must not retain obsolete slider values',
    );
    session.state = const YouTubeMediaState(
      videoId: 'audio-order',
      hasVideo: true,
      duration: 180,
      audioEffects: {'bass': 7, 'mid': 6},
    );
    session.notifyListeners();
    await tester.pump();
    expect(tester.widget<Slider>(bass).value, 7);
    tester.widget<Slider>(bass).onChanged?.call(3);
    session.notifyListeners();
    await tester.pump();
    expect(
      tester.widget<Slider>(bass).value,
      3,
      reason: 'Polling cannot interrupt an active slider drag',
    );
    tester.widget<Slider>(bass).onChangeEnd?.call(3);
    session.pending.last.completeError(StateError('unsupported source'));
    await tester.pump();
    expect(
      tester.widget<Slider>(bass).value,
      7,
      reason: 'Rejected adjustment returns to the engine value',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('modulação compacta mostra tom estimado em Cifra e Treino', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = FakeYouTubeSession();
    await tester.pumpWidget(
      StudioVisualApp(
        openSearchWhenEmpty: true,
        youtubeSessionFactory: () => session,
      ),
    );
    await tester.pumpAndSettle();
    session.state = const YouTubeMediaState(
      videoId: 'key-song',
      hasVideo: true,
      duration: 180,
      keyRoot: 0,
      keyMode: 'major',
      keyStatus: 'ready',
    );
    session.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pumpAndSettle();
    final pitchCard = find.byKey(const Key('unifiedPitchCard'));
    expect(tester.getSize(pitchCard).height, lessThan(90));
    expect(find.byKey(const Key('unifiedPitchReset')), findsNothing);
    expect(find.text('Tom estimado: C maior'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unifiedSectionpractice')));
    await tester.pumpAndSettle();
    expect(tester.getSize(pitchCard).height, lessThan(90));
    expect(find.byKey(const Key('unifiedPitchReset')), findsNothing);
    expect(find.text('Tom estimado: C maior'), findsOneWidget);
    session.state = const YouTubeMediaState(
      videoId: 'key-song',
      hasVideo: true,
      duration: 180,
      pitch: 2,
      keyRoot: 0,
      keyMode: 'major',
      keyStatus: 'ready',
    );
    session.notifyListeners();
    await tester.pump();
    expect(find.text('Tom estimado: D maior'), findsOneWidget);
  });
}

class _DelayedAudioSession extends FakeYouTubeSession {
  final List<Completer<void>> pending = <Completer<void>>[];
  final Map<String, int> versions = <String, int>{};

  @override
  Future<void> command(String action, [num? value]) async {
    final completer = Completer<void>();
    final version = (versions[action] ?? 0) + 1;
    versions[action] = version;
    pending.add(completer);
    await completer.future;
    if (versions[action] != version) return;
    await super.command(action, value);
  }
}
