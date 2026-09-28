import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/band_audio.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native band clock generates scheduled beats and expires its lease',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Band audio QA'))),
      );
      final audio = NativeBandAudio();
      final clock = Stopwatch()..start();
      int now() => clock.elapsedMicroseconds;
      try {
        await audio.prepare(now);
        final start = now() + 2000000;
        Map<String, dynamic> status = {};
        for (var i = 0; i < 28; i++) {
          await audio.schedule(
            revision: 1,
            startUs: start,
            bpm: 120,
            beats: 4,
            validUntilUs: now() + 1000000,
            correctionUs: 0,
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pump();
          status = await audio.status();
          expect(status['error'], isNull);
        }
        expect(status['locked'], isTrue);
        expect(status['clicks'], greaterThanOrEqualTo(8));
        expect(status['maxGridErrorUs'], lessThan(32));
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        final expired = await audio.status();
        expect(expired['leaseActive'], isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final after = await audio.status();
        expect(after['clicks'], expired['clicks']);
        binding.reportData = {
          'passed': true,
          'active': status,
          'expired': after,
          'scope': 'AudioTrack timestamp/grid only; not an acoustic two-phone measurement',
        };
        debugPrint('TRANSPONO_BAND ${jsonEncode(binding.reportData)}');
      } finally {
        await audio.stop();
      }
    },
  );
}
