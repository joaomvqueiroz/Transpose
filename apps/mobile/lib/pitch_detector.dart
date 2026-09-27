import 'dart:math' as math;

/// A monophonic pitch estimate for a sustained, individually plucked string.
/// It does not infer the musical key of a complete song or polyphonic chord.
class PitchReading {
  const PitchReading({
    required this.frequency,
    required this.midiNote,
    required this.cents,
    required this.confidence,
  });

  final double frequency;
  final int midiNote;
  final double cents;
  final double confidence;

  static const noteNames = [
    'Dó',
    'Dó♯',
    'Ré',
    'Ré♯',
    'Mi',
    'Fá',
    'Fá♯',
    'Sol',
    'Sol♯',
    'Lá',
    'Lá♯',
    'Si',
  ];

  String get noteName => '${noteNames[midiNote % 12]}${midiNote ~/ 12 - 1}';
}

/// YIN-style cumulative mean normalized difference, limited to the guitar
/// range. The RMS gate and confidence gate reject silence and weak estimates.
PitchReading? detectInstrumentPitch(
  List<double> samples, {
  int sampleRate = 16000,
  double minFrequency = 70,
  double maxFrequency = 500,
}) {
  if (sampleRate <= 0 || samples.length < 1024) return null;
  final minLag = (sampleRate / maxFrequency).floor().clamp(
    2,
    samples.length ~/ 4,
  );
  final maxLag = (sampleRate / minFrequency).ceil().clamp(
    minLag + 2,
    samples.length ~/ 3,
  );
  final count = samples.length - maxLag;
  if (count < 256) return null;

  var mean = 0.0;
  for (final sample in samples) {
    mean += sample;
  }
  mean /= samples.length;
  var energy = 0.0;
  for (final sample in samples) {
    final centered = sample - mean;
    energy += centered * centered;
  }
  if (math.sqrt(energy / samples.length) < 0.012) return null;

  final normalized = List<double>.filled(maxLag + 1, 1);
  var running = 0.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    var difference = 0.0;
    for (var i = 0; i < count; i++) {
      final delta = samples[i] - samples[i + lag];
      difference += delta * delta;
    }
    running += difference;
    normalized[lag] = running == 0 ? 1 : difference * lag / running;
  }

  int? bestLag;
  for (var lag = minLag; lag < maxLag; lag++) {
    if (normalized[lag] < 0.16 && normalized[lag] <= normalized[lag + 1]) {
      bestLag = lag;
      break;
    }
  }
  if (bestLag == null || normalized[bestLag] > 0.16) return null;

  final previous = normalized[bestLag - 1];
  final center = normalized[bestLag];
  final next = normalized[bestLag + 1];
  final denominator = previous - 2 * center + next;
  final correction = denominator.abs() < 1e-9
      ? 0.0
      : (0.5 * (previous - next) / denominator).clamp(-0.5, 0.5);
  final frequency = sampleRate / (bestLag + correction);
  if (!frequency.isFinite ||
      frequency < minFrequency ||
      frequency > maxFrequency) {
    return null;
  }
  final exactMidi = 69 + 12 * math.log(frequency / 440) / math.ln2;
  final nearestMidi = exactMidi.round();
  return PitchReading(
    frequency: frequency,
    midiNote: nearestMidi,
    cents: (exactMidi - nearestMidi) * 100,
    confidence: 1 - center,
  );
}
