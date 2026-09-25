import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

/// Device probe of the actual principal panel and production audio/storage.
/// Leaves one clearly named QA preset; never clears existing user collections.
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'principal panel controls drive real Android audio and study tools',
    (WidgetTester tester) async {
      // Profile builds do not accept the debug-only text client -1 shortcut.
      // Register the test keyboard so enterText targets the real widget client.
      binding.testTextInput.register();
      final MainPlayerController player = MainPlayerController();
      final PlayerPresetStore presets = _ProbePresetStore();
      final List<String> completed = <String>[];
      final String presetName =
          'QA Player ${DateTime.now().toUtc().toIso8601String()}';
      void report(String step) {
        completed.add(step);
        binding.reportData = <String, dynamic>{
          'completed': List<String>.of(completed),
          'qaPresetName': presetName,
          'pitch': player.pitch,
          'speed': player.speed,
          'positionMs': player.position.inMilliseconds,
          'loop': player.loopEnabled,
        };
        debugPrint('TRANSPONO_MAIN_PANEL ${jsonEncode(binding.reportData)}');
      }

      Future<void> tapKey(String key) async {
        final Finder target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(target);
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> waitFor(
        FutureOr<bool> Function() condition,
        String description, {
        int seconds = 15,
      }) async {
        final DateTime end = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (await condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError(
          '$description: timed out; completed=$completed; '
          'busy=${player.busy}, loaded=${player.loaded}, '
          'playing=${player.playing}, message=${player.message}, '
          'saveDialog=${find.byKey(const Key('presetName')).evaluate().length}, '
          'saveSuccess=${find.text('Tom, velocidade e A/B guardados neste dispositivo.').evaluate().length}, '
          'saveError=${find.text('Não foi possível guardar. Os ajustes atuais continuam ativos.').evaluate().length}',
        );
      }

      Future<void> idle() => waitFor(() => !player.busy, 'command completion');

      Future<void> more(String label) async {
        await tapKey('visualPlayerMore');
        await waitFor(() => find.text(label).evaluate().isNotEmpty, label);
        await tester.ensureVisible(find.text(label));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 350));
      }

      Future<void> seek(int milliseconds) async {
        await idle();
        final Finder finder = find.byKey(const Key('visualPlayerSeek'));
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        final Slider slider = tester.widget<Slider>(finder);
        expect(slider.onChanged, isNotNull);
        expect(slider.onChangeEnd, isNotNull);
        slider.onChanged!(milliseconds.toDouble());
        slider.onChangeEnd!(milliseconds.toDouble());
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - milliseconds).abs() < 200,
          'seek to $milliseconds ms',
        );
      }

      Future<void> closeTool() async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byTooltip('Fechar ferramenta'));
        await tester.pump(const Duration(milliseconds: 400));
      }

      try {
        await tester.pumpWidget(
          StudioVisualApp(playerController: player, presetStore: presets),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(player.loaded, isFalse);
        await more('Carregar áudio de demonstração');
        await waitFor(
          () => player.loaded && player.canPitch && !player.busy,
          'load demonstration audio',
        );
        expect(player.playing, isFalse);
        expect(player.duration.inSeconds, greaterThanOrEqualTo(10));
        final String sourceId = player.local.sourceId;
        final String? locator = player.local.locator;
        report('sample-loaded-from-main-menu');

        await tapKey('visualPlayerDismissTip');
        expect(find.byKey(const Key('visualPlayerDismissTip')), findsNothing);
        await tapKey('visualPlayerPlay');
        await waitFor(
          () => player.playing && player.position.inMilliseconds > 300,
          'play and advance',
        );
        await tapKey('visualPlayerPlay');
        await waitFor(() => !player.playing && !player.busy, 'pause');
        final Duration paused = player.position;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await tester.pump();
        expect((player.position - paused).inMilliseconds.abs(), lessThan(150));
        report('play-pause-confirmed');

        await tapKey('visualPlayerPitchDown');
        await waitFor(() => player.pitch == -1 && !player.busy, 'pitch down');
        await tapKey('visualPlayerPitchUp');
        await waitFor(() => player.pitch == 0 && !player.busy, 'pitch up');
        await tapKey('visualPlayerPitchDown');
        await idle();
        await tapKey('visualPlayerPitchDown');
        await waitFor(() => player.pitch == -2 && !player.busy, 'pitch -2');
        for (final (String, double) speed in <(String, double)>[
          ('075', .75),
          ('085', .85),
          ('100', 1),
        ]) {
          await tapKey('visualPlayerSpeed${speed.$1}');
          await waitFor(
            () => (player.speed - speed.$2).abs() < .001 && !player.busy,
            'speed preset ${speed.$2}',
          );
          expect(player.pitch, -2);
        }
        final Slider speedSlider = tester.widget<Slider>(
          find.byKey(const Key('visualPlayerSpeed')),
        );
        speedSlider.onChanged!(.8);
        speedSlider.onChangeEnd!(.8);
        await waitFor(() => player.speed == .8 && !player.busy, 'speed slider');
        report('pitch-stepper-speed-presets-slider');

        await seek(1000);
        await tapKey('visualPlayerForward10');
        await waitFor(
          () => !player.busy && player.position.inMilliseconds >= 10800,
          'forward 10 seconds',
        );
        await tapKey('visualPlayerBack10');
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - 1000).abs() < 200,
          'back 10 seconds',
        );
        await seek(2000);
        await tapKey('visualPlayerMarkA');
        await waitFor(
          () => player.markerA?.inMilliseconds == 2000 && !player.busy,
          'mark A',
        );
        await seek(4000);
        await tapKey('visualPlayerMarkB');
        await waitFor(
          () => player.markerB?.inMilliseconds == 4000 && !player.busy,
          'mark B',
        );
        await tapKey('visualPlayerLoopToggle');
        await waitFor(() => player.loopEnabled && !player.busy, 'loop enabled');
        await tapKey('visualPlayerPlay');
        await waitFor(() => player.playing && !player.busy, 'loop playback');
        await Future<void>.delayed(const Duration(milliseconds: 3400));
        await tester.pump();
        expect(player.playing, isTrue);
        expect(player.position.inMilliseconds, inInclusiveRange(1800, 4200));
        await tapKey('visualPlayerPlay');
        await waitFor(() => !player.playing && !player.busy, 'pause loop');
        await seek(6000);
        expect(player.loopEnabled, isFalse);
        expect(player.markerA, const Duration(seconds: 2));
        expect(player.markerB, const Duration(seconds: 4));
        report('timeline-skip-loop-outside-seek');

        await tapKey('visualPlayerFullscreen');
        await waitFor(
          () => find
              .byKey(const Key('visualFullscreenSurface'))
              .evaluate()
              .isNotEmpty,
          'fullscreen',
        );
        expect(player.local.sourceId, sourceId);
        expect(player.local.locator, locator);
        expect(player.pitch, -2);
        expect(player.speed, .8);
        expect(player.position.inMilliseconds, inInclusiveRange(5800, 6200));
        await tapKey('visualFullscreenLock');
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<Slider>(find.byKey(const Key('visualFullscreenSeek')))
              .onChanged,
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
        await tapKey('visualFullscreenPlay');
        await waitFor(() => player.playing && !player.busy, 'fullscreen play');
        await tapKey('visualFullscreenPlay');
        await waitFor(
          () => !player.playing && !player.busy,
          'fullscreen pause',
        );
        await tapKey('visualFullscreenBack');
        await tester.pump(const Duration(milliseconds: 400));
        expect(player.local.sourceId, sourceId);
        expect(player.local.locator, locator);
        expect(player.markerA, const Duration(seconds: 2));
        report('fullscreen-shared-source-lock-transport-return');

        await more('Guardar predefinição');
        await waitFor(
          () => find.byKey(const Key('presetName')).evaluate().isNotEmpty,
          'preset name dialog',
        );
        await tester.enterText(find.byKey(const Key('presetName')), presetName);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 800));
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('presetName')))
              .controller!
              .text,
          presetName,
        );
        await tapKey('presetSave');
        await waitFor(
          () async => (await PlayerPresetStore().list()).any(
            (PlayerPreset p) => p.name == presetName,
          ),
          'production storage write',
        );
        final PlayerPreset saved = (await PlayerPresetStore().list())
            .singleWhere((PlayerPreset p) => p.name == presetName);
        expect(saved.pitch, -2);
        expect(saved.speed, .8);
        expect(saved.aMs, 2000);
        expect(saved.bMs, 4000);
        expect(saved.loop, isFalse);
        await player.resetProcessing();
        await idle();
        expect(player.pitch, 0);
        await more('Predefinições guardadas');
        await waitFor(
          () => find.text('Predefinições guardadas').evaluate().isNotEmpty,
          'saved preset list',
        );
        await tester.scrollUntilVisible(
          find.text(presetName),
          250,
          maxScrolls: 100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text(presetName));
        await waitFor(
          () => !player.busy && player.pitch == -2 && player.speed == .8,
          'preset restore',
        );
        expect(player.playing, isFalse);
        expect(player.local.locator, locator);
        expect(player.markerA?.inMilliseconds, saved.aMs);
        expect(player.markerB?.inMilliseconds, saved.bMs);
        report('preset-persisted-read-back-restored-no-autoplay');

        await tapKey('visualPlayerStudyTools');
        await tapKey('visualPlayerTool_metronome');
        await waitFor(
          () =>
              find.byKey(const Key('metronomePlayback')).evaluate().isNotEmpty,
          'metronome sheet',
        );
        await tapKey('metronomePlayback');
        await waitFor(
          () => find.text('Parar metrônomo').evaluate().isNotEmpty,
          'real metronome playback',
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await tapKey('metronomePlayback');
        await waitFor(
          () => find.text('Iniciar metrônomo').evaluate().isNotEmpty,
          'metronome stop',
        );
        await closeTool();
        report('metronome-start-stop');

        await tapKey('visualPlayerTool_tuner');
        await waitFor(
          () => find.text('A4 · Lá 440').evaluate().isNotEmpty,
          'reference tuner sheet',
        );
        await tester.tap(find.text('A4 · Lá 440'));
        await waitFor(
          () => tester
              .widget<ChoiceChip>(
                find.ancestor(
                  of: find.text('A4 · Lá 440'),
                  matching: find.byType(ChoiceChip),
                ),
              )
              .selected,
          'reference tone playback',
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
        await tester.tap(find.text('Parar nota'));
        await waitFor(
          () => !tester
              .widget<ChoiceChip>(
                find.ancestor(
                  of: find.text('A4 · Lá 440'),
                  matching: find.byType(ChoiceChip),
                ),
              )
              .selected,
          'reference tone stop',
        );
        await closeTool();
        report('reference-tuner-start-stop');

        await tapKey('visualPlayerTool_chords');
        await waitFor(
          () => find
              .byKey(const Key('chordProgressionInput'))
              .evaluate()
              .isNotEmpty,
          'chords sheet',
        );
        await tester.enterText(
          find.byKey(const Key('chordProgressionInput')),
          'Dm7 G/B',
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Cm7 F/A'), findsOneWidget);
        await closeTool();
        report('manual-chord-progression-transposed');

        await tapKey('visualPlayerAdvancedTools');
        await waitFor(
          () => find.text('Configurações de áudio').evaluate().isNotEmpty,
          'advanced sheet',
        );
        expect(find.text('Voz · indisponível'), findsOneWidget);
        await tester.ensureVisible(find.text('Concluir'));
        await tester.tap(find.text('Concluir'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(player.playing, isFalse);
        report('advanced-panel-open-close');
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

class _ProbePresetStore extends PlayerPresetStore {
  @override
  Future<void> save(PlayerPreset preset, {bool setlist = false}) async {
    debugPrint(
      'TRANSPONO_PRESET_WRITE ${jsonEncode(<String, Object?>{'nameIsQa': preset.name.startsWith('QA Player'), 'name': preset.name, 'valid': PlayerPreset.parse(preset.toJson()) != null, 'pitch': preset.pitch, 'speed': preset.speed, 'a': preset.aMs, 'b': preset.bMs, 'loop': preset.loop})}',
    );
    try {
      await super.save(preset, setlist: setlist);
      debugPrint('TRANSPONO_PRESET_READ count=${(await list()).length}');
    } on Object catch (error) {
      debugPrint('TRANSPONO_PRESET_ERROR $error');
      rethrow;
    }
  }
}
