import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/media/local_media_importer.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';
import 'package:transpose_mobile/session_snapshot_store.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

/// Physical, two-process recovery check; not a widget rebuild masquerading as
/// process death. Run the seed phase until READY_TO_KILL, force-stop ONLY this
/// QA app with adb, then run verify with the same RECOVERY_PROBE_ID. Pass
/// --keep-app-running to both flutter drive commands (default cleanup uninstalls
/// the target). Integration targets get an isolated .qa applicationId. The first
/// driver's disconnect is expected. All files live in a QA-private directory;
/// production recovery, collections, chords and original media are untouched.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('RECOVERY_PROBE_PHASE');
  const runId = String.fromEnvironment(
    'RECOVERY_PROBE_ID',
    defaultValue: 'process-death-v1',
  );

  testWidgets(
    'durable session survives an external Android force-stop',
    (tester) async {
      expect(phase, anyOf('seed', 'verify'));
      expect(RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(runId), isTrue);
      final support = await getApplicationSupportDirectory();
      // Refuse to touch a production sandbox if build isolation regresses.
      expect(support.path, contains('/com.example.transpose_mobile.qa/'));
      final qaRoot = Directory('${support.path}/transpono_qa_recovery/$runId');
      final manifest = File('${qaRoot.path}/probe_manifest.json');
      final databasePath = '${qaRoot.path}/qa_recovery.sqlite';
      final repository = SessionSnapshotStore(databasePath: databasePath);
      final player = MainPlayerController(
        local: LocalPlayerController(
          importer: LocalMediaImporter(supportDirectory: () async => qaRoot),
        ),
      );
      final completed = <String>[];
      var passed = false;
      var cleanedUp = false;
      Map<String, Object?> evidence = <String, Object?>{};

      void report(String step) {
        completed.add(step);
        binding.reportData = <String, dynamic>{
          'phase': phase,
          'runId': runId,
          'applicationId': 'com.example.transpose_mobile.qa',
          'processId': pid,
          'passed': passed,
          'qaArtifactsRemoved': cleanedUp,
          'completed': List<String>.of(completed),
          ...evidence,
        };
        debugPrint(
          'TRANSPONO_RECOVERY_PROBE ${jsonEncode(binding.reportData)}',
        );
      }

      Future<void> waitFor(
        FutureOr<bool> Function() condition,
        String label, {
        int seconds = 20,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (await condition()) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError(
          '$label timed out: loaded=${player.loaded}, busy=${player.busy}, '
          'playing=${player.playing}, message=${player.message}',
        );
      }

      Future<void> mount() => tester.pumpWidget(
        StudioVisualApp(
          playerController: player,
          recoveryRepository: repository,
        ),
      );

      try {
        if (phase == 'seed') {
          // Reusing an unfinished run requires verification, not destructive
          // reseeding. Use a different explicit run ID to start another run.
          expect(await manifest.exists(), isFalse);
          expect(await File(databasePath).exists(), isFalse);
          await qaRoot.create(recursive: true);
          final preferencesBefore = await _preferencesFingerprint();
          await mount();
          await waitFor(
            () =>
                find.byKey(const Key('visualPlayerMenu')).evaluate().isNotEmpty,
            'studio startup',
          );
          // Give the empty startup read a chance to complete before selecting
          // media. The production coordinator must also tolerate this race.
          await tester.pump(const Duration(milliseconds: 400));
          await player.loadSample();
          await waitFor(() => player.loaded && !player.busy, 'durable sample');
          expect(player.local.locator, startsWith(qaRoot.uri.toString()));
          expect(
            await File.fromUri(Uri.parse(player.local.locator!)).exists(),
            isTrue,
          );
          await player.changePitch(-2);
          await player.changeSpeed(.8);
          await player.local.setLoopMarkers(
            const Duration(seconds: 2),
            const Duration(seconds: 6),
          );
          await player.toggleLoop();
          await player.seek(const Duration(seconds: 3));
          await tester.tap(find.byKey(const Key('visualPlayerMenu')));
          await tester.pump(const Duration(milliseconds: 250));
          await tester.tap(find.byKey(const Key('visualTabpractice')));
          await waitFor(() async {
            final snapshot = (await repository.read()).snapshot;
            return snapshot != null &&
                snapshot.media.pitch == -2 &&
                snapshot.media.speed == .8 &&
                snapshot.media.loop &&
                snapshot.media.aMs == 2000 &&
                snapshot.media.bMs == 6000 &&
                snapshot.media.positionMs == 3000 &&
                snapshot.screen == 'practice';
          }, 'confirmed automatic SQLite checkpoint');
          expect(await _preferencesFingerprint(), preferencesBefore);
          final seedSnapshot = (await repository.read()).snapshot!;
          await manifest.writeAsString(
            jsonEncode(<String, Object?>{
              'runId': runId,
              'processId': pid,
              'preferencesFingerprint': preferencesBefore,
              'mediaLocator': player.local.locator,
              'seedSnapshot': seedSnapshot.toJson(),
            }),
            flush: true,
          );
          report('native-source-imported-and-real-controls-autosaved');
          await player.playPause();
          await waitFor(() => player.playing && !player.busy, 'live output');
          evidence = <String, Object?>{
            'playingAtKillSignal': player.playing,
            'checkpoint': seedSnapshot.toJson(),
            'qaPreferencesUnchanged': true,
          };
          report('ready-for-external-force-stop');
          debugPrint('TRANSPONO_RECOVERY_READY_TO_KILL pid=$pid run=$runId');
          final deadline = DateTime.now().add(const Duration(minutes: 3));
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          fail('Host did not force-stop the app after READY_TO_KILL.');
        } else {
          expect(await manifest.exists(), isTrue);
          final previous =
              jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
          expect(previous['runId'], runId);
          expect(pid, isNot(previous['processId']));
          final recoveredRecord = await repository.read();
          expect(recoveredRecord.writeBlocked, isFalse);
          final expected = recoveredRecord.snapshot!;
          expect(expected.media.locator, previous['mediaLocator']);
          expect(expected.media.pitch, -2);
          expect(expected.media.speed, .8);
          expect(expected.media.aMs, 2000);
          expect(expected.media.bMs, 6000);
          expect(expected.media.loop, isTrue);
          expect(expected.screen, 'practice');
          expect(expected.media.positionMs, inInclusiveRange(2000, 6000));
          expect(player.loaded, isFalse);
          expect(player.playing, isFalse);
          report('new-native-process-read-committed-snapshot');

          final restoration = Stopwatch()..start();
          await mount();
          await waitFor(
            () => player.loaded && !player.busy && player.lastRestoreSucceeded,
            'local startup recovery',
          );
          restoration.stop();
          expect(player.local.locator, expected.media.locator);
          expect(player.pitch, -2);
          expect(player.speed, .8);
          expect(player.markerA, const Duration(seconds: 2));
          expect(player.markerB, const Duration(seconds: 6));
          expect(player.loopEnabled, isTrue);
          expect(player.playing, isFalse);
          expect(
            (player.position.inMilliseconds - expected.media.positionMs).abs(),
            lessThanOrEqualTo(150),
          );
          expect(find.byKey(const Key('visualPracticePause')), findsOneWidget);
          final pausedPosition = player.position;
          for (var check = 0; check < 12; check++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            expect(player.playing, isFalse);
            expect(
              (player.position - pausedPosition).inMilliseconds.abs(),
              lessThanOrEqualTo(20),
            );
          }
          expect(
            await _preferencesFingerprint(),
            previous['preferencesFingerprint'],
          );
          evidence = <String, Object?>{
            'previousProcessId': previous['processId'],
            'differentNativeProcess': true,
            'restoreMilliseconds': restoration.elapsedMilliseconds,
            'measurementScope': 'mount-to-player-ready; database already read',
            'singleRunNotP95': true,
            'storedPositionMs': expected.media.positionMs,
            'restoredPositionMs': player.position.inMilliseconds,
            'pitch': player.pitch,
            'speed': player.speed,
            'loopA': player.markerA?.inMilliseconds,
            'loopB': player.markerB?.inMilliseconds,
            'loopEnabled': player.loopEnabled,
            'screen': expected.screen,
            'playingAfterRestore': player.playing,
            'qaPreferencesUnchanged': true,
          };
          report('same-source-settings-loop-position-screen-restored-paused');
          passed = true;
        }
      } finally {
        // An external force-stop cannot execute Dart's finally. If Dart is
        // still alive (including an unexpected pump error), always stop output.
        await player.pause();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await player.local.close();
        player.dispose();
        await repository.close();
        if (passed) {
          // No recursive deletion: exact, QA-owned paths only. The namespace
          // can retain unexpected files for inspection instead of erasing them.
          final sample = File(
            '${qaRoot.path}/transpono_media/qa-tone-440-v1.wav',
          );
          if (await sample.exists()) await sample.delete();
          if (await sample.parent.exists() &&
              await sample.parent.list().isEmpty) {
            await sample.parent.delete();
          }
          await deleteDatabase(databasePath);
          await manifest.delete();
          if (await qaRoot.exists() && await qaRoot.list().isEmpty) {
            await qaRoot.delete();
          }
          cleanedUp = true;
          report('qa-files-removed-qa-preferences-preserved');
        }
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// A stable non-cryptographic change detector; no user titles/content are copied
/// into the probe evidence or its manifest. It is not a security checksum.
Future<String> _preferencesFingerprint() async {
  final preferences = await SharedPreferencesAsync().getAll();
  final keys = preferences.keys.toList()..sort();
  final serialized = jsonEncode(<String, Object?>{
    for (final key in keys) key: preferences[key],
  });
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(serialized)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return '${keys.length}:${hash.toRadixString(16).padLeft(8, '0')}';
}
