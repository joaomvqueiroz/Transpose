import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/band_audio.dart';
import 'package:transpose_mobile/native_beat_audio_arbiter.dart';
import 'package:transpose_mobile/rhythm_map.dart';
import 'package:transpose_mobile/youtube_beat_scheduler.dart';
import 'package:transpose_mobile/youtube_browser.dart';
import 'package:transpose_mobile/youtube_native_beat_output.dart';

/// Synthetic, reviewed map → YouTube timeline scheduler → Android AudioTrack.
/// Does not open YouTube, capture sound, or test acoustic synchronization.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA map schedules native clicks and pause stops them', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
      throw StateError('Refusing beat probe outside isolated QA package');
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Beat scheduler QA'))),
    );

    final clock = Stopwatch()..start();
    int nowUs() => clock.elapsedMicroseconds;
    const videoId = 'qaRhythm001';
    const map = RhythmMap(8, [
      RhythmSection(
        start: 0,
        end: 8,
        firstBeat: .5,
        bpm: 120,
        beatsPerBar: 4,
        confidence: .9,
      ),
    ]);
    final audio = NativeBandAudio();
    final arbiter = NativeBeatAudioArbiter.instance;
    final output = YouTubeNativeBeatOutput(
      audio: audio,
      nowUs: nowUs,
      arbiter: arbiter,
    );
    final scheduler = YouTubeBeatScheduler(
      map: map,
      videoId: videoId,
      output: output,
      nowUs: nowUs,
    );
    const playing = YouTubeMediaState(
      videoId: videoId,
      hasVideo: true,
      playing: true,
      playbackReady: true,
      duration: 8,
    );
    var revision = 0;
    YouTubeTimelineSample sample() {
      final at = nowUs();
      return YouTubeTimelineSample(
        videoId: videoId,
        revision: ++revision,
        epoch: 1,
        positionMs: at / 1000,
        speed: 1,
        browserTimeMs: at / 1000,
        hostMidpointUs: at,
        uncertaintyMs: 1,
      );
    }

    final evidence = <String, Object?>{'passed': false};
    try {
      await scheduler.update(sample: sample(), media: playing);
      for (var i = 0; i < 18; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await tester.pump();
        await scheduler.update(sample: sample(), media: playing);
      }
      final active = await audio.status();
      expect(active['error'], isNull);
      expect(active['clicks'], greaterThanOrEqualTo(4));
      expect(active['maxGridErrorUs'], lessThan(32));

      await scheduler.update(
        sample: sample(),
        media: const YouTubeMediaState(
          videoId: videoId,
          hasVideo: true,
          playing: false,
          playbackReady: true,
          duration: 8,
        ),
      );
      final paused = await audio.status();
      expect(paused['leaseActive'], isFalse);
      evidence.addAll({
        'passed': true,
        'clicks': active['clicks'],
        'maxGridErrorUs': active['maxGridErrorUs'],
        'scope': 'synthetic map and timeline; no YouTube content or acoustic measurement',
      });
    } finally {
      await scheduler.close();
      await output.stop();
      binding.reportData = evidence;
      debugPrint('TRANSPONO_BEAT_NATIVE ${jsonEncode(evidence)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
