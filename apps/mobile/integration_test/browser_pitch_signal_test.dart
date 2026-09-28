import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:transpose_mobile/youtube_browser.dart';

import 'fixtures/audio_probe_source.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('browser WASM shifts frequency independently of speed', (
    tester,
  ) async {
    final WebViewYouTubeSession session = WebViewYouTubeSession();
    // Initialize through the public browser to retain real controller settings.
    await tester.pumpWidget(
      MaterialApp(home: YouTubeBrowserScreen(session: session)),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (session.controller.platform is AndroidWebViewController) {
      await (session.controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    // Reproduce YouTube's no-blob module restriction using our own test document.
    await session.controller.loadHtmlString(
      '''<!doctype html><html><head>
      <meta http-equiv="Content-Security-Policy" content="script-src 'self' 'unsafe-inline' 'unsafe-eval'">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      </head><body></body></html>''',
      baseUrl: 'https://m.youtube.com/watch?v=transpono-probe',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    // Reload the document's bridge after enabling diagnostics (test-only).
    await session.controller.runJavaScript(
      'window.TransponoMedia?.dispose(); delete window.TransponoMedia;',
    );
    await session.controller.runJavaScript(audioProbeSource);
    for (final String asset in <String>[
      'SignalsmithStretch.js',
      'transpono_stretch.js',
      'transpono_key_detector.js',
      'transpono_media.js',
    ]) {
      await session.controller.runJavaScript(
        await rootBundle.loadString('assets/web/$asset'),
      );
    }
    final List<dynamic> cases = <dynamic>[];
    for (final (int pitch, double speed) in <(int, double)>[
      (12, 1),
      (-5, 0.75),
      (3, 1.25),
    ]) {
      await session.controller.runJavaScript('''
        window.__probeResult = null;
        window.TransponoAudioProbe.runCase({pitch:$pitch,speed:$speed})
          .then(value => window.__probeResult=value)
          .catch(error => window.__probeResult={error:error.message});
      ''');
      dynamic result;
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
      while (result == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        dynamic value = await session.controller.runJavaScriptReturningResult(
          'JSON.stringify(window.__probeResult)',
        );
        for (int i = 0; value is String && i < 2; i++) {
          value = jsonDecode(value);
        }
        result = value;
      }
      debugPrint('TRANSPO_PITCH_SIGNAL ${jsonEncode(result)}');
      cases.add(result);
      expect(result, isNotNull);
      expect(result['error'], isNull);
      expect(result['passed'], isTrue);
    }
    await session.controller.runJavaScript('''
      window.__transitionResult = null;
      window.TransponoAudioProbe.runPitchTransitionCase()
        .then(value => window.__transitionResult=value)
        .catch(error => window.__transitionResult={error:error.message});
    ''');
    dynamic transition;
    final DateTime transitionDeadline = DateTime.now().add(
      const Duration(seconds: 20),
    );
    while (transition == null && DateTime.now().isBefore(transitionDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      dynamic value = await session.controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__transitionResult)',
      );
      for (int i = 0; value is String && i < 2; i++) {
        value = jsonDecode(value);
      }
      transition = value;
    }
    debugPrint('TRANSPO_PITCH_TRANSITION ${jsonEncode(transition)}');
    expect(transition, isNotNull);
    expect(transition['error'], isNull);
    expect(transition['passed'], isTrue);
    await session.controller.runJavaScript('''
      window.__effectsResult = null;
      (async () => {
        for (const [action, value] of [
          ['gain', 3], ['chorus', .2], ['feedback', .25],
          ['delay', .15], ['reverb', .2],
        ]) await window.TransponoMedia.command({action, value});
        await new Promise(resolve => setTimeout(resolve, 150));
        return window.TransponoMedia.snapshot().probe.effects;
      })().then(value => window.__effectsResult=value)
        .catch(error => window.__effectsResult={error:error.message});
    ''');
    dynamic effects;
    final DateTime effectsDeadline = DateTime.now().add(
      const Duration(seconds: 15),
    );
    while (effects == null && DateTime.now().isBefore(effectsDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      dynamic value = await session.controller.runJavaScriptReturningResult(
        'JSON.stringify(window.__effectsResult)',
      );
      for (int i = 0; value is String && i < 2; i++) {
        value = jsonDecode(value);
      }
      effects = value;
    }
    debugPrint('TRANSPO_EFFECTS ${jsonEncode(effects)}');
    expect(effects, isNotNull);
    expect(effects['error'], isNull);
    expect(effects['gain'], greaterThan(1));
    expect(effects['chorus'], greaterThan(0));
    expect(effects['feedback'], greaterThan(0));
    expect(effects['delay'], greaterThan(0));
    expect(effects['reverb'], greaterThan(0));
    binding.reportData = <String, dynamic>{
      'cases': cases,
      'transition': transition,
      'effects': effects,
    };
    await session.controller.runJavaScript(
      'window.TransponoAudioProbe.cleanup()',
    );
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
