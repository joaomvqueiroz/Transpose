import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/studio_visual_app.dart';
import 'package:transpose_mobile/youtube_browser.dart';

/// Live YouTube transport check against the current integrated player layout.
/// The QA package is mandatory. No account, saved media or preset is touched.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real YouTube transport and confirmed A/B returns', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
      throw StateError('Refusing transport probe outside isolated QA package');
    }
    final session = WebViewYouTubeSession();
    final player = MainPlayerController(youtubeFactory: () => session);
    final evidence = <String, dynamic>{'passed': false};
    String stage = 'mount';

    Future<void> until(
      String label,
      Future<bool> Function() condition, {
      int seconds = 25,
    }) async {
      stage = label;
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        try {
          if (await condition()) return;
        } on Object {
          // A YouTube document navigation can replace the JS execution context.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('Timed out at $label');
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

    Future<void> refresh() async {
      await session.refresh();
      await tester.pump();
    }

    try {
      await tester.pumpWidget(
        StudioVisualApp(playerController: player, openSearchWhenEmpty: true),
      );
      await until('browser ready', () async => player.youtube == session);
      await session.search('Big Buck Bunny Blender');
      await until('visible video results', () async {
        await session.controller.runJavaScript(r'''
          (() => {
            const reject = Array.from(document.querySelectorAll('button'))
              .find(b => /^(Reject all|Rejeitar tudo|Rejeitar todos)$/i.test(b.innerText.trim()));
            if (reject) reject.click();
          })();
        ''');
        return await read(
              r'''document.querySelectorAll('a[href*="/watch?v="] img').length > 0''',
            ) ==
            true;
      }, seconds: 45);
      await session.controller.runJavaScript('''
        (() => {
          const links = Array.from(document.querySelectorAll('a[href*="/watch?v="]'));
          const link = links.find(a => a.href.includes('aqz-KE-bpKQ')) || links[0];
          if (!link) throw new Error('No rendered video result');
          link.click();
        })();
      ''');
      await until('integrated video selected', () async {
        await refresh();
        return player.loaded &&
            session.media.duration > 25 &&
            find
                .byKey(const Key('visualMainMediaViewport'))
                .evaluate()
                .isNotEmpty;
      }, seconds: 45);
      await until('content ready', () async {
        await refresh();
        return !session.media.isAd && session.media.playbackReady;
      }, seconds: 45);
      evidence['videoSelected'] = true;
      evidence['sourceIdPresent'] = session.media.videoId.isNotEmpty;

      if (!player.playing || player.muted) await player.playPause();
      await until('unmuted play', () async {
        await refresh();
        return player.playing && !player.muted && !session.media.isAd;
      });
      final firstPosition = player.position;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await refresh();
      final advanceMs = (player.position - firstPosition).inMilliseconds;
      expect(advanceMs, greaterThanOrEqualTo(300));
      evidence['playAdvancedMs'] = advanceMs;

      await player.pause();
      await until('paused', () async {
        await refresh();
        return !player.playing;
      });
      await player.seek(const Duration(seconds: 20));
      await until('seek A', () async {
        await refresh();
        return (player.position.inMilliseconds - 20000).abs() < 200;
      });
      await player.markA();
      await player.seek(const Duration(seconds: 22));
      await until('seek B', () async {
        await refresh();
        return (player.position.inMilliseconds - 22000).abs() < 200;
      });
      await player.markB();
      await player.seek(const Duration(seconds: 20));
      await until('confirmed loop available', () async {
        await refresh();
        return player.loopEnabled && player.loopObservation != null;
      });
      final initialCount = player.loopObservation!.count;
      await player.playPause();
      await until('first complete return', () async {
        await refresh();
        return player.loopObservation != null &&
            player.loopObservation!.count >= initialCount + 1;
      }, seconds: 18);
      await player.pause();
      final pausedCount = player.loopObservation!.count;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await refresh();
      expect(player.loopObservation!.count, pausedCount);
      expect(player.playing, isFalse);
      evidence['confirmedReturn'] = true;
      evidence['pauseHeldCount'] = true;

      final previousEpoch = player.loopObservation!.epoch;
      await player.seek(const Duration(seconds: 21));
      await until('manual seek invalidated cycle', () async {
        await refresh();
        return player.loopObservation != null &&
            player.loopObservation!.epoch > previousEpoch;
      });
      final partialCount = player.loopObservation!.count;
      await player.playPause();
      await until('partial pass returned', () async {
        await refresh();
        return player.position.inMilliseconds < 20500 && player.playing;
      }, seconds: 12);
      await player.pause();
      expect(player.loopObservation!.count, partialCount);
      evidence['partialSeekExcluded'] = true;
      evidence['passed'] = true;
    } on Object catch (error) {
      evidence['stage'] = stage;
      evidence['error'] = error.toString().replaceAll(
        RegExp(r'https?://\S+'),
        '[url]',
      );
      rethrow;
    } finally {
      binding.reportData = evidence;
      debugPrint('TRANSPONO_YOUTUBE_TRANSPORT ${jsonEncode(evidence)}');
      await player.pause();
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
