import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/media/local_media_importer.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';
import 'package:transpose_mobile/practice_controller.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'fixtures/audio_probe_source.dart';

/// Run only through the prebuilt-APK QA wrapper. The Android applicationId must
/// be com.example.transpose_mobile.qa; no presets/recovery databases are used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <String, dynamic>{'passed': false};

  void report(String key, Map<String, dynamic> value) {
    evidence[key] = value;
    evidence['passed'] =
        (evidence['native'] as Map?)?['passed'] == true &&
        (evidence['webview'] as Map?)?['passed'] == true;
    binding.reportData = Map<String, dynamic>.of(evidence);
    debugPrint('TRANSPONO_PRACTICE ${jsonEncode(binding.reportData)}');
  }

  testWidgets(
    'real Android audio completes confirmed progressive repetitions',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
        throw StateError('Refusing probe outside the isolated QA application');
      }
      final directory = await Directory('${support.path}/practice-probes')
          .create(recursive: true);
      final isolated = await directory.createTemp('run-');
      final player = MainPlayerController(
        local: LocalPlayerController(
          importer: LocalMediaImporter(supportDirectory: () async => isolated),
        ),
      );
      final practice = PracticeController(player);
      final steps = <int>[];
      final events = <Map<String, Object?>>[];
      String? lastEvent;
      void observe() {
        if (practice.running && !steps.contains(practice.currentPercent)) {
          steps.add(practice.currentPercent);
        }
        final signature =
            '${practice.status.name}:${practice.currentPercent}:'
            '${practice.totalRepetitions}:${practice.stepRepetitions}';
        if (lastEvent == signature) return;
        lastEvent = signature;
        events.add({
          'status': practice.status.name,
          'percent': practice.currentPercent,
          'total': practice.totalRepetitions,
          'stepRepetitions': practice.stepRepetitions,
          'epoch': player.loopObservation?.epoch,
          'count': player.loopObservation?.count,
          'positionMs': player.position.inMilliseconds,
        });
      }

      practice.addListener(observe);

      Future<void> waitFor(
        bool Function() predicate,
        String description, {
        int seconds = 15,
      }) async {
        final deadline = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          if (predicate()) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        throw StateError(
          '$description timed out: status=${practice.status}; '
          'message=${practice.message}; player=${player.message}; '
          'position=${player.position}; count=${player.loopObservation?.count}; '
          'epoch=${player.loopObservation?.epoch}; events=$events',
        );
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ListenableBuilder(
                  listenable: practice,
                  builder: (context, _) => Text(
                    'QA isolado · treino progressivo\n'
                    '${practice.status.name} · ${practice.currentPercent}%\n'
                    '${practice.totalRepetitions} voltas confirmadas',
                  ),
                ),
              ),
            ),
          ),
        );
        await player.loadSample();
        await waitFor(
          () => player.loaded && !player.busy && player.loopObservation != null,
          'native loop telemetry',
        );
        final source = player.sourceKey;
        expect(source, contains(isolated.path));
        expect(player.playing, isFalse);
        await player.seek(const Duration(seconds: 2));
        await player.markA();
        await player.seek(const Duration(milliseconds: 2800));
        await player.markB();
        if (!player.loopEnabled) await player.toggleLoop();
        await player.changeSpeed(.5);
        await player.seek(const Duration(milliseconds: 2600));
        expect(player.loopObservation!.count, 0);
        final partialEpoch = player.loopObservation!.epoch;
        await player.playPause();
        await waitFor(
          () =>
              player.position.inMilliseconds >= 1950 &&
              player.position.inMilliseconds <= 2300,
          'first partial traversal returned to A',
        );
        expect(player.loopObservation!.epoch, partialEpoch);
        expect(
          player.loopObservation!.count,
          0,
          reason: 'The partial 2.6–2.8 s pass must not count as 2.0–2.8 s.',
        );
        await player.pause();
        report('native', {
          'passed': false,
          'partialSeekExcluded': true,
          'events': events,
        });

        await practice.start(
          const PracticePlan(
            startPercent: 60,
            targetPercent: 70,
            incrementPercent: 5,
            repetitionsPerStep: 2,
          ),
        );
        await waitFor(() => practice.running, 'practice running');
        await waitFor(
          () => practice.totalRepetitions == 1,
          'first complete repetition',
        );
        await practice.pause();
        await waitFor(() => !player.playing, 'practice pause');
        final pausedTotal = practice.totalRepetitions;
        final pausedPosition = player.position;
        final pausedCount = player.loopObservation!.count;
        for (int i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(practice.status, PracticeStatus.paused);
        expect(practice.totalRepetitions, pausedTotal);
        expect(player.loopObservation!.count, pausedCount);
        expect(
          (player.position - pausedPosition).inMilliseconds.abs(),
          lessThan(150),
        );
        await practice.resume();
        await waitFor(
          () => practice.status == PracticeStatus.completed && !player.playing,
          'three confirmed stages complete and pause',
          seconds: 30,
        );
        expect(steps, [60, 65, 70]);
        expect(practice.totalRepetitions, 6);
        expect(practice.stepRepetitions, 2);
        expect(practice.currentPercent, 70);
        expect(player.speed, closeTo(.7, .0001));
        expect(player.sourceKey, source);
        expect(player.markerA, const Duration(seconds: 2));
        expect(player.markerB, const Duration(milliseconds: 2800));
        expect(player.loopEnabled, isTrue);
        final completed = practice.snapshot!;
        expect(completed.status, PracticeStatus.completed);
        report('native', {
          'passed': true,
          'partialSeekExcluded': true,
          'pauseHeld': true,
          'steps': steps,
          'totalRepetitions': practice.totalRepetitions,
          'finalPercent': practice.currentPercent,
          'completedPaused': !player.playing,
          'snapshot': completed.toJson(),
          'events': events,
        });
      } catch (error) {
        report('native', {
          'passed': false,
          'error': error.toString(),
          'events': events,
        });
        rethrow;
      } finally {
        practice.removeListener(observe);
        practice.dispose();
        await player.pause();
        await player.local.close();
        await tester.pumpWidget(const SizedBox.shrink());
        player.dispose();
        // Only the freshly minted QA fixture is removed; no broad directory,
        // presets, snapshot store or existing media is touched.
        final sample = File(
          '${isolated.path}/transpono_media/qa-tone-440-v1.wav',
        );
        if (await sample.exists()) await sample.delete();
        final media = sample.parent;
        if (await media.exists() && await media.list().isEmpty) {
          await media.delete();
        }
        if (await isolated.exists() && await isolated.list().isEmpty) {
          await isolated.delete();
        }
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'offline WebView confirms real seeking events without phantom repetitions',
    (tester) async {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: WebViewWidget(controller: controller)),
          ),
        );
        await controller.loadHtmlString(
          '<!doctype html><html><head><meta name="viewport" '
          'content="width=device-width,initial-scale=1"></head>'
          '<body>Transpono · prova sintética offline</body></html>',
          baseUrl: 'https://m.youtube.com/watch?v=transpono-probe',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        await tester.pump();
        await controller.runJavaScript(audioProbeSource);
        await controller.runJavaScript(
          await rootBundle.loadString('assets/web/transpono_media.js'),
        );
        await controller.runJavaScript(_webLoopProbe);
        dynamic result;
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (result == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          dynamic value = await controller.runJavaScriptReturningResult(
            'JSON.stringify(window.__practiceProbeResult || null)',
          );
          for (int i = 0; value is String && i < 2; i++) {
            value = jsonDecode(value);
          }
          result = value;
        }
        expect(result, isA<Map>());
        final data = Map<String, dynamic>.from(result as Map);
        report('webview', data);
        expect(data['error'], isNull);
        expect(data['passed'], isTrue);
      } catch (error) {
        report('webview', {'passed': false, 'error': error.toString()});
        rethrow;
      } finally {
        await controller.runJavaScript(
          'window.TransponoMedia?.dispose(); '
          'window.TransponoAudioProbe?.cleanup();',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

const _webLoopProbe = r'''
(async () => {
  const video = document.querySelector('video');
  const bridge = window.TransponoMedia;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const check = (value, description) => { if (!value) throw new Error(description); };
  const wait = async (test, description, milliseconds = 6000) => {
    const end = performance.now() + milliseconds;
    while (performance.now() < end) {
      if (test()) return;
      await sleep(30);
    }
    throw new Error(description + ' timed out: ' + JSON.stringify(bridge.snapshot()));
  };
  const seek = async seconds => {
    await bridge.command({action:'seekTo', value:seconds});
    await wait(() => !video.seeking && Math.abs(video.currentTime - seconds) < .05,
      'seek ' + seconds);
    await sleep(40); // Allow queued seeking/seeked events to reach the bridge.
  };
  try {
    await wait(() => video.readyState >= 3, 'generated WAV ready');
    await bridge.command({action:'pause'});
    await seek(2);
    await bridge.command({action:'markA'});
    await seek(2.8);
    await bridge.command({action:'markB'});
    await seek(2);
    await bridge.command({action:'speed', value:.6});
    check(bridge.snapshot().loopEventsSupported, 'Missing loop event capability');
    const baseline = bridge.snapshot().loopCount;
    await bridge.command({action:'playPause'});
    await wait(() => bridge.snapshot().loopCount >= baseline + 2, 'two complete real loops');
    await bridge.command({action:'pause'});
    const pausedCount = bridge.snapshot().loopCount;
    await sleep(700);
    check(bridge.snapshot().loopCount === pausedCount, 'Pause advanced count');
    const epoch = bridge.snapshot().loopEpoch;
    await seek(2.6);
    check(bridge.snapshot().loopEpoch > epoch, 'External seek did not change epoch');
    const partialCount = bridge.snapshot().loopCount;
    await bridge.command({action:'playPause'});
    await wait(() => video.currentTime < 2.3 && !video.seeking, 'partial pass return');
    await bridge.command({action:'pause'});
    check(bridge.snapshot().loopCount === partialCount, 'Partial traversal was counted');
    document.body.classList.add('ad-showing'); // Synthetic fixture only; not a real ad.
    const ad = bridge.snapshot();
    check(ad.isAd && !ad.playbackReady && !ad.loopEnabled, 'Ad context was not suspended');
    await sleep(500);
    check(bridge.snapshot().loopCount === partialCount, 'Ad context advanced count');
    document.body.classList.remove('ad-showing');
    window.__practiceProbeResult = {
      passed: true, offlineSyntheticWav: true, realSeekEvents: true,
      completeLoops: pausedCount - baseline, pausedCountHeld: true,
      partialSeekExcluded: true, simulatedAdSuspended: true, snapshot: bridge.snapshot()
    };
  } catch (error) {
    window.__practiceProbeResult = {passed:false, error:String(error), snapshot:bridge.snapshot()};
  } finally {
    await bridge.command({action:'pause'});
  }
})();
''';
