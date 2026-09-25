import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

/// Physical Android probe: the real shared player, native audio and storage.
/// Leaves one clearly labelled QA preset; existing collections are untouched.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fullscreen controls operate the existing real audio session',
    (tester) async {
      binding.testTextInput.register();
      final player = MainPlayerController();
      final presets = PlayerPresetStore();
      final completed = <String>[];
      final presetName =
          'QA Fullscreen ${DateTime.now().toUtc().toIso8601String()}';
      String? originalSource;
      String? originalLocator;
      int preservedChecks = 0;

      void report(String step, {bool passed = false}) {
        completed.add(step);
        binding.reportData = <String, dynamic>{
          'passed': passed,
          'completed': List<String>.of(completed),
          'qaPresetName': presetName,
          'sourceId': player.local.sourceId,
          'sourcePreserved':
              player.local.sourceId == originalSource &&
              player.local.locator == originalLocator,
          'sourcePreservedChecks': preservedChecks,
          'pitch': player.pitch,
          'speed': player.speed,
          'positionMs': player.position.inMilliseconds,
          'markerAMs': player.markerA?.inMilliseconds,
          'markerBMs': player.markerB?.inMilliseconds,
          'loop': player.loopEnabled,
          'playing': player.playing,
        };
        debugPrint('TRANSPONO_FULLSCREEN ${jsonEncode(binding.reportData)}');
      }

      Future<void> waitFor(
        FutureOr<bool> Function() predicate,
        String description, {
        int seconds = 15,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (await predicate()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError(
          '$description timed out. completed=$completed; loaded=${player.loaded}; busy=${player.busy}; playing=${player.playing}; position=${player.position}; message=${player.message}',
        );
      }

      Future<void> idle() => waitFor(() => !player.busy, 'audio command');

      Future<void> reveal() async {
        final target = find.byKey(const Key('visualFullscreenReveal'));
        if (target.evaluate().isNotEmpty) {
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      Future<void> tapKey(String key) async {
        if (key.startsWith('visualFullscreen')) await reveal();
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> tapText(String text) async {
        await waitFor(() => find.text(text).evaluate().isNotEmpty, text);
        final target = find.text(text);
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> more(String text) async {
        await tapKey('visualFullscreenMore');
        await tapText(text);
      }

      Future<void> seek(int milliseconds) async {
        await idle();
        await reveal();
        final target = find.byKey(const Key('visualFullscreenSeek'));
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 200));
        final slider = tester.widget<Slider>(target);
        expect(slider.onChanged, isNotNull);
        expect(slider.onChangeEnd, isNotNull);
        // Sends the native slider's drag-completion callbacks exactly; the
        // resulting position is read back from the real Android player.
        slider.onChanged!(milliseconds.toDouble());
        slider.onChangeEnd!(milliseconds.toDouble());
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - milliseconds).abs() < 200,
          'seek $milliseconds',
        );
      }

      void sameSource() {
        expect(player.local.sourceId, originalSource);
        expect(player.local.locator, originalLocator);
        expect(player.isYouTube, isFalse);
        preservedChecks++;
      }

      Future<void> closeTool() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Fechar ferramenta'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const Key('visualFullscreenSurface')),
          findsOneWidget,
        );
        sameSource();
      }

      Future<void> checkLock(String entry) async {
        await tapKey(entry);
        for (final key in <String>[
          'visualFullscreenPlay',
          'visualFullscreenBack10',
          'visualFullscreenForward10',
          'visualFullscreenPitchUp',
          'visualFullscreenSpeedUp',
          'visualFullscreenBack',
        ]) {
          expect(
            tester.widget<IconButton>(find.byKey(Key(key))).onPressed,
            isNull,
            reason: key,
          );
        }
        expect(
          tester
              .widget<Slider>(find.byKey(const Key('visualFullscreenSeek')))
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<Switch>(
                find.byKey(const Key('visualFullscreenLoopToggle')),
              )
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<PopupMenuButton<String>>(
                find.byKey(const Key('visualFullscreenMore')),
              )
              .enabled,
          isFalse,
        );
        await tapKey('visualFullscreenLock');
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
              .onPressed,
          isNull,
        );
        await tester.longPress(find.byKey(const Key('visualFullscreenLock')));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
              .onPressed,
          isNotNull,
        );
      }

      try {
        await tester.pumpWidget(
          StudioVisualApp(playerController: player, presetStore: presets),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tapKey('visualPlayerMore');
        await tapText('Carregar áudio de demonstração');
        await waitFor(
          () => player.loaded && player.canPitch && !player.busy,
          'load local sample',
        );
        originalSource = player.local.sourceId;
        originalLocator = player.local.locator;
        expect(player.playing, isFalse);
        await tapKey('visualPlayerFullscreen');
        expect(
          find.byKey(const Key('visualFullscreenSurface')),
          findsOneWidget,
        );
        sameSource();
        report('enter-fullscreen-preserves-local-source');

        await tapKey('visualFullscreenPitchUp');
        await waitFor(() => !player.busy && player.pitch == 1, 'pitch +1');
        await tapKey('visualFullscreenPitchDown');
        await waitFor(() => !player.busy && player.pitch == 0, 'pitch -1');
        await tapKey('visualFullscreenPitchDown');
        await waitFor(() => !player.busy && player.pitch == -1, 'pitch -1 st');
        await tapKey('visualFullscreenPitchReset');
        await waitFor(
          () => !player.busy && player.pitch == 0,
          'pitch original',
        );
        await tapKey('visualFullscreenSpeedDown');
        await waitFor(
          () => !player.busy && (player.speed - .95).abs() < .001,
          'speed .95',
        );
        await tapKey('visualFullscreenSpeedUp');
        await waitFor(() => !player.busy && player.speed == 1, 'speed 1');
        await tapKey('visualFullscreenSpeed');
        await tapText('0.75×');
        await waitFor(
          () => !player.busy && player.speed == .75,
          'speed preset .75',
        );
        await tapKey('visualFullscreenSpeedReset');
        await waitFor(
          () => !player.busy && player.speed == 1,
          'speed original',
        );
        sameSource();
        report('pitch-up-down-original-speed-fine-preset-original');

        await seek(1000);
        await tapKey('visualFullscreenForward10');
        await waitFor(
          () => !player.busy && player.position.inMilliseconds >= 10800,
          'forward10',
        );
        await tapKey('visualFullscreenBack10');
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - 1000).abs() < 200,
          'back10',
        );
        await seek(2000);
        await tapKey('visualFullscreenMarkA');
        await waitFor(
          () => !player.busy && player.markerA?.inMilliseconds == 2000,
          'markA',
        );
        await seek(4000);
        await tapKey('visualFullscreenMarkB');
        await waitFor(
          () => !player.busy && player.markerB?.inMilliseconds == 4000,
          'markB',
        );
        await tapKey('visualFullscreenLoopToggle');
        await waitFor(() => !player.busy && player.loopEnabled, 'loop on');
        await tapKey('visualFullscreenLoopToggle');
        await waitFor(() => !player.busy && !player.loopEnabled, 'loop off');
        expect(player.markerA, const Duration(seconds: 2));
        expect(player.markerB, const Duration(seconds: 4));
        await tapKey('visualFullscreenLoopToggle');
        await idle();
        await tapKey('visualFullscreenPlay');
        await waitFor(() => !player.busy && player.playing, 'play loop');
        await waitFor(
          () => find
              .byKey(const Key('visualFullscreenReveal'))
              .evaluate()
              .isNotEmpty,
          'auto hide',
          seconds: 10,
        );
        expect(player.playing, isTrue);
        expect(player.position.inMilliseconds, inInclusiveRange(1800, 4200));
        await reveal();
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const Key('visualFullscreenOverlay')),
              )
              .opacity,
          1,
        );
        await tapKey('visualFullscreenPlay');
        await waitFor(() => !player.busy && !player.playing, 'pause');
        final paused = player.position;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        expect((player.position - paused).inMilliseconds.abs(), lessThan(150));
        await seek(6000);
        expect(player.loopEnabled, isFalse);
        expect(player.markerA, const Duration(seconds: 2));
        await tapKey('visualFullscreenClearLoop');
        await waitFor(
          () =>
              !player.busy && player.markerA == null && player.markerB == null,
          'clear markers',
        );
        sameSource();
        report(
          'seek-skip-markers-toggle-loop-play-autohide-reveal-pause-clear',
        );

        await checkLock('visualFullscreenLock');
        await checkLock('visualFullscreenLockSurface');
        sameSource();
        report('both-locks-short-tap-stays-locked-long-hold-unlocks');

        await tapKey('visualFullscreenPitchUp');
        await idle();
        await tapKey('visualFullscreenSpeedDown');
        await idle();
        await seek(2000);
        await tapKey('visualFullscreenMarkA');
        await idle();
        await seek(4000);
        await tapKey('visualFullscreenMarkB');
        await idle();
        await more('Guardar ajustes');
        await waitFor(
          () => find.byKey(const Key('presetName')).evaluate().isNotEmpty,
          'preset dialog',
        );
        await tester.enterText(find.byKey(const Key('presetName')), presetName);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 500));
        await tapKey('presetSave');
        await waitFor(
          () async => (await presets.list()).any((p) => p.name == presetName),
          'persist fullscreen preset',
        );
        final saved = (await PlayerPresetStore().list()).singleWhere(
          (p) => p.name == presetName,
        );
        expect(saved.pitch, 1);
        expect(saved.speed, .95);
        expect(saved.aMs, 2000);
        expect(saved.bMs, 4000);
        await more('Repor tom, velocidade e A–B');
        await waitFor(
          () =>
              !player.busy &&
              player.pitch == 0 &&
              player.speed == 1 &&
              player.markerA == null &&
              player.markerB == null,
          'reset all processing',
        );
        sameSource();
        report('more-save-persists-real-adjustments-reset-clears-processing');

        await more('Metrônomo');
        await waitFor(
          () =>
              find.byKey(const Key('metronomePlayback')).evaluate().isNotEmpty,
          'metronome',
        );
        await tapKey('metronomePlayback');
        await waitFor(
          () => find.text('Parar metrônomo').evaluate().isNotEmpty,
          'metronome started',
        );
        await tapKey('metronomePlayback');
        await waitFor(
          () => find.text('Iniciar metrônomo').evaluate().isNotEmpty,
          'metronome stopped',
        );
        await closeTool();
        await more('Afinador por referência');
        await tapText('A4 · Lá 440');
        await waitFor(
          () => tester
              .widget<ChoiceChip>(
                find.ancestor(
                  of: find.text('A4 · Lá 440'),
                  matching: find.byType(ChoiceChip),
                ),
              )
              .selected,
          'reference tone',
        );
        await tapText('Parar nota');
        await closeTool();
        await more('Acordes');
        await waitFor(
          () => find
              .byKey(const Key('chordProgressionInput'))
              .evaluate()
              .isNotEmpty,
          'manual chord tool',
        );
        await tester.enterText(
          find.byKey(const Key('chordProgressionInput')),
          'Dm7 G/B',
        );
        await tester.pump(const Duration(milliseconds: 250));
        await closeTool();
        await more('Ferramentas de áudio');
        await waitFor(
          () => find.text('Configurações de áudio').evaluate().isNotEmpty,
          'advanced sheet',
        );
        await tapText('Concluir');
        sameSource();
        report('fullscreen-more-metronome-reference-tuner-chords-advanced');

        await tapKey('visualFullscreenBack');
        await waitFor(
          () => find
              .byKey(const Key('visualPlayerFullscreen'))
              .evaluate()
              .isNotEmpty,
          'return to main player',
        );
        sameSource();
        expect(player.playing, isFalse);
        expect(player.pitch, 0);
        expect(player.speed, 1);
        report('return-main-preserves-source-and-paused-state', passed: true);
      } finally {
        await player.pause();
        await player.local.close();
        await tester.pumpWidget(const SizedBox.shrink());
        player.dispose();
        binding.testTextInput.unregister();
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
