import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/band_audio.dart';
import 'package:transpose_mobile/band_session.dart';
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

  testWidgets('band and QA output hand off one native channel', (tester) async {
    final support = await getApplicationSupportDirectory();
    if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
      throw StateError('Refusing arbiter probe outside isolated QA package');
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Beat ownership QA'))),
    );

    final arbiter = NativeBeatAudioArbiter.instance;
    final bandAudio = NativeBandAudio();
    final band = BandSession(audio: bandAudio, arbiter: arbiter);
    final youtubeAudio = NativeBandAudio();
    final clock = Stopwatch()..start();
    int nowUs() => clock.elapsedMicroseconds;
    final youtube = YouTubeNativeBeatOutput(
      audio: youtubeAudio,
      nowUs: nowUs,
      arbiter: arbiter,
    );
    final evidence = <String, Object?>{'passed': false};
    try {
      await band.host(address: InternetAddress.loopbackIPv4);
      expect(band.connected, isTrue);
      band.setTransport(bpm: 120, beats: 4, playing: true);
      final wait = Stopwatch()..start();
      while ((band.audioStatus['clicks'] as num? ?? 0) < 2 &&
          wait.elapsed < const Duration(seconds: 9)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      final firstClicks = (band.audioStatus['clicks'] as num? ?? 0).toInt();
      expect(firstClicks, greaterThanOrEqualTo(2));
      expect(band.audioStatus['error'], isNull);

      final blockedAt = nowUs();
      await expectLater(
        youtube.schedule(
          YouTubeBeatSchedule(
            revision: 1,
            epoch: 1,
            sectionIndex: 0,
            gridStartUs: blockedAt + 500000,
            nextBeatUs: blockedAt + 500000,
            nextBeatIndex: 0,
            bpm: 120,
            beatsPerBar: 4,
            validUntilUs: blockedAt + 1250000,
          ),
        ),
        throwsStateError,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
      final bandAfterBlock = (band.audioStatus['clicks'] as num? ?? 0).toInt();
      expect(bandAfterBlock, greaterThan(firstClicks));
      await band.leave();
      final stoppedBand = await bandAudio.status();
      expect(stoppedBand['leaseActive'], isFalse);

      final takeoverAt = nowUs();
      await youtube.schedule(
        YouTubeBeatSchedule(
          revision: 2,
          epoch: 1,
          sectionIndex: 0,
          gridStartUs: takeoverAt + 600000,
          nextBeatUs: takeoverAt + 600000,
          nextBeatIndex: 0,
          bpm: 120,
          beatsPerBar: 4,
          validUntilUs: takeoverAt + 1550000,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await tester.pump();
      final qaActive = await youtubeAudio.status();
      expect(qaActive['error'], isNull);
      expect(qaActive['clicks'], greaterThanOrEqualTo(1));
      expect(qaActive['maxGridErrorUs'], lessThan(32));
      await youtube.stop();
      final qaStopped = await youtubeAudio.status();
      expect(qaStopped['leaseActive'], isFalse);
      evidence.addAll({
        'passed': true,
        'bandClicksBeforeBlock': firstClicks,
        'bandClicksAfterBlock': bandAfterBlock,
        'qaClicksAfterHandoff': qaActive['clicks'],
        'qaMaxGridErrorUs': qaActive['maxGridErrorUs'],
        'scope': 'one Android AudioTrack channel; synthetic clicks only; no acoustic or YouTube measurement',
      });
    } finally {
      await youtube.stop();
      await band.leave();
      band.dispose();
      binding.reportData = evidence;
      debugPrint('TRANSPONO_BEAT_ARBITER ${jsonEncode(evidence)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
