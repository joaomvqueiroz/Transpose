import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'detects a musical key from a local synthetic chord progression',
    (tester) async {
      final session = WebViewYouTubeSession();
      await tester.pumpWidget(
        MaterialApp(home: YouTubeBrowserScreen(session: session)),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (session.controller.platform is AndroidWebViewController) {
        await (session.controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      await session.controller.loadHtmlString(
        '<!doctype html><html><body></body></html>',
        baseUrl: 'https://m.youtube.com/watch?v=transpono-key-probe',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await session.controller.runJavaScript('''
      window.TransponoMedia?.dispose(); delete window.TransponoMedia;
      (() => {
        const rate = 22050, seconds = 18, length = rate * seconds;
        const wav = new ArrayBuffer(44 + length * 2);
        const view = new DataView(wav);
        const ascii = (offset, value) => {
          for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
        };
        ascii(0, 'RIFF'); view.setUint32(4, 36 + length * 2, true);
        ascii(8, 'WAVE'); ascii(12, 'fmt ');
        view.setUint32(16, 16, true); view.setUint16(20, 1, true);
        view.setUint16(22, 1, true); view.setUint32(24, rate, true);
        view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true);
        view.setUint16(34, 16, true); ascii(36, 'data');
        view.setUint32(40, length * 2, true);
        const chords = [[261.63, 329.63, 392], [349.23, 440, 523.25],
          [392, 493.88, 587.33]];
        for (let i = 0; i < length; i++) {
          const within = i % (rate * 6);
          const envelope = Math.min(1, within / 700, (rate * 6 - within - 1) / 700);
          const frequencies = chords[Math.floor(i / (rate * 6))];
          const signal = frequencies.reduce((sum, hz) =>
            sum + Math.sin(2 * Math.PI * hz * i / rate), 0) * 0.11 * envelope;
          view.setInt16(44 + i * 2, Math.round(signal * 32767), true);
        }
        const video = document.createElement('video');
        video.playsInline = true;
        document.body.appendChild(video);
        video.src = URL.createObjectURL(new Blob([wav], {type: 'audio/wav'}));
        window.__keyProbe = {ready: false};
        video.addEventListener('loadedmetadata', () => {
          video.play().then(() => window.__keyProbe.ready = true)
            .catch(error => window.__keyProbe.error = error.message);
        }, {once: true});
      })();
    ''');
      for (final asset in <String>[
        'transpono_key_detector.js',
        'transpono_media.js',
      ]) {
        await session.controller.runJavaScript(
          await rootBundle.loadString('assets/web/$asset'),
        );
      }

      Map<String, dynamic> snapshot = <String, dynamic>{};
      final deadline = DateTime.now().add(const Duration(seconds: 27));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        dynamic value = await session.controller.runJavaScriptReturningResult(
          'JSON.stringify(window.TransponoMedia?.snapshot() || {})',
        );
        for (int i = 0; value is String && i < 2; i++) {
          value = jsonDecode(value);
        }
        if (value is Map<String, dynamic>) snapshot = value;
        if (snapshot['keyStatus'] == 'ready') break;
      }
      debugPrint('TRANSPO_KEY ${jsonEncode(snapshot)}');
      expect(snapshot['keyStatus'], 'ready');
      expect(snapshot['keyRoot'], 0);
      expect(snapshot['keyMode'], 'major');
      await session.controller.runJavaScript('''
      window.TransponoMedia?.dispose();
      document.querySelector('video')?.pause();
    ''');
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
