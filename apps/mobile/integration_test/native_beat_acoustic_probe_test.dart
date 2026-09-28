import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transpose_mobile/band_audio.dart';

double _percentile(List<double> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[(math.max(
    0,
    (sorted.length * fraction).ceil() - 1,
  )).clamp(0, sorted.length - 1)];
}

/// QA-only acoustic measurement of generated clicks. PCM remains inside the
/// native capture process; only 10 ms features and summary timings reach Dart.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const microphone = MethodChannel('transpose/qa_phone_rhythm_features');
  const nativeBeat = MethodChannel('transpose/band_audio');

  testWidgets('speaker clicks are compared with microphone onsets', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    if (!support.path.contains('/com.example.transpose_mobile.qa/')) {
      throw StateError('Refusing microphone probe outside isolated QA package');
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Synthetic acoustic QA'))),
    );

    final audio = NativeBandAudio();
    final watch = Stopwatch()..start();
    int nowUs() => watch.elapsedMicroseconds;
    final evidence = <String, Object?>{'captured': false, 'conclusive': false};
    try {
      var bestRttUs = 1 << 62;
      var nativeMinusDartUs = 0;
      for (var i = 0; i < 7; i++) {
        final before = nowUs();
        final native = await nativeBeat.invokeMethod<int>('clock');
        final after = nowUs();
        final rtt = after - before;
        if (native == null || rtt < 0) {
          throw StateError('Native monotonic clock unavailable');
        }
        if (rtt < bestRttUs) {
          bestRttUs = rtt;
          nativeMinusDartUs = native - ((before + after) ~/ 2);
        }
      }
      if (bestRttUs > 100000) {
        throw StateError('Clock calibration is too uncertain');
      }

      await microphone.invokeMethod<void>('start', {'durationMs': 12000});
      await audio.prepare(nowUs);
      final gridStartUs = nowUs() + 1000000;
      Map<String, dynamic> audioStatus = {};
      for (var i = 0; i < 42; i++) {
        await audio.schedule(
          revision: 1,
          startUs: gridStartUs,
          bpm: 120,
          beats: 4,
          validUntilUs: nowUs() + 1250000,
          correctionUs: 0,
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
        audioStatus = await audio.status();
        if (audioStatus['error'] != null) {
          throw StateError('Native AudioTrack: ${audioStatus['error']}');
        }
      }
      await audio.stop();
      await microphone.invokeMethod<void>('finish');
      Map<String, dynamic> capture = {};
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (DateTime.now().isBefore(deadline)) {
        capture = Map<String, dynamic>.from(
          await microphone.invokeMapMethod<String, dynamic>('status') ?? {},
        );
        if (capture['busy'] == false) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(capture['phase'], 'done');
      expect(capture['busy'], isFalse);
      evidence.addAll({
        'captured': true,
        'quality': capture['quality'],
        'peakRms': capture['peakRms'],
        'meanRms': capture['meanRms'],
        'ambientRms': capture['ambientRms'],
        'source': capture['source'],
        'routeType': capture['routeType'],
        'aecEnabled': capture['aecEnabled'],
        'agcEnabled': capture['agcEnabled'],
        'noiseSuppressorEnabled': capture['noiseSuppressorEnabled'],
        'nativeClicks': audioStatus['clicks'],
      });
      final total = (capture['featureCount'] as num?)?.toInt();
      final originUs = (capture['captureOriginMonotonicUs'] as num?)?.toInt();
      if (total == null || total < 800 || total > 1200 || originUs == null) {
        evidence['reason'] =
            'No stable microphone timestamp or insufficient features';
        return;
      }

      final onsetsUs = <int>[];
      final features = <({int atUs, double novelty})>[];
      for (var offset = 0; offset < total; offset += 500) {
        final page = await microphone.invokeMapMethod<String, dynamic>(
          'readFeatures',
          {'offset': offset, 'limit': 500},
        );
        if (page?['offset'] != offset || page?['total'] != total) {
          throw StateError('Incomplete QA feature page');
        }
        for (final row in page!['features'] as List) {
          if (row is Map &&
              row['monotonicUs'] is num &&
              row['novelty'] is num) {
            final atUs = (row['monotonicUs'] as num).toInt();
            features.add((
              atUs: atUs,
              novelty: (row['novelty'] as num).toDouble(),
            ));
            if (row['onset'] == true) onsetsUs.add(atUs);
          }
        }
      }

      ({int atUs, double novelty})? strongest(int beginUs, int endUs) {
        ({int atUs, double novelty})? peak;
        for (final feature in features) {
          if (feature.atUs < beginUs || feature.atUs >= endUs) continue;
          if (peak == null || feature.novelty > peak.novelty) peak = feature;
        }
        return peak;
      }

      final nativeGridStartUs = gridStartUs + nativeMinusDartUs;
      final captureEndUs = originUs + total * 10000;
      final deltasMs = <double>[];
      final beatToGapRatios = <double>[];
      var expected = 0;
      for (
        var at = nativeGridStartUs;
        at < captureEndUs - 450000;
        at += 500000
      ) {
        if (at < originUs + 250000) continue;
        expected++;
        // The native onset bit intentionally detects mainly loud accents.
        // Compare each beat's energy rise with an equal-size quiet gap before
        // the next beat, so weaker beats need actual acoustic evidence too.
        final beat = strongest(at - 20000, at + 180000);
        final gap = strongest(at + 230000, at + 430000);
        if (beat == null || gap == null) continue;
        beatToGapRatios.add(beat.novelty / math.max(.001, gap.novelty));
        if (beat.novelty >= math.max(.002, gap.novelty * 2.5)) {
          deltasMs.add((beat.atUs - at) / 1000);
        }
      }
      final medianMs = deltasMs.isEmpty ? null : _percentile(deltasMs, .5);
      final jitterMs = medianMs == null
          ? null
          : _percentile(
              deltasMs.map((delta) => (delta - medianMs).abs()).toList(),
              .95,
            );
      final coverage = expected == 0 ? 0.0 : deltasMs.length / expected;
      final conclusive =
          capture['quality'] == 'availableForReview' &&
          bestRttUs <= 10000 &&
          deltasMs.length >= 8 &&
          coverage >= .7 &&
          jitterMs != null &&
          jitterMs <= 30;
      evidence.addAll({
        'conclusive': conclusive,
        'captureClockSpreadUs': capture['captureClockSpreadUs'],
        'clockRoundTripUs': bestRttUs,
        'expectedClicks': expected,
        'microphoneOnsets': onsetsUs.length,
        'medianBeatToGapRatio': beatToGapRatios.isEmpty
            ? null
            : _percentile(beatToGapRatios, .5),
        'matchedClicks': deltasMs.length,
        'coverage': coverage,
        'medianAcousticOffsetMs': medianMs,
        'p95AcousticJitterMs': jitterMs,
        'scope': 'QA synthetic speaker clicks only; not a YouTube/video synchronization measurement',
      });
    } finally {
      await audio.stop();
      await microphone.invokeMethod<void>('cancel');
      binding.reportData = evidence;
      debugPrint('TRANSPONO_BEAT_ACOUSTIC ${jsonEncode(evidence)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
