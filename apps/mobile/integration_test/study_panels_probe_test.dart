import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:player_core/player_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transpose_mobile/chord_sheet.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/player_presets.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

/// Exercises production Android output/storage through the new studio panels.
/// Only two uniquely identified QA presets and a QA-private sample are created.
/// Cleanup never removes or overwrites existing user records or source files.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'practice chords stage and collection controls on Android',
    (tester) async {
      binding.testTextInput.register();
      final player = MainPlayerController();
      final store = PlayerPresetStore();
      final completed = <String>[];
      final createdIds = <String>[];
      final suffix = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
      final firstId = 'qa-study-first-$suffix';
      final secondId = 'qa-study-second-$suffix';
      File? qaFile;
      String? qaSource;
      bool passed = false;
      Map<String, Object?>? chordEvidence;

      void report([String? step]) {
        if (step != null) completed.add(step);
        binding.reportData = <String, dynamic>{
          'passed': passed,
          'completed': List<String>.of(completed),
          'qaPresetIds': [firstId, secondId],
          'pitch': player.pitch,
          'speed': player.speed,
          'positionMs': player.position.inMilliseconds,
          'playing': player.playing,
          'loop': player.loopEnabled,
          'chords': chordEvidence,
        };
        debugPrint('TRANSPONO_STUDY_PANELS ${jsonEncode(binding.reportData)}');
      }

      Future<void> waitFor(
        FutureOr<bool> Function() condition,
        String label, {
        int seconds = 15,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (await condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError(
          '$label timed out; completed=$completed; busy=${player.busy}, message=${player.message}',
        );
      }

      Future<void> tapKey(String key) async {
        if (key.startsWith('visualTab') &&
            find.byKey(Key(key)).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('visualPlayerMenu')));
          await tester.pump(const Duration(milliseconds: 250));
        }
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> tapText(String label) async {
        final finder = find.text(label);
        await tester.ensureVisible(finder);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 250));
      }

      Future<void> idle() => waitFor(() => !player.busy, 'player idle');

      Future<void> practiceSeek(int ms) async {
        await idle();
        final finder = find.byKey(const Key('practiceSeek'));
        await tester.ensureVisible(finder);
        final slider = tester.widget<Slider>(finder);
        expect(slider.onChanged, isNotNull);
        slider.onChanged!(ms.toDouble());
        slider.onChangeEnd!(ms.toDouble());
        await waitFor(
          () =>
              !player.busy && (player.position.inMilliseconds - ms).abs() < 150,
          'practice seek',
        );
      }

      Future<void> collectionItemVisible(String id) async {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('collectionOpen-$id')),
          260,
          maxScrolls: 180,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pump(const Duration(milliseconds: 200));
      }

      PlayerPreset preset(String id, String name, double pitch) => PlayerPreset(
        id: id,
        name: name,
        title: 'QA Transpono · Estudo',
        sourceId: 'qa-study-$suffix',
        locator: qaFile!.uri.toString(),
        youtube: false,
        pitch: pitch,
        speed: .8,
        positionMs: 1000,
        aMs: 1000,
        bMs: 3000,
        loop: false,
      );

      try {
        await tester.pumpWidget(
          StudioVisualApp(playerController: player, presetStore: store),
        );
        await player.loadSample();
        await waitFor(
          () => player.loaded && player.canPitch && !player.busy,
          'load sample',
        );
        final original = File.fromUri(Uri.parse(player.local.locator!));
        final target = File('${original.parent.path}/qa-study-$suffix.wav');
        expect(await target.exists(), isFalse);
        qaFile = await original.copy(target.path);
        await player.local.load(
          LocalFileSource(
            id: 'qa-study-$suffix',
            displayName: 'QA Transpono · Estudo',
            locator: qaFile.uri,
          ),
        );
        await waitFor(() => player.loaded && !player.busy, 'QA source load');
        qaSource = player.sourceKey;
        expect(qaSource, contains('qa-study-$suffix.wav'));
        report('production-android-audio-unique-qa-source');

        await tapKey('visualTabpractice');
        await practiceSeek(1000);
        await tapKey('visualPracticeMarkA');
        await waitFor(
          () => player.markerA?.inMilliseconds == 1000 && !player.busy,
          'practice mark A',
        );
        await practiceSeek(3000);
        await tapKey('visualPracticeMarkB');
        await waitFor(
          () => player.markerB?.inMilliseconds == 3000 && !player.busy,
          'practice mark B',
        );
        await tapKey('practiceLoopToggle');
        await waitFor(
          () => player.loopEnabled && !player.busy,
          'practice loop enable',
        );
        final speedFinder = find.byKey(const Key('practiceSpeed'));
        await tester.ensureVisible(speedFinder);
        final speed = tester.widget<Slider>(speedFinder);
        speed.onChanged!(.8);
        speed.onChangeEnd!(.8);
        await waitFor(
          () => !player.busy && (player.speed - .8).abs() < .001,
          'practice speed',
        );
        await tapKey('visualPracticePause');
        await waitFor(() => player.playing && !player.busy, 'practice play');
        await Future<void>.delayed(const Duration(milliseconds: 2700));
        await tester.pump();
        expect(player.position.inMilliseconds, inInclusiveRange(850, 3150));
        await tapKey('visualPracticePause');
        await waitFor(() => !player.playing && !player.busy, 'practice pause');
        await tapKey('practiceReturnA');
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - 1000).abs() < 150,
          'return A',
        );
        await tapKey('practiceClearLoop');
        await waitFor(
          () =>
              player.markerA == null &&
              player.markerB == null &&
              !player.loopEnabled &&
              !player.busy,
          'clear loop',
        );
        report('practice-markers-loop-speed-play-pause-return-clear');

        await player.changePitch(2);
        await idle();
        await tapKey('visualTabchords');
        await waitFor(
          () =>
              tester
                  .widget<FilledButton>(find.byKey(const Key('chordsEdit')))
                  .onPressed !=
              null,
          'chord editor ready',
        );
        await tapKey('chordsEdit');
        await tester.enterText(
          find.byKey(const Key('chordsTimelineInput')),
          '00:00 C\n00:02 Am7\n00:04 G/B',
        );
        await tester.enterText(
          find.byKey(const Key('chordsNotesInput')),
          'QA Estudo $suffix',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 600));
        await tapKey('chordsSave');
        await waitFor(
          () => find.byKey(const Key('chordsTimelineInput')).evaluate().isEmpty,
          'chord editor saved',
        );
        final savedSheet = await ChordSheetStore().read(qaSource);
        expect(savedSheet.timeline, '00:00 C\n00:02 Am7\n00:04 G/B');
        expect(savedSheet.notes, 'QA Estudo $suffix');
        expect(find.text('D'), findsWidgets);
        expect(find.text('Bm7'), findsWidgets);
        await tapKey('chordCue1');
        await waitFor(
          () =>
              !player.busy &&
              (player.position.inMilliseconds - 2000).abs() < 150,
          'chord cue seek',
        );
        expect(
          tester.widget<ListTile>(find.byKey(const Key('chordCue1'))).selected,
          isTrue,
        );
        await tapKey('chordsPlay');
        await waitFor(() => player.playing && !player.busy, 'chords play');
        await tapKey('chordsPlay');
        await waitFor(() => !player.playing && !player.busy, 'chords pause');
        chordEvidence = {
          'timelineSaved': savedSheet.timeline,
          'notesMatch': savedSheet.notes == 'QA Estudo $suffix',
          'currentCue': 1,
          'transposition': 2,
        };
        report('manual-chords-edit-persist-transpose-cue-seek-play');

        await store.save(
          preset(firstId, 'QA Estudo 1 $suffix', -1),
          setlist: true,
        );
        createdIds.add(firstId);
        await store.save(
          preset(secondId, 'QA Estudo 2 $suffix', 3),
          setlist: true,
        );
        createdIds.add(secondId);
        await tapKey('visualTabstage');
        await waitFor(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'stage collection read',
        );
        await tapKey('stageSetlist');
        await collectionItemVisible(secondId);
        await tapKey('collectionMenu-$secondId');
        await tapText('Renomear');
        await tester.enterText(
          find.byKey(const Key('collectionRenameInput')),
          'QA Palco renomeado $suffix',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 500));
        await tapKey('collectionConfirmRename');
        await waitFor(
          () async =>
              (await store.list(setlist: true))
                  .singleWhere((p) => p.id == secondId)
                  .name ==
              'QA Palco renomeado $suffix',
          'rename persisted',
        );
        await collectionItemVisible(secondId);
        await tapKey('collectionUp-$secondId');
        await waitFor(() async {
          final items = await PlayerPresetStore().list(setlist: true);
          return items.indexWhere((p) => p.id == secondId) + 1 ==
              items.indexWhere((p) => p.id == firstId);
        }, 'setlist reordered persistently');
        await collectionItemVisible(secondId);
        await tapKey('collectionOpen-$secondId');
        await waitFor(
          () =>
              !player.busy &&
              player.lastRestoreSucceeded &&
              player.pitch == 3 &&
              (player.speed - .8).abs() < .001,
          'collection applies stored second preset',
        );
        expect(player.playing, isFalse);
        report('setlist-rename-reorder-persist-apply-without-autoplay');

        await tapKey('visualTabstage');
        await waitFor(
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
          'stage read restored setlist',
        );
        await tapKey('visualStageNext');
        await waitFor(
          () => !player.busy && player.pitch == -1,
          'stage next distinct preset same source',
        );
        await tapKey('visualStagePrevious');
        await waitFor(
          () => !player.busy && player.pitch == 3,
          'stage previous same source preset',
        );
        await tapKey('visualStagePitchUp');
        await waitFor(() => !player.busy && player.pitch == 4, 'stage pitch');
        await tapKey('visualStageExecute');
        await waitFor(() => !player.busy && player.playing, 'stage play');
        await tapKey('visualStageExecute');
        await waitFor(() => !player.busy && !player.playing, 'stage pause');
        await tapKey('visualStageLock');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('visualStageExecute')))
              .onPressed,
          isNull,
        );
        await tester.longPress(find.byKey(const Key('visualStageLock')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('visualStageExecute')))
              .onPressed,
          isNotNull,
        );
        report('stage-next-previous-same-media-pitch-transport-lock');

        await tapKey('stageSetlist');
        await collectionItemVisible(firstId);
        await tapKey('collectionMenu-$firstId');
        await tapText('Remover');
        await tapText('Cancelar');
        expect(
          (await store.list(setlist: true)).any((p) => p.id == firstId),
          isTrue,
        );
        await tapKey('collectionMenu-$firstId');
        await tapText('Remover');
        await tapKey('collectionConfirmDelete');
        await waitFor(
          () async =>
              !(await store.list(setlist: true)).any((p) => p.id == firstId),
          'confirmed remove persisted',
        );
        report('collection-remove-cancel-and-confirm-only-qa-item');
        passed = true;
        report();
      } finally {
        await player.pause();
        await player.local.close();
        await tester.pumpWidget(const SizedBox.shrink());
        player.dispose();
        // Exact QA IDs only: never clear or replace the user's collections.
        for (final id in createdIds) {
          if ((await store.list(setlist: true)).any((p) => p.id == id)) {
            await store.delete(id, setlist: true);
          }
        }
        if (qaSource != null && qaSource.contains('qa-study-$suffix.wav')) {
          await SharedPreferencesAsync().remove(
            'transpono.chords.v1.${base64Url.encode(utf8.encode(qaSource))}',
          );
        }
        if (qaFile != null &&
            qaFile.path.endsWith('qa-study-$suffix.wav') &&
            await qaFile.exists()) {
          await qaFile.delete();
        }
        completed.add('only-own-qa-presets-chords-file-cleaned');
        binding.reportData = <String, dynamic>{
          ...?binding.reportData,
          'passed': passed,
          'completed': List<String>.of(completed),
          'qaArtifactsRemoved': true,
        };
        debugPrint('TRANSPONO_STUDY_PANELS ${jsonEncode(binding.reportData)}');
        binding.testTextInput.unregister();
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
