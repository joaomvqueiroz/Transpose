import 'dart:async';

import 'package:audio_engine/audio_engine.dart';
import 'package:test/test.dart';

void main() {
  test('pitch stays pending until an applied event and never changes speed',
      () async {
    final _FakePitchPort port = _FakePitchPort();
    final PitchController controller = PitchController(port);

    final int sequence = await controller.setPitchSemitones(-2);
    expect(sequence, 1);
    expect(controller.state.confirmedSemitones, 0);
    expect(controller.state.pendingSemitones, -2);
    expect(controller.state.lastApplyLatency, isNull);
    expect(port.appliedState.speedFactor, 1);

    port.applyPitch(sequence, -2, const Duration(milliseconds: 14));
    expect(controller.state.confirmedSemitones, -2);
    expect(controller.state.pendingSemitones, isNull);
    expect(controller.state.lastApplyLatency, const Duration(milliseconds: 14));
    expect(port.appliedState.speedFactor, 1);

    await controller.dispose();
    await port.close();
  });

  test('rejected command keeps the previous confirmed pitch', () async {
    final _FakePitchPort port = _FakePitchPort();
    final PitchController controller = PitchController(port);
    final int first = await controller.setPitchSemitones(-3);
    port.applyPitch(first, -3, const Duration(milliseconds: 10));

    port.failNext = true;
    await expectLater(
      controller.setPitchSemitones(5),
      throwsA(isA<PitchCommandException>()),
    );
    expect(controller.state.confirmedSemitones, -3);
    expect(controller.state.pendingSemitones, isNull);
    expect(controller.state.errorCode, 'PITCH_COMMAND_FAILED');

    await controller.dispose();
    await port.close();
  });

  test('rapid commands retain the latest pending target', () async {
    final _FakePitchPort port = _FakePitchPort();
    final PitchController controller = PitchController(port);
    final int first = await controller.setPitchSemitones(-1);
    final int second = await controller.setPitchSemitones(2);

    port.applyPitch(first, -1, null);
    expect(controller.state.confirmedSemitones, -1);
    expect(controller.state.pendingSemitones, 2);
    port.applyPitch(second, 2, null);
    expect(controller.state.confirmedSemitones, 2);
    expect(controller.state.pendingSemitones, isNull);

    await controller.dispose();
    await port.close();
  });

  test('reset to original pitch is an explicit applied command', () async {
    final _FakePitchPort port = _FakePitchPort();
    final PitchController controller = PitchController(port);
    final int shifted = await controller.setPitchSemitones(4);
    port.applyPitch(shifted, 4, null);
    final int reset = await controller.setPitchSemitones(0);
    expect(controller.state.confirmedSemitones, 4);
    port.applyPitch(reset, 0, null);
    expect(controller.state.confirmedSemitones, 0);

    await controller.dispose();
    await port.close();
  });

  test('rejects unsupported and out-of-range values before the port', () async {
    final _FakePitchPort port = _FakePitchPort(supportsPitch: false);
    final PitchController controller = PitchController(port);
    await expectLater(
        controller.setPitchSemitones(1), throwsA(isA<UnsupportedError>()));
    await expectLater(controller.setPitchSemitones(13), throwsRangeError);
    await expectLater(
        controller.setPitchSemitones(double.nan), throwsRangeError);
    expect(port.pitchCallCount, 0);
    expect(controller.state.confirmedSemitones, 0);

    await controller.dispose();
    await port.close();
  });

  test('application during command ACK still clears pending state', () async {
    final _FakePitchPort port = _FakePitchPort()..applyBeforeAck = true;
    final PitchController controller = PitchController(port);
    await controller.setPitchSemitones(1);
    expect(controller.state.confirmedSemitones, 1);
    expect(controller.state.pendingSemitones, isNull);

    await controller.dispose();
    await port.close();
  });
}

final class _FakePitchPort implements AudioProcessingPort {
  _FakePitchPort({this.supportsPitch = true});

  final bool supportsPitch;
  final StreamController<AudioProcessingAppliedState> _changes =
      StreamController<AudioProcessingAppliedState>.broadcast(sync: true);
  AudioProcessingAppliedState _applied = AudioProcessingAppliedState.initial;
  int _nextSequence = 0;
  int pitchCallCount = 0;
  bool failNext = false;
  bool applyBeforeAck = false;

  @override
  AudioProcessingSupport get support => AudioProcessingSupport(
        pitchShift: supportsPitch,
        timeStretch: false,
      );

  @override
  AudioProcessingAppliedState get appliedState => _applied;

  @override
  Stream<AudioProcessingAppliedState> get appliedStates => _changes.stream;

  @override
  Future<int> setPitchSemitones(double semitones) async {
    pitchCallCount++;
    if (failNext) {
      failNext = false;
      throw StateError('private adapter detail');
    }
    final int sequence = ++_nextSequence;
    if (applyBeforeAck) applyPitch(sequence, semitones, null);
    return sequence;
  }

  @override
  Future<int> setSpeedFactor(double factor) =>
      throw UnsupportedError('Not needed for pitch tests.');

  void applyPitch(int sequence, double semitones, Duration? latency) {
    _applied = AudioProcessingAppliedState(
      pitchSemitones: semitones,
      speedFactor: _applied.speedFactor,
      lastPitchAppliedSequence: sequence,
      lastSpeedAppliedSequence: _applied.lastSpeedAppliedSequence,
      lastPitchApplyLatency: latency,
    );
    _changes.add(_applied);
  }

  Future<void> close() => _changes.close();
}
