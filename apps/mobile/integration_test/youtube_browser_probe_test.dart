import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('YouTube search, selection and browser audio on device', (
    tester,
  ) async {
    final WebViewYouTubeSession session = WebViewYouTubeSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: YouTubeBrowserScreen(
          initialQuery: 'Big Buck Bunny Blender',
          session: session,
        ),
      ),
    );

    Future<dynamic> read(String expression) async {
      dynamic value = await session.controller.runJavaScriptReturningResult(
        'JSON.stringify($expression)',
      );
      for (int i = 0; value is String && i < 2; i++) {
        value = jsonDecode(value);
      }
      return value;
    }

    Future<void> waitFor(
      Future<bool> Function() condition, [
      int seconds = 45,
    ]) async {
      final DateTime end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        try {
          if (await condition()) return;
        } on Object {
          /* Page navigating. */
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
      }
      throw StateError(
        'Timed out: ${await read('({url:location.href,text:document.body.innerText.slice(0,1400)})')}',
      );
    }

    // A fresh browser may show Google's consent choice. Reject optional cookies
    // if presented; never sign in or change any existing Google account setting.
    await waitFor(() async {
      final String? url = await session.controller.currentUrl();
      if (url == null) return false;
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
    }, 60);
    final dynamic searchEvidence = await read('''({
      url:location.href,
      thumbnails:document.querySelectorAll('a[href*="/watch?v="] img').length,
      titles:Array.from(document.querySelectorAll('h3')).slice(0,3).map(x=>x.innerText)
    })''');
    debugPrint('TRANSPO_YOUTUBE_SEARCH ${jsonEncode(searchEvidence)}');

    // Select an observed search result, preserving the same embedded browser.
    await session.controller.runJavaScript('''
      (() => {
        const links = Array.from(document.querySelectorAll('a[href*="/watch?v="]'));
        const link = links.find(a => a.href.includes('aqz-KE-bpKQ')) || links[0];
        link.click();
      })();
    ''');
    await waitFor(() async {
      await session.refresh();
      return session.media.hasVideo && session.media.duration > 0;
    });
    // User gesture from the embedded page is required for first playback.
    await session.controller.runJavaScript(
      'document.querySelector("video").play().catch(() => {});',
    );
    await waitFor(
      () async =>
          await read(
            '!!document.querySelector("video") && !document.querySelector("video").paused',
          ) ==
          true,
      20,
    );
    final dynamic capabilities = await read('''({
      url:location.href,srcType:document.querySelector('video').currentSrc.split(':')[0],
      worklet:!!window.AudioWorkletNode,wasm:!!window.WebAssembly,
      bridge:!!window.TransponoMedia,ad:!!document.querySelector('.ad-showing,.ad-interrupting'),
      muted:document.querySelector('video').muted,volume:document.querySelector('video').volume
    })''');
    debugPrint('TRANSPO_YOUTUBE_CAPABILITIES ${jsonEncode(capabilities)}');
    await waitFor(() async {
      await session.refresh();
      return !session.media.isAd;
    }, 60);
    // Programmatic selection may autoplay muted; explicitly enable sound in the
    // test before checking PCM. Production preserves the user's mute preference.
    await session.controller.runJavaScript('''
      window.TransponoMedia?.dispose(); delete window.TransponoMedia;
      window.__transponoAudioProbe = true;
      document.querySelector('video').currentTime = 30;
    ''');
    await session.controller.runJavaScript(
      await rootBundle.loadString('assets/web/transpono_media.js'),
    );
    await session.command('unmute');
    await waitFor(() async {
      await session.refresh();
      return session.media.playing && !session.media.muted;
    }, 10);
    await session.command('pitch', 2);
    await waitFor(() async {
      await session.refresh();
      return session.media.pitchStatus == 'active' ||
          session.media.pitchStatus == 'unavailable';
    }, 25);
    final dynamic audioEvidence = await read(
      'window.TransponoMedia.snapshot()',
    );
    debugPrint('TRANSPO_YOUTUBE_AUDIO ${jsonEncode(audioEvidence)}');
    expect(
      session.media.pitchStatus,
      'active',
      reason: session.media.pitchMessage,
    );
    expect(session.media.pitch, 2);
    await session.command('speed', 0.75);
    await Future<void>.delayed(const Duration(seconds: 1));
    await session.refresh();
    expect(session.media.speed, closeTo(0.75, 0.01));
    await session.command('pause');
    await session.refresh();
    expect(session.media.playing, isFalse);
    binding.reportData = <String, dynamic>{
      'search': searchEvidence,
      'capabilities': capabilities,
      'audio': audioEvidence,
    };
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 5)));
}
