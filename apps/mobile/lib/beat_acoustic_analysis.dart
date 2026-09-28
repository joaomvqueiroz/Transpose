import 'dart:math' as math;

/// Ten-millisecond microphone feature, never raw PCM.
typedef BeatAcousticFeature = ({int atUs, double novelty});

class BeatAcousticResult {
  const BeatAcousticResult({
    required this.expected,
    required this.matched,
    required this.controlMatched,
    required this.medianOffsetMs,
    required this.p95JitterMs,
    required this.medianContrast,
  });

  final int expected, matched, controlMatched;
  final double? medianOffsetMs, p95JitterMs, medianContrast;
  double get coverage => expected == 0 ? 0 : matched / expected;
  double get controlCoverage => expected == 0 ? 0 : controlMatched / expected;

  /// This is evidence of locally generated clicks, not YouTube synchronization.
  bool get conclusive =>
      expected >= 8 &&
      coverage >= .7 &&
      controlCoverage <= .2 &&
      p95JitterMs != null &&
      p95JitterMs! <= 30;
}

/// Compare each beat with a quiet interval and a half-beat-shifted placebo.
/// The placebo guards against treating background rhythm/noise as proof.
BeatAcousticResult analyzeBeatAcoustics({
  required List<BeatAcousticFeature> features,
  required int gridStartUs,
  required int beatIntervalUs,
  required int captureStartUs,
  required int captureEndUs,
}) {
  if (beatIntervalUs < 250000 || beatIntervalUs > 1500000) {
    throw ArgumentError.value(beatIntervalUs, 'beatIntervalUs');
  }
  for (var i = 0; i < features.length; i++) {
    final feature = features[i];
    if (!feature.novelty.isFinite ||
        feature.novelty < 0 ||
        (i > 0 && feature.atUs <= features[i - 1].atUs)) {
      throw const FormatException('Invalid or unordered acoustic features');
    }
  }

  BeatAcousticFeature? strongest(int beginUs, int endUs) {
    BeatAcousticFeature? peak;
    for (final feature in features) {
      if (feature.atUs < beginUs || feature.atUs >= endUs) continue;
      if (peak == null || feature.novelty > peak.novelty) peak = feature;
    }
    return peak;
  }

  final deltas = <double>[];
  final contrasts = <double>[];
  var expected = 0, controlMatched = 0;
  final half = beatIntervalUs ~/ 2;
  for (
    var at = gridStartUs;
    at + beatIntervalUs - 70000 < captureEndUs;
    at += beatIntervalUs
  ) {
    if (at - 20000 < captureStartUs + 200000) continue;
    expected++;
    final beat = strongest(at - 20000, at + 180000);
    final gap = strongest(at + half - 20000, at + half + 180000);
    if (beat == null || gap == null) continue;
    final contrast = beat.novelty / math.max(.001, gap.novelty);
    contrasts.add(contrast);
    if (beat.novelty >= math.max(.002, gap.novelty * 2.5)) {
      deltas.add((beat.atUs - at) / 1000);
    }
    if (gap.novelty >= math.max(.002, beat.novelty * 2.5)) {
      controlMatched++;
    }
  }
  final median = deltas.isEmpty ? null : _percentile(deltas, .5);
  return BeatAcousticResult(
    expected: expected,
    matched: deltas.length,
    controlMatched: controlMatched,
    medianOffsetMs: median,
    p95JitterMs: median == null
        ? null
        : _percentile(
            deltas.map((delta) => (delta - median).abs()).toList(),
            .95,
          ),
    medianContrast: contrasts.isEmpty ? null : _percentile(contrasts, .5),
  );
}

double _percentile(List<double> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length * fraction).ceil().clamp(1, sorted.length) - 1];
}
