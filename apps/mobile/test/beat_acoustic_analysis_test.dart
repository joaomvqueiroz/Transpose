import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/beat_acoustic_analysis.dart';

List<BeatAcousticFeature> features({
  int? beatOffsetUs,
  double pulse = .012,
  double noise = .0002,
}) {
  return [
    for (var at = 0; at < 12000000; at += 10000)
      (
        atUs: at,
        novelty:
            beatOffsetUs != null &&
                at >= 1000000 &&
                (at - 1000000 - beatOffsetUs) % 500000 == 0
            ? pulse
            : noise,
      ),
  ];
}

BeatAcousticResult analyze(List<BeatAcousticFeature> rows) =>
    analyzeBeatAcoustics(
      features: rows,
      gridStartUs: 1000000,
      beatIntervalUs: 500000,
      captureStartUs: 0,
      captureEndUs: 12000000,
    );

void main() {
  test('real synthetic pulses beat the half-beat placebo', () {
    final result = analyze(features(beatOffsetUs: 30000));
    expect(result.expected, greaterThanOrEqualTo(18));
    expect(result.matched, result.expected);
    expect(result.controlMatched, 0);
    expect(result.medianOffsetMs, 30);
    expect(result.conclusive, isTrue);
  });

  test('silence and uniform noise cannot prove acoustic timing', () {
    for (final rows in [features(), features(noise: .004)]) {
      final result = analyze(rows);
      expect(result.matched, 0);
      expect(result.conclusive, isFalse);
    }
  });

  test('half-beat-shifted pulses fail despite a regular rhythm', () {
    final result = analyze(features(beatOffsetUs: 250000));
    expect(result.matched, 0);
    expect(result.controlMatched, greaterThanOrEqualTo(18));
    expect(result.conclusive, isFalse);
  });

  test('unordered or invalid features fail closed', () {
    expect(
      () => analyze([(atUs: 10000, novelty: .1), (atUs: 0, novelty: .1)]),
      throwsFormatException,
    );
    expect(
      () => analyze([(atUs: 0, novelty: double.nan)]),
      throwsFormatException,
    );
  });
}
