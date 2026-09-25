import 'dart:async';

/// Operations supported by a prepared audio pipeline, not merely by a source.
final class AudioProcessingSupport {
  const AudioProcessingSupport({
    required this.pitchShift,
    required this.timeStretch,
  });

  final bool pitchShift;
  final bool timeStretch;
}

/// Last values actually applied by the audio pipeline.
///
/// A command acknowledgement is not an applied value. Until an applied-state
/// update arrives, consumers must continue displaying the previous confirmed
/// values (or an explicit pending indicator).
final class AudioProcessingAppliedState {
  AudioProcessingAppliedState({
    required this.pitchSemitones,
    required this.speedFactor,
    required this.lastPitchAppliedSequence,
    required this.lastSpeedAppliedSequence,
    this.lastPitchApplyLatency,
    this.lastSpeedApplyLatency,
  }) {
    if (!pitchSemitones.isFinite) {
      throw ArgumentError.value(pitchSemitones, 'pitchSemitones');
    }
    if (!speedFactor.isFinite || speedFactor <= 0) {
      throw ArgumentError.value(speedFactor, 'speedFactor');
    }
    if (lastPitchAppliedSequence < 0 || lastSpeedAppliedSequence < 0) {
      throw ArgumentError('Applied sequences must be non-negative.');
    }
    if ((lastPitchApplyLatency?.isNegative ?? false) ||
        (lastSpeedApplyLatency?.isNegative ?? false)) {
      throw ArgumentError('Apply latencies must be non-negative.');
    }
  }

  /// Zero semitones means original pitch.
  final double pitchSemitones;

  /// One means original speed, independently of pitch.
  final double speedFactor;

  /// Zero until the first change to the respective parameter is applied.
  final int lastPitchAppliedSequence;
  final int lastSpeedAppliedSequence;

  /// Command-to-effective-output latency, when measurable by the adapter.
  /// Null means unknown, not zero.
  final Duration? lastPitchApplyLatency;
  final Duration? lastSpeedApplyLatency;

  static final AudioProcessingAppliedState initial =
      AudioProcessingAppliedState(
    pitchSemitones: 0,
    speedFactor: 1,
    lastPitchAppliedSequence: 0,
    lastSpeedAppliedSequence: 0,
  );
}

/// Processing boundary for one already prepared media resource.
///
/// Playback ownership, load/unload, seek, and position remain with the media
/// player. This port does not select a DSP library, decoder, output device, or
/// clock. It must never create a second audio output for the same resource.
abstract interface class AudioProcessingPort {
  AudioProcessingSupport get support;

  /// Latest confirmed values; never optimistic command intent.
  AudioProcessingAppliedState get appliedState;

  /// Emits confirmed changes. Subscribers must first read [appliedState], then
  /// subscribe to this stream, just as they do for the player state.
  Stream<AudioProcessingAppliedState> get appliedStates;

  /// Queues an absolute pitch in semitones without changing speed.
  ///
  /// The returned positive, monotonically increasing sequence acknowledges
  /// command delivery only. It does not mean the new sound is audible. The
  /// implementation later reports that sequence in [appliedStates]. A failed
  /// command must not change [appliedState]. Unsupported operations throw
  /// [UnsupportedError]; non-finite values throw [ArgumentError].
  Future<int> setPitchSemitones(double semitones);

  /// Queues an absolute speed factor without changing pitch.
  ///
  /// The factor must be finite and greater than zero. As with pitch, the
  /// Future acknowledges delivery, not effective output. A platform/DSP
  /// adapter may coalesce superseded pending commands, but must eventually
  /// report the sequence of the effective value.
  Future<int> setSpeedFactor(double factor);
}
