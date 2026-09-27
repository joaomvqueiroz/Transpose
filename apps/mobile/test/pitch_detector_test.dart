import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/pitch_detector.dart';

List<double> tone(double hz, {double harmonic = 0, double amplitude = .5}) =>
    List.generate(4096, (i) {
      final phase = 2 * math.pi * hz * i / 16000;
      return amplitude * (math.sin(phase) + harmonic * math.sin(2 * phase));
    });

void main() {
  test('detects guitar strings over the intended range', () {
    for (final (hz, midi) in [
      (82.406889, 40),
      (110.0, 45),
      (146.832384, 50),
      (195.997718, 55),
      (246.941651, 59),
      (329.627557, 64),
    ]) {
      final reading = detectInstrumentPitch(tone(hz));
      expect(reading, isNotNull, reason: '$hz Hz');
      expect(reading!.midiNote, midi);
      expect(reading.cents.abs(), lessThan(3));
    }
  });

  test('harmonics do not turn a plucked string into the next octave', () {
    final reading = detectInstrumentPitch(tone(110, harmonic: .7));
    expect(reading?.midiNote, 45);
  });

  test('silence and very quiet input do not show a false note', () {
    expect(detectInstrumentPitch(List.filled(4096, 0)), isNull);
    expect(detectInstrumentPitch(tone(440, amplitude: .001)), isNull);
  });
}
