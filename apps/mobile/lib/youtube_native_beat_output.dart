import 'band_audio.dart';
import 'youtube_beat_scheduler.dart';

/// A synchronous lease shared with any future BandSession integration. An
/// implementation must refuse acquisition while the band owns the channel.
abstract class YouTubeBeatAudioArbiter {
  bool tryAcquire();
  void release();
}

/// QA-only bridge. The owner must call [stop] on pause/seek/dispose and must
/// not construct this alongside a BandSession without a shared arbiter.
class YouTubeNativeBeatOutput implements YouTubeBeatOutput {
  YouTubeNativeBeatOutput({
    required this.audio,
    required this.nowUs,
    required this.arbiter,
    required this.bandSessionActive,
  });

  final FractionalBeatAudio audio;
  final int Function() nowUs;
  final YouTubeBeatAudioArbiter arbiter;
  final bool Function() bandSessionActive;
  bool _owned = false;
  bool _prepared = false;

  @override
  Future<void> schedule(YouTubeBeatSchedule plan) async {
    if (bandSessionActive()) {
      // Never send stop to an output potentially owned by BandSession.
      throw StateError('BandSession owns the native metronome.');
    }
    if (plan.validUntilUs <= plan.nextBeatUs + 25000 ||
        plan.validUntilUs <= nowUs()) {
      throw ArgumentError('Beat does not fit its native lease.');
    }
    if (!_owned) {
      if (!arbiter.tryAcquire()) {
        throw StateError('Native metronome output is in use.');
      }
      _owned = true;
    }
    try {
      if (!_prepared) {
        await audio.prepare(nowUs);
        _prepared = true;
      }
      if (bandSessionActive()) {
        throw StateError('BandSession became active during preparation.');
      }
      await audio.scheduleFractional(
        revision: plan.revision,
        startUs: plan.gridStartUs,
        bpm: plan.bpm,
        beats: plan.beatsPerBar,
        validUntilUs: plan.validUntilUs,
        correctionUs: 0,
      );
    } on Object {
      await stop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_owned) return;
    try {
      await audio.stop();
    } finally {
      _prepared = false;
      _owned = false;
      arbiter.release();
    }
  }
}
