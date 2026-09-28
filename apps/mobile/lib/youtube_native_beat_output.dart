import 'band_audio.dart';
import 'native_beat_audio_arbiter.dart';
import 'youtube_beat_scheduler.dart';

/// QA-only bridge. The owner must call [stop] on pause/seek/dispose and must
/// pass the same arbiter instance used by any BandSession on this device.
class YouTubeNativeBeatOutput implements YouTubeBeatOutput {
  YouTubeNativeBeatOutput({
    required this.audio,
    required this.nowUs,
    required this.arbiter,
  });

  final FractionalBeatAudio audio;
  final int Function() nowUs;
  final NativeBeatAudioArbiter arbiter;
  final Object _owner = Object();
  bool _owned = false;
  bool _prepared = false;

  @override
  Future<void> schedule(YouTubeBeatSchedule plan) async {
    if (plan.validUntilUs <= plan.nextBeatUs + 25000 ||
        plan.validUntilUs <= nowUs()) {
      throw ArgumentError('Beat does not fit its native lease.');
    }
    if (!_owned) {
      if (!arbiter.tryAcquire(_owner)) {
        throw StateError('Native metronome output is in use.');
      }
      _owned = true;
    }
    try {
      if (!_prepared) {
        await audio.prepare(nowUs);
        _prepared = true;
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
    // A failed native stop cannot grant ownership to another session.
    await audio.stop();
    _prepared = false;
    _owned = false;
    arbiter.release(_owner);
  }
}
