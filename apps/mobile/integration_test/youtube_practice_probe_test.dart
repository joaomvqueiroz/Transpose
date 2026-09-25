import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/practice_controller.dart';
import 'package:transpose_mobile/practice_progression_card.dart';
import 'package:transpose_mobile/practice_session.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

/// Live-network QA, not a synthetic substitute for YouTube. Rendered search
/// results are selected in the real browser; practice uses production widgets,
/// the existing shared player and the actual WebView audio/loop bridge.
/// Run only with tool/run_youtube_practice_probe.ps1: production is never a
/// test target, and Flutter Driver's automatic uninstall must stay disabled.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real YouTube advances confirmed practice loops and retains its session',
    (tester) async {
      // This guard precedes app mounting, browser creation and any preferences.
      final support = await getApplicationSupportDirectory();
      if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
        throw StateError('Refusing probe outside the isolated QA application');
      }
      binding.testTextInput.register();
      final session = _TrackedYouTubeSession();
      int factories = 0;
      final player = MainPlayerController(
        youtubeFactory: () {
          factories++;
          return session;
        },
      );
      PracticeController? practice;
      final deadline = DateTime.now().add(const Duration(seconds: 225));
      final evidence = <String, dynamic>{
        'passed': false,
        'isolatedQa': true,
        'liveYouTube': true,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      };
      final events = <Map<String, Object?>>[];
      final taps = <Map<String, Object?>>[];
      final steps = <int>[];
      String stage = 'mount';
      String? lastEvent;
      bool browserDiagnosticsAttached = false;
      final browserDiagnostics = <String, Object?>{};
      evidence['browserDiagnostics'] = browserDiagnostics;

      Map<String, Object?> mediaState() => {
        'videoId': session.media.videoId,
        'playing': player.playing,
        'muted': player.muted,
        'isAd': session.media.isAd,
        'pitch': player.pitch,
        'pitchStatus': session.media.pitchStatus,
        'pitchMessage': _safeMessage(session.media.pitchMessage),
        'playerMessage': _safeMessage(player.message),
        'busy': player.busy,
        'speed': player.speed,
        'positionMs': player.position.inMilliseconds,
        'aMs': player.markerA?.inMilliseconds,
        'bMs': player.markerB?.inMilliseconds,
        'loop': player.loopEnabled,
        'loopEventsSupported': session.media.loopEventsSupported,
        'ready': player.loopObservation?.ready,
        'epoch': player.loopObservation?.epoch,
        'count': player.loopObservation?.count,
      };
      session.diagnostic = mediaState;

      void observe() {
        final current = practice;
        if (current == null) return;
        if (current.running && !steps.contains(current.currentPercent)) {
          steps.add(current.currentPercent);
        }
        final signature =
            '${current.status.name}:${current.currentPercent}:'
            '${current.totalRepetitions}:${current.stepRepetitions}';
        if (signature == lastEvent) return;
        lastEvent = signature;
        events.add({
          'status': current.status.name,
          'percent': current.currentPercent,
          'total': current.totalRepetitions,
          'stepRepetitions': current.stepRepetitions,
          'media': mediaState(),
        });
      }

      Future<dynamic> read(String expression) async {
        dynamic value = await session.controller.runJavaScriptReturningResult(
          'JSON.stringify($expression)',
        );
        for (int i = 0; value is String && i < 2; i++) {
          value = jsonDecode(value);
        }
        return value;
      }

      Future<void> captureBrowserEvidence(String label) async {
        if (!browserDiagnosticsAttached) return;
        try {
          browserDiagnostics[label] = await read(
            'window.__transponoPracticeEvents?.snapshot() || null',
          );
        } on Object catch (error) {
          browserDiagnostics[label] = {'error': _safeMessage(error.toString())};
        }
      }

      Future<void> waitFor(
        String label,
        Future<bool> Function() condition, {
        int seconds = 20,
      }) async {
        stage = label;
        final stageEnd = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(stageEnd) &&
            DateTime.now().isBefore(deadline)) {
          try {
            if (await condition()) return;
          } on Object {
            // A document navigation can invalidate the JavaScript context.
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        throw StateError('Timed out in $label');
      }

      Future<void> tap(String key) async {
        final keyed = find.byKey(Key(key));
        // An expanded tile's centre is in its children, not its header.
        final target = key == 'practicePlanConfiguration'
            ? find.descendant(
                of: keyed,
                matching: find.text('Configurar plano'),
              )
            : keyed;
        await waitFor('control available: $key', () async {
          await tester.pump();
          if (target.evaluate().isEmpty) return false;
          final widget = tester.widget(target);
          if (widget is IconButton) return widget.onPressed != null;
          if (widget is ButtonStyleButton) return widget.onPressed != null;
          return true;
        });
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 100));
        final bounds = tester.getRect(target);
        final record = <String, Object?>{
          'key': key,
          'at': DateTime.now().toUtc().toIso8601String(),
          'before': mediaState(),
          'hitTestable': target.hitTestable().evaluate().isNotEmpty,
          'bounds': {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.width,
            'height': bounds.height,
          },
        };
        taps.add(record);
        expect(
          target.hitTestable(),
          findsOneWidget,
          reason: '$key must be tappable after scrolling, not moving/clipped.',
        );
        await tester.tap(target);
        await tester.pump();
        record['afterDispatch'] = mediaState();
      }

      Future<void> fill(String key, String value) async {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(target, value);
        await tester.pump();
      }

      Future<void> refreshUntil(
        String label,
        bool Function(YouTubeMediaState media) condition, {
        int seconds = 20,
      }) => waitFor(label, () async {
        await session.refresh();
        return condition(session.media);
      }, seconds: seconds);

      Future<void> hold(Duration duration) async {
        final end = DateTime.now().add(duration);
        while (DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      }

      try {
        await tester.pumpWidget(StudioVisualApp(playerController: player));
        await tap('visualPlayerSearch');
        await waitFor('browser initialized', () async => session.starts == 1);
        await fill('youtubeSearchInput', 'Big Buck Bunny Blender');
        await tap('youtubeSearchSubmit');
        // Fresh QA consent may be rejected. Never log in, modify an account,
        // bypass an advertisement or directly request a hidden media URL.
        await waitFor('rendered search thumbnails', () async {
          await session.controller.runJavaScript(r'''
            (() => {
              const reject = Array.from(document.querySelectorAll('button'))
                .find(b => /^(Reject all|Rejeitar tudo|Rejeitar todos)$/i.test(b.innerText.trim()));
              if (reject) reject.click();
            })();
          ''');
          return await read(
                'document.querySelectorAll(\'a[href*="/watch?v="] img\').length > 0',
              ) ==
              true;
        }, seconds: 45);
        evidence['searchThumbnails'] = await read(
          'document.querySelectorAll(\'a[href*="/watch?v="] img\').length',
        );
        await session.controller.runJavaScript('''
          (() => {
            const links = Array.from(document.querySelectorAll('a[href*="/watch?v="]'));
            const link = links.find(a => a.href.includes('aqz-KE-bpKQ')) || links[0];
            if (!link) throw new Error('No rendered YouTube result available');
            link.click();
          })();
        ''');
        await refreshUntil(
          'selected video',
          (media) => media.hasVideo && media.duration > 25,
          seconds: 30,
        );
        // Passive observation only. Never override play/pause, visibility or
        // the site's policies to make this diagnostic scenario pass.
        await session.controller.runJavaScript(_passiveVideoDiagnostic);
        browserDiagnosticsAttached = true;
        await captureBrowserEvidence('beforeUseInPlayer');
        await tap('youtubeUseInPlayer');
        await waitFor(
          'main panel mounted after selection',
          () async =>
              find.byKey(const Key('visualPlayerPlay')).evaluate().isNotEmpty &&
              find.byKey(const Key('youtubeUseInPlayer')).evaluate().isEmpty &&
              !player.busy,
        );
        await refreshUntil(
          'content ready after advertisements',
          (media) => !media.isAd && media.playbackReady,
          seconds: 45,
        );
        // Metadata and !paused can precede the first playable frame. Wait for
        // actual content readiness before observing the reparented view and
        // deciding its one explicit Play intent. Never retry Play in a polling
        // loop to hide a transport failure.
        await hold(const Duration(milliseconds: 300));
        await session.refresh();
        evidence['afterMainPanelSettled'] = mediaState();
        await captureBrowserEvidence('afterMainPanelSettled');
        final requestPlay = !player.playing || player.muted;
        evidence['requestedInitialMainPlay'] = requestPlay;
        if (requestPlay) await tap('visualPlayerPlay');
        await captureBrowserEvidence('afterInitialPlayDecision');
        await refreshUntil(
          'unmuted playback',
          (media) =>
              media.playing &&
              !media.muted &&
              !media.isAd &&
              media.playbackReady,
        );
        stage = 'actual content position advances before pitch';
        final initialPosition = player.position.inMilliseconds;
        final initialVideoId = session.media.videoId;
        await hold(const Duration(milliseconds: 1200));
        await session.refresh();
        evidence['beforePitchPlaybackAdvance'] = {
          'initialPositionMs': initialPosition,
          'advancedMs': player.position.inMilliseconds - initialPosition,
          'media': mediaState(),
        };
        await captureBrowserEvidence('beforePitchPlaybackAdvance');
        expect(session.media.videoId, initialVideoId);
        expect(player.playing, isTrue);
        expect(player.muted, isFalse);
        expect(session.media.isAd, isFalse);
        expect(
          player.position.inMilliseconds - initialPosition,
          greaterThanOrEqualTo(250),
          reason: 'A transient !paused flag is not confirmed playback.',
        );
        // This confirms browser/player state, not a microphone measurement.
        evidence['unmutedPlaybackConfirmed'] = true;
        final initialPitch = player.pitch;
        await tap('visualPlayerPitchUp');
        await refreshUntil(
          'pitch acknowledged',
          (media) =>
              media.pitchStatus == 'active' ||
              media.pitchStatus == 'unavailable',
          seconds: 25,
        );
        expect(
          session.media.pitchStatus,
          'active',
          reason: 'The actual YouTube pitch bridge must be available.',
        );
        expect(player.pitch, initialPitch + 1);
        evidence['pitchAcknowledged'] = mediaState();
        await captureBrowserEvidence('pitchAcknowledged');

        await tap('visualPlayerPlay');
        await refreshUntil('paused for markers', (media) => !media.playing);
        // Exact positions use the same controller invoked by the slider. The
        // marker buttons themselves are exercised through their visible UI.
        await player.seek(const Duration(seconds: 20));
        await refreshUntil(
          'seek to A',
          (media) => (media.position - 20).abs() < .15 && media.playbackReady,
        );
        await tap('visualPlayerMarkA');
        await player.seek(const Duration(seconds: 22));
        await refreshUntil(
          'seek to B',
          (media) => (media.position - 22).abs() < .15 && media.playbackReady,
        );
        await tap('visualPlayerMarkB');
        await refreshUntil(
          'confirmed A-B telemetry',
          (media) =>
              media.loopEnabled &&
              media.loopEventsSupported &&
              media.loopA != null &&
              media.loopB != null &&
              (media.loopA! - 20).abs() < .15 &&
              (media.loopB! - 22).abs() < .15,
        );

        final videoId = session.media.videoId;
        final token = DateTime.now().microsecondsSinceEpoch.toString();
        await session.controller.runJavaScript('''
          window.__transponoPracticeDocument = ${jsonEncode(token)};
          window.__transponoPracticeVideo = document.querySelector('video.html5-main-video') || document.querySelector('video');
        ''');
        final startCount = session.starts;
        final searchCount = session.searches;
        final viewCount = session.views;
        final reloadCount = session.reloads;
        Future<void> assertSameSession(String label) async {
          await session.refresh();
          expect(factories, 1, reason: label);
          expect(session.starts, startCount, reason: label);
          expect(session.searches, searchCount, reason: label);
          expect(session.views, viewCount, reason: label);
          expect(session.reloads, reloadCount, reason: label);
          expect(session.media.videoId, videoId, reason: label);
          expect(
            await read('window.__transponoPracticeDocument'),
            token,
            reason: '$label reloaded the document',
          );
          expect(
            await read(
              '''window.__transponoPracticeVideo ===
            (document.querySelector('video.html5-main-video') || document.querySelector('video'))''',
            ),
            isTrue,
            reason: '$label replaced the selected media element',
          );
        }

        await tap('visualTabpractice');
        await waitFor(
          'practice card',
          () async =>
              find.byType(PracticeProgressionCard).evaluate().isNotEmpty,
        );
        final realPractice = tester
            .widget<PracticeProgressionCard>(
              find.byType(PracticeProgressionCard),
            )
            .controller;
        practice = realPractice;
        realPractice.addListener(observe);
        await tap('practicePlanConfiguration');
        await fill('practicePlanStartPercent', '60');
        await fill('practicePlanTargetPercent', '70');
        await fill('practicePlanIncrement', '5');
        await fill('practicePlanRepetitionsPerStep', '2');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tap('practicePlanConfiguration');
        // The collapsed expansion tile changes scroll extents while animating.
        // Finish that bounded animation before ensureVisible locates Start;
        // never invoke its callback directly or retry a missed Start tap.
        await hold(const Duration(milliseconds: 400));
        await tap('practicePlanStart');
        await waitFor(
          'start intent accepted',
          () async => realPractice.status != PracticeStatus.notStarted,
          seconds: 3,
        );
        expect(realPractice.plan.startPercent, 60);
        expect(realPractice.plan.targetPercent, 70);
        expect(realPractice.plan.incrementPercent, 5);
        expect(realPractice.plan.repetitionsPerStep, 2);
        await waitFor(
          'first complete repetition',
          () async =>
              realPractice.running && realPractice.totalRepetitions == 1,
          seconds: 15,
        );
        await tap('practicePlanPause');
        await waitFor(
          'practice paused',
          () async =>
              realPractice.status == PracticeStatus.paused && !player.playing,
        );
        final pausedTotal = realPractice.totalRepetitions;
        final pausedCount = player.loopObservation!.count;
        await hold(const Duration(milliseconds: 1200));
        expect(realPractice.totalRepetitions, pausedTotal);
        expect(player.loopObservation!.count, pausedCount);
        expect(player.playing, isFalse);
        evidence['pauseHeld'] = true;
        await tap('practicePlanResume');
        await waitFor('practice resumed', () async => realPractice.running);
        await tap('visualTabplayer');
        await tap('visualPlayerFullscreen');
        await waitFor(
          'active practice fullscreen mounted',
          () async => find
              .byKey(const Key('visualFullscreenSurface'))
              .evaluate()
              .isNotEmpty,
        );
        await assertSameSession('active practice to fullscreen');
        evidence['activePracticeFullscreenEntered'] = true;
        await tap('visualFullscreenBack');
        await waitFor(
          'active practice fullscreen exited',
          () async => find
              .byKey(const Key('visualFullscreenSurface'))
              .evaluate()
              .isEmpty,
        );
        await tap('visualTabpractice');
        await assertSameSession('active practice returned to practice');
        expect(
          tester
              .widget<PracticeProgressionCard>(
                find.byType(PracticeProgressionCard),
              )
              .controller,
          same(realPractice),
        );
        await waitFor(
          'six completed repetitions and final pause',
          () async =>
              realPractice.status == PracticeStatus.completed &&
              !player.playing,
          seconds: 35,
        );
        expect(steps, [60, 65, 70]);
        expect(realPractice.totalRepetitions, 6);
        expect(realPractice.stepRepetitions, 2);
        expect(realPractice.currentPercent, 70);
        expect(player.speed, closeTo(.7, .0001));
        expect(player.pitch, initialPitch + 1);
        expect(player.loopEnabled, isTrue);
        evidence['completed'] = {
          'steps': List<int>.of(steps),
          'totalRepetitions': realPractice.totalRepetitions,
          'targetPercent': realPractice.currentPercent,
          'paused': !player.playing,
          'media': mediaState(),
        };

        // A manual speed choice suspends automation. Explicit transport pause
        // then navigation must not cause the old plan to auto-resume.
        await tap('practicePlanStart');
        await waitFor(
          'restart for manual override',
          () async => realPractice.running,
        );
        await tap('visualTabplayer');
        await tap('visualPlayerSpeed075');
        await waitFor(
          'manual speed suspends progression',
          () async =>
              realPractice.status == PracticeStatus.paused &&
              (player.speed - .75).abs() < .01,
        );
        if (player.playing) await tap('visualPlayerPlay');
        await refreshUntil('explicit manual pause', (media) => !media.playing);
        final manualTotal = realPractice.totalRepetitions;
        await tap('visualPlayerFullscreen');
        await waitFor(
          'manually paused fullscreen mounted',
          () async => find
              .byKey(const Key('visualFullscreenSurface'))
              .evaluate()
              .isNotEmpty,
        );
        await assertSameSession('manually paused fullscreen');
        await tap('visualFullscreenBack');
        await waitFor(
          'manually paused fullscreen exited',
          () async => find
              .byKey(const Key('visualFullscreenSurface'))
              .evaluate()
              .isEmpty,
        );
        await tap('visualTabpractice');
        await assertSameSession('manually paused practice');
        await hold(const Duration(milliseconds: 1200));
        expect(realPractice.status, PracticeStatus.paused);
        expect(realPractice.totalRepetitions, manualTotal);
        expect(player.speed, closeTo(.75, .01));
        expect(player.playing, isFalse);
        evidence['manualOverride'] = {
          'automationPaused': true,
          'noAutoplayOnNavigation': true,
          'repetitionsHeld': true,
          'media': mediaState(),
        };
        await tap('practicePlanStop');
        expect(realPractice.status, PracticeStatus.aborted);
        expect(player.playing, isFalse);
        evidence['ownership'] = {
          'factories': factories,
          'starts': session.starts,
          'searches': session.searches,
          'webViewBuilds': session.views,
          'reloads': session.reloads,
          'documentPreserved': true,
          'mediaElementPreserved': true,
          'practiceControllerPreserved': true,
        };
        expect(tester.takeException(), isNull);
        evidence['passed'] = true;
      } on Object catch (error) {
        evidence['failedStage'] = stage;
        // Platform failures can contain URLs. Evidence never retains those,
        // cookies, full DOM/account text or raw media locations.
        evidence['failure'] = _safeMessage(error.toString());
        evidence['failureMedia'] = mediaState();
        evidence['practiceStatus'] = practice?.status.name;
        evidence['practiceMessage'] = _safeMessage(practice?.message);
        await captureBrowserEvidence('failure');
        rethrow;
      } finally {
        practice?.removeListener(observe);
        await captureBrowserEvidence('final');
        evidence['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        evidence['events'] = events;
        evidence['taps'] = taps;
        evidence['commands'] = List<Map<String, Object?>>.of(session.commands);
        binding.reportData = evidence;
        debugPrint('TRANSPONO_YOUTUBE_PRACTICE ${jsonEncode(evidence)}');
        try {
          if (browserDiagnosticsAttached) {
            await session.controller.runJavaScript(
              'window.__transponoPracticeEvents?.cleanup();',
            );
          }
        } on Object {
          // Read-only listeners may already be gone with the old document.
        }
        try {
          await player.pause();
        } on Object {
          // Network/navigation failure may already have destroyed the view.
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        player.dispose();
        binding.testTextInput.unregister();
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _TrackedYouTubeSession extends WebViewYouTubeSession {
  int starts = 0, searches = 0, views = 0, reloads = 0;
  Map<String, Object?> Function()? diagnostic;
  final commands = <Map<String, Object?>>[];

  @override
  Future<void> command(String action, [num? value]) async {
    final record = <String, Object?>{
      'index': commands.length,
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'value': value,
      'before': diagnostic?.call(),
    };
    commands.add(record);
    try {
      await super.command(action, value);
      // Completion means that the production bridge returned; the scenario
      // still separately checks whether the requested media state was applied.
      record['result'] = 'returned';
    } on Object catch (error) {
      record['result'] = 'threw';
      record['error'] = _safeMessage(error.toString());
      rethrow;
    } finally {
      record['after'] = diagnostic?.call();
      debugPrint('TRANSPONO_YOUTUBE_PRACTICE_COMMAND ${jsonEncode(record)}');
    }
  }

  @override
  Future<void> start(Uri uri) {
    starts++;
    return super.start(uri);
  }

  @override
  Future<void> search(String query) {
    searches++;
    return super.search(query);
  }

  @override
  Future<void> reload() {
    reloads++;
    return super.reload();
  }

  @override
  Widget buildView() {
    views++;
    return super.buildView();
  }
}

String? _safeMessage(String? value) {
  if (value == null) return null;
  final sanitized = value.replaceAll(
    RegExp(r'https?://[^\s]+'),
    '[url omitted]',
  );
  return sanitized.length > 1500 ? sanitized.substring(0, 1500) : sanitized;
}

const _passiveVideoDiagnostic = r'''
(() => {
  window.__transponoPracticeEvents?.cleanup();
  const selected = document.querySelector('video.html5-main-video') || document.querySelector('video');
  if (!selected) throw new Error('No selected video for passive diagnostic');
  const events = [];
  const measure = type => {
    const rect = selected.getBoundingClientRect();
    const style = getComputedStyle(selected);
    const viewport = window.visualViewport;
    return {
      type, atMs: Date.now(), performanceMs: Math.round(performance.now()),
      currentTime: selected.currentTime, readyState: selected.readyState,
      networkState: selected.networkState, paused: selected.paused,
      seeking: selected.seeking, ended: selected.ended, muted: selected.muted,
      volume: selected.volume, connected: selected.isConnected,
      selectedElementStillCurrent: selected ===
        (document.querySelector('video.html5-main-video') || document.querySelector('video')),
      visibility: document.visibilityState, documentHidden: document.hidden,
      documentHasFocus: document.hasFocus(),
      rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height,
        top: rect.top, right: rect.right, bottom: rect.bottom, left: rect.left},
      viewport: {width: innerWidth, height: innerHeight,
        visualWidth: viewport?.width ?? null, visualHeight: viewport?.height ?? null,
        offsetLeft: viewport?.offsetLeft ?? null, offsetTop: viewport?.offsetTop ?? null,
        scale: viewport?.scale ?? null},
      scroll: {x: scrollX, y: scrollY},
      style: {display: style.display, visibility: style.visibility, opacity: style.opacity}
    };
  };
  const record = event => {
    events.push(measure(typeof event === 'string' ? event : event.type));
    if (events.length > 40) events.shift();
  };
  const types = ['pause', 'play', 'playing', 'waiting', 'stalled', 'seeking', 'seeked', 'ended', 'emptied'];
  for (const type of types) selected.addEventListener(type, record, {passive: true});
  document.addEventListener('visibilitychange', record, {passive: true});
  window.addEventListener('resize', record, {passive: true});
  window.addEventListener('scroll', record, {passive: true});
  record('attached');
  window.__transponoPracticeEvents = {
    snapshot: () => ({current: measure('snapshot'), events: events.slice()}),
    cleanup: () => {
      for (const type of types) selected.removeEventListener(type, record);
      document.removeEventListener('visibilitychange', record);
      window.removeEventListener('resize', record);
      window.removeEventListener('scroll', record);
    }
  };
})();
''';
