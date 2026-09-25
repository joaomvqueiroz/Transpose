import 'dart:async';

import 'package:audio_engine/audio_engine.dart';
import 'package:test/test.dart';

void main() {
  group('AudioProcessingAppliedState', () {
    test('starts with original pitch and speed without fabricated metrics', () {
      final AudioProcessingAppliedState initial =
          AudioProcessingAppliedState.initial;
      expect(initial.pitchSemitones, 0);
      expect(initial.speedFactor, 1);
      expect(initial.lastPitchAppliedSequence, 0);
      expect(initial.lastSpeedAppliedSequence, 0);
      expect(initial.lastPitchApplyLatency, isNull);
      expect(initial.lastSpeedApplyLatency, isNull);
    });

    test('rejects invalid confirmed values and metrics', () {
      AudioProcessingAppliedState state({
        double pitch = 0,
        double speed = 1,
        int pitchSequence = 0,
        Duration? latency,
      }) =>
          AudioProcessingAppliedState(
            pitchSemitones: pitch,
            speedFactor: speed,
            lastPitchAppliedSequence: pitchSequence,
            lastSpeedAppliedSequence: 0,
            lastPitchApplyLatency: latency,
          );

      expect(() => state(pitch: double.nan), throwsArgumentError);
      expect(() => state(pitch: double.infinity), throwsArgumentError);
      expect(() => state(speed: double.negativeInfinity), throwsArgumentError);
      expect(() => state(speed: 0), throwsArgumentError);
      expect(() => state(speed: -0.5), throwsArgumentError);
      expect(() => state(pitchSequence: -1), throwsArgumentError);
      expect(
        () => state(latency: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
    });
  });

  test('command delivery is distinct from DSP application', () async {
    final _ManualProcessingPort port = _ManualProcessingPort();
    final List<AudioProcessingAppliedState> observed =
        <AudioProcessingAppliedState>[];
    final StreamSubscription<AudioProcessingAppliedState> subscription =
        port.appliedStates.listen(observed.add);

    final int pitchSequence = await port.setPitchSemitones(-2);
    final int speedSequence = await port.setSpeedFactor(0.75);
    expect(pitchSequence, 1);
    expect(speedSequence, 2);
    expect(port.appliedState.pitchSemitones, 0);
    expect(port.appliedState.speedFactor, 1);
    expect(observed, isEmpty);

    port.applyPitch(pitchSequence, -2);
    expect(port.appliedState.pitchSemitones, -2);
    expect(port.appliedState.speedFactor, 1);
    expect(port.appliedState.lastPitchAppliedSequence, pitchSequence);

    port.applySpeed(speedSequence, 0.75);
    expect(port.appliedState.pitchSemitones, -2);
    expect(port.appliedState.speedFactor, 0.75);
    expect(port.appliedState.lastSpeedAppliedSequence, speedSequence);
    expect(observed, hasLength(2));

    await subscription.cancel();
    await port.close();
  });
}

/// A contract consumer, not a production DSP implementation.
final class _ManualProcessingPort implements AudioProcessingPort {
  final StreamController<AudioProcessingAppliedState> _updates =
      StreamController<AudioProcessingAppliedState>.broadcast(sync: true);
  int _nextSequence = 0;
  AudioProcessingAppliedState _state = AudioProcessingAppliedState.initial;

  @override
  AudioProcessingSupport get support =>
      const AudioProcessingSupport(pitchShift: true, timeStretch: true);

  @override
  AudioProcessingAppliedState get appliedState => _state;

  @override
  Stream<AudioProcessingAppliedState> get appliedStates => _updates.stream;

  @override
  Future<int> setPitchSemitones(double semitones) async {
    if (!semitones.isFinite) throw ArgumentError.value(semitones);
    return ++_nextSequence;
  }

  @override
  Future<int> setSpeedFactor(double factor) async {
    if (!factor.isFinite || factor <= 0) throw ArgumentError.value(factor);
    return ++_nextSequence;
  }

  void applyPitch(int sequence, double semitones) {
    _state = AudioProcessingAppliedState(
      pitchSemitones: semitones,
      speedFactor: _state.speedFactor,
      lastPitchAppliedSequence: sequence,
      lastSpeedAppliedSequence: _state.lastSpeedAppliedSequence,
    );
    _updates.add(_state);
  }

  void applySpeed(int sequence, double factor) {
    _state = AudioProcessingAppliedState(
      pitchSemitones: _state.pitchSemitones,
      speedFactor: factor,
      lastPitchAppliedSequence: _state.lastPitchAppliedSequence,
      lastSpeedAppliedSequence: sequence,
    );
    _updates.add(_state);
  }

  Future<void> close() => _updates.close();
}
