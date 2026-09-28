import 'dart:math' as math;

/// NTP-style four-timestamp estimate. All values are monotonic microseconds;
/// no wall clock, time zone or phone date participates in the beat grid.
class BandClock {
  final List<({int at, double offset, int rtt})> _samples = [];
  double offsetUs = 0;
  double uncertaintyUs = double.infinity;
  int _inlierCount = 0;
  int? _newestInlierAt;
  int get sampleCount => _samples.length;
  int get inlierCount => _inlierCount;
  int? get lastSampleAt => _newestInlierAt;
  int? get lastAcceptedAt => _samples.isEmpty ? null : _samples.last.at;
  int? get bestRttUs => _samples.isEmpty
      ? null
      : _samples.map((sample) => sample.rtt).reduce(math.min);
  List<int> get recentRttsUs => [for (final sample in _samples) sample.rtt];

  bool add({
    required int sent,
    required int received,
    required int hostReceived,
    required int hostSent,
  }) {
    final rtt = received - sent - (hostSent - hostReceived);
    if (received < sent || hostSent < hostReceived || rtt < 0 || rtt > 250000) {
      return false;
    }
    _samples.removeWhere((s) => received - s.at > 10000000);
    _samples.add((
      at: received,
      offset: ((hostReceived - sent) + (hostSent - received)) / 2,
      rtt: rtt,
    ));
    if (_samples.length > 40) _samples.removeAt(0);
    final best = [..._samples]..sort((a, b) => a.rtt.compareTo(b.rtt));
    // Anchor the estimate on the lowest-RTT samples. A high-latency,
    // asymmetric packet may be accepted for diagnostics but must not make a
    // good clock unhealthy, nor count as a fresh precise measurement.
    final anchors = best.take(math.min(3, best.length)).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    offsetUs = anchors[anchors.length ~/ 2].offset;
    final inliers = _samples
        .where((s) => (s.offset - offsetUs).abs() + s.rtt / 2 <= 20000)
        .toList();
    _inlierCount = inliers.length;
    _newestInlierAt = inliers.isEmpty
        ? null
        : inliers.map((s) => s.at).reduce(math.max);
    uncertaintyUs = inliers.isEmpty
        ? double.infinity
        : inliers.fold<double>(
            0,
            (bound, s) =>
                math.max(bound, (s.offset - offsetUs).abs() + s.rtt / 2),
          );
    return true;
  }

  bool ready(int now) =>
      _inlierCount >= 3 &&
      _newestInlierAt != null &&
      now - _newestInlierAt! < 3000000 &&
      uncertaintyUs <= 20000;
  int localTime(int hostTime) => (hostTime - offsetUs).round();
  void clear() {
    _samples.clear();
    _inlierCount = 0;
    _newestInlierAt = null;
    offsetUs = 0;
    uncertaintyUs = double.infinity;
  }
}

class BandBeatPlan {
  const BandBeatPlan({
    required this.revision,
    required this.bpm,
    required this.beatsPerBar,
    required this.startUs,
    required this.playing,
  });
  final int revision, bpm, beatsPerBar, startUs;
  final bool playing;

  factory BandBeatPlan.fromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    final bpm = json['bpm'];
    final beats = json['beats'];
    final start = json['start'];
    if (revision is! int ||
        revision < 0 ||
        bpm is! int ||
        bpm < 40 ||
        bpm > 240 ||
        beats is! int ||
        beats < 1 ||
        beats > 12 ||
        start is! int ||
        start < 0 ||
        json['playing'] is! bool) {
      throw const FormatException('Invalid beat plan');
    }
    return BandBeatPlan(
      revision: revision,
      bpm: bpm,
      beatsPerBar: beats,
      startUs: start,
      playing: json['playing'] as bool,
    );
  }
  Map<String, Object> toJson() => {
    'revision': revision,
    'bpm': bpm,
    'beats': beatsPerBar,
    'start': startUs,
    'playing': playing,
  };
  int beatTime(int beat) => startUs + (beat * 60000000 / bpm).round();
  int nextBar(int now) {
    final barUs = 60000000 * beatsPerBar / bpm;
    return startUs +
        (math.max(0, ((now - startUs) / barUs).ceil()) * barUs).round();
  }
}
