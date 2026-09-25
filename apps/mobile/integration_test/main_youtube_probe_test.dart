import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

/// Live-network Android probe of the actual main panel. DOM interaction only
/// selects a rendered search result; playback intents use the Flutter controls.
/// It neither extracts media nor replaces the production audio bridge.
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('main player retains selected YouTube session and real controls', (
    WidgetTester tester,
  ) async {
    // In profile builds, register an actual Flutter text-input client for
    // enterText; the debug-only client -1 bypass is not available on device.
    binding.testTextInput.register();
    final _TrackedYouTubeSession session = _TrackedYouTubeSession();
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 170));
    final Map<String, dynamic> evidence = <String, dynamic>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'passed': false,
    };
    int factoryCalls = 0;
    String stage = 'mount';

    Future<dynamic> read(String expression) async {
      dynamic value = await session.controller.runJavaScriptReturningResult(
        'JSON.stringify($expression)',
      );
      for (int i = 0; value is String && i < 2; i++) {
        value = jsonDecode(value);
      }
      return value;
    }

    Future<dynamic> mediaDiagnostic() => read('''(() => {
      const video = document.querySelector('video.html5-main-video') || document.querySelector('video');
      const rect = video?.getBoundingClientRect();
      return {
        media:window.TransponoMedia?.snapshot() || null,
        visibility:document.visibilityState,
        viewport:{width:innerWidth,height:innerHeight},
        video:video ? {
          paused:video.paused,muted:video.muted,volume:video.volume,
          position:video.currentTime,readyState:video.readyState,
          networkState:video.networkState,srcType:video.currentSrc.split(':')[0],
          rect:rect ? {x:rect.x,y:rect.y,width:rect.width,height:rect.height} : null
        } : null
      };
    })()''');

    Future<void> waitFor(
      String label,
      Future<bool> Function() condition, {
      int seconds = 20,
    }) async {
      stage = label;
      final DateTime stageEnd = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(stageEnd) &&
          DateTime.now().isBefore(deadline)) {
        try {
          if (await condition()) return;
        } on Object {
          // Navigation can destroy its JS context during a read.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      // Keep media evidence on its own short log line: Android logcat may
      // truncate the combined page body before the useful audio state.
      try {
        evidence['failureSnapshot'] = await mediaDiagnostic();
      } on Object catch (error) {
        evidence['failureSnapshot'] = error.toString();
      }
      debugPrint(
        'TRANSPO_MAIN_YOUTUBE_FAILURE_MEDIA ${jsonEncode(<String, dynamic>{'stage': label, 'snapshot': evidence['failureSnapshot']})}',
      );
      dynamic page;
      try {
        page = await read('''({
          url:location.href,
          text:document.body.innerText.slice(0,1000)
        })''');
      } on Object catch (error) {
        page = error.toString();
      }
      throw StateError('Timed out in $label: ${jsonEncode(page)}');
    }

    Future<void> tap(String key) async {
      final Finder target = find.byKey(Key(key));
      await waitFor('control available: $key', () async {
        await tester.pump();
        if (target.evaluate().isEmpty) return false;
        final Widget widget = tester.widget(target);
        if (widget is IconButton) return widget.onPressed != null;
        if (widget is ButtonStyleButton) return widget.onPressed != null;
        if (widget is Switch) return widget.onChanged != null;
        return true;
      });
      final bool traceMedia =
          key == 'visualPlayerPlay' ||
          key == 'visualPlayerPitchUp' ||
          key == 'visualPlayerSpeed075';
      if (traceMedia) {
        debugPrint(
          'TRANSPO_MAIN_TAP_BEFORE_SCROLL ${jsonEncode(<String, dynamic>{'key': key, 'snapshot': await mediaDiagnostic()})}',
        );
      }
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 100));
      if (traceMedia) {
        final Offset center = tester.getCenter(target);
        debugPrint(
          'TRANSPO_MAIN_TAP_AFTER_SCROLL ${jsonEncode(<String, dynamic>{
            'key': key,
            'center': <double>[center.dx, center.dy],
            'snapshot': await mediaDiagnostic(),
          })}',
        );
      }
      await tester.tap(target);
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

    Future<dynamic> snapshot() => read('window.TransponoMedia.snapshot()');

    try {
      await tester.pumpWidget(
        StudioVisualApp(
          youtubeSessionFactory: () {
            factoryCalls++;
            return session;
          },
        ),
      );
      await tap('visualPlayerSearch');
      await waitFor('browser initialized', () async => session.starts == 1);
      await tester.enterText(
        find.byKey(const Key('youtubeSearchInput')),
        'Big Buck Bunny Blender',
      );
      await tap('youtubeSearchSubmit');

      // Reject optional cookies only if the fresh Google consent page asks.
      // Never sign in, alter account preferences or skip advertisements.
      await waitFor('search thumbnails', () async {
        await session.controller.runJavaScript(r'''
          (() => {
            const buttons = Array.from(document.querySelectorAll('button'));
            const reject = buttons.find(b => /^(Reject all|Rejeitar tudo|Rejeitar todos)$/i.test(b.innerText.trim()));
            if (reject) reject.click();
          })();
        ''');
        return await read(
              "document.querySelectorAll('a[href*=\"/watch?v=\"] img').length > 0",
            ) ==
            true;
      }, seconds: 50);
      evidence['search'] = await read('''({
        url:location.href,
        thumbnails:document.querySelectorAll('a[href*="/watch?v="] img').length,
        titles:Array.from(document.querySelectorAll('h3')).slice(0,3).map(x=>x.innerText)
      })''');
      debugPrint(
        'TRANSPO_MAIN_YOUTUBE_SEARCH ${jsonEncode(evidence['search'])}',
      );

      // Click only an existing link from these results. Prefer the Blender
      // Foundation video previously observed by the browser integration probe.
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
        (media) => media.hasVideo && media.duration > 0,
        seconds: 35,
      );
      final String videoId = session.media.videoId;
      expect(videoId, matches(RegExp(r'^[A-Za-z0-9_-]{11}$')));
      final String documentToken = DateTime.now().microsecondsSinceEpoch
          .toString();
      await session.controller.runJavaScript('''
        window.__transponoMainProbeDocument = ${jsonEncode(documentToken)};
        window.__transponoMainProbeVideo = document.querySelector('video.html5-main-video') || document.querySelector('video');
      ''');
      final int startsBeforeMove = session.starts;
      final int searchesBeforeMove = session.searches;
      final int viewsBeforeMove = session.views;
      final int reloadsBeforeMove = session.reloads;

      Future<void> assertSameSession(String label) async {
        await session.refresh();
        expect(factoryCalls, 1, reason: '$label recreated the browser session');
        expect(session.starts, startsBeforeMove, reason: '$label restarted it');
        expect(session.searches, searchesBeforeMove);
        expect(
          session.views,
          viewsBeforeMove,
          reason: '$label rebuilt WebView',
        );
        expect(session.reloads, reloadsBeforeMove);
        expect(session.media.videoId, videoId, reason: label);
        expect(
          await read('window.__transponoMainProbeDocument'),
          documentToken,
          reason: '$label reloaded the document',
        );
        expect(
          await read(
            '''window.__transponoMainProbeVideo ===
            (document.querySelector('video.html5-main-video') || document.querySelector('video'))''',
          ),
          isTrue,
          reason: '$label replaced the selected media element',
        );
      }

      await tap('youtubeUseInPlayer');
      await waitFor('main panel visible', () async {
        return find
            .byKey(const Key('visualPlayerPitchUp'))
            .evaluate()
            .isNotEmpty;
      });
      await assertSameSession('browser to main panel');
      evidence['selected'] = await snapshot();

      // The native play control must also handle an initially muted autoplay.
      if (session.media.muted || !session.media.playing) {
        await tap('visualPlayerPlay');
      }
      await refreshUntil(
        'audible main-panel playback',
        (media) => media.playing && !media.muted,
      );
      await refreshUntil(
        'content ready after advertisements',
        (media) => !media.isAd,
        seconds: 45,
      );
      final double initialPitch = session.media.pitch;
      await tap('visualPlayerPitchUp');
      await refreshUntil(
        'processed pitch acknowledged',
        (media) =>
            media.pitchStatus == 'active' || media.pitchStatus == 'unavailable',
        seconds: 25,
      );
      expect(
        session.media.pitchStatus,
        'active',
        reason: session.media.pitchMessage,
      );
      expect(session.media.pitch, initialPitch + 1);
      await tap('visualPlayerSpeed075');
      await refreshUntil(
        'speed acknowledged',
        (media) => (media.speed - .75).abs() < .01,
      );
      evidence['processing'] = await snapshot();

      // Pause to make seek/marker assertions deterministic, using only the real
      // transport controls. The graph and applied processing must stay intact.
      await tap('visualPlayerPlay');
      await refreshUntil('paused for markers', (media) => !media.playing);
      final double positionBeforeSeek = session.media.position;
      await tap('visualPlayerForward10');
      await refreshUntil(
        'forward seek acknowledged',
        (media) => (media.position - (positionBeforeSeek + 10)).abs() < 1,
      );
      final double markerA = session.media.position;
      await tap('visualPlayerMarkA');
      await refreshUntil(
        'marker A acknowledged',
        (media) => media.loopA != null && (media.loopA! - markerA).abs() < 1,
      );
      await tap('visualPlayerForward10');
      await refreshUntil(
        'seek to marker B',
        (media) => (media.position - markerA - 10).abs() < 1,
      );
      await tap('visualPlayerMarkB');
      await refreshUntil(
        'marker B acknowledged',
        (media) =>
            media.loopB != null &&
            media.loopB! > media.loopA! &&
            media.loopEnabled,
      );
      await tap('visualPlayerLoopToggle');
      await refreshUntil('loop disabled', (media) => !media.loopEnabled);
      await tap('visualPlayerLoopToggle');
      await refreshUntil('loop enabled', (media) => media.loopEnabled);
      evidence['loop'] = await snapshot();

      await tap('visualPlayerFullscreen');
      await waitFor('fullscreen visible', () async {
        return find
            .byKey(const Key('visualFullscreenSurface'))
            .evaluate()
            .isNotEmpty;
      });
      await assertSameSession('main panel to fullscreen');
      expect(session.media.pitch, initialPitch + 1);
      expect(session.media.speed, closeTo(.75, .01));
      expect(session.media.loopEnabled, isTrue);
      evidence['fullscreen'] = await snapshot();

      await tap('visualFullscreenLock');
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('visualFullscreenPlay')))
            .onPressed,
        isNull,
      );
      await tester.longPress(find.byKey(const Key('visualFullscreenLock')));
      await tester.pump();
      await tap('visualFullscreenBack');
      await assertSameSession('fullscreen to main panel');
      expect(session.media.pitch, initialPitch + 1);
      expect(session.media.speed, closeTo(.75, .01));
      expect(session.media.loopEnabled, isTrue);

      await tap('visualPlayerPlay');
      await refreshUntil('resumed in main panel', (media) => media.playing);
      await tap('visualPlayerPlay');
      await refreshUntil('final pause', (media) => !media.playing);
      evidence['final'] = await snapshot();
      evidence['ownership'] = <String, dynamic>{
        'factories': factoryCalls,
        'starts': session.starts,
        'searches': session.searches,
        'reloads': session.reloads,
        'webViewBuilds': session.views,
        'documentPreserved': true,
        'mediaElementPreserved': true,
      };
      expect(tester.takeException(), isNull);
      evidence['passed'] = true;
    } on Object catch (error) {
      evidence['failedStage'] = stage;
      evidence['failure'] = error.toString();
      if (!evidence.containsKey('failureSnapshot')) {
        try {
          evidence['failureSnapshot'] = await mediaDiagnostic();
        } on Object catch (snapshotError) {
          evidence['failureSnapshot'] = snapshotError.toString();
        }
        debugPrint(
          'TRANSPO_MAIN_YOUTUBE_FAILURE_MEDIA ${jsonEncode(evidence['failureSnapshot'])}',
        );
      }
      rethrow;
    } finally {
      evidence['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      evidence['commands'] = List<Map<String, dynamic>>.of(session.commands);
      binding.reportData = evidence;
      debugPrint('TRANSPO_MAIN_YOUTUBE_EVIDENCE ${jsonEncode(evidence)}');
      try {
        await session.command('pause');
      } on Object {
        // Best effort cleanup if a network/platform failure destroyed the page.
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      binding.testTextInput.unregister();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class _TrackedYouTubeSession extends WebViewYouTubeSession {
  int starts = 0;
  int searches = 0;
  int reloads = 0;
  int views = 0;
  final List<Map<String, dynamic>> commands = <Map<String, dynamic>>[];

  @override
  Future<void> command(String action, [num? value]) {
    final Map<String, dynamic> command = <String, dynamic>{
      'index': commands.length,
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'value': value,
      'before': <String, dynamic>{
        'playing': media.playing,
        'muted': media.muted,
        'pitch': media.pitch,
        'pitchStatus': media.pitchStatus,
        'position': media.position,
      },
    };
    commands.add(command);
    debugPrint('TRANSPO_COMMAND ${jsonEncode(command)}');
    return super.command(action, value);
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
