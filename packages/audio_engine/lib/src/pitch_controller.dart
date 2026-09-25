import 'dart:async';

import 'audio_processing_port.dart';

/// UI-facing pitch state. Only [confirmedSemitones] describes effective audio.
final class PitchControlState {
  const PitchControlState({
    required this.confirmedSemitones,
    required this.pendingSemitones,
    required this.lastApplyLatency,
    required this.errorCode,
  });

  final double confirmedSemitones;
  final double? pendingSemitones;
  final Duration? lastApplyLatency;
  final String? errorCode;
}

/// Coordinates pitch intent and confirmed output without owning playback/DSP.
///
/// This class is application-side only. It never touches PCM, disk or network,
/// and does not infer acoustic latency from a command acknowledgement.
final class PitchController {
  PitchController(AudioProcessingPort port)
      : _port = port,
        _state = PitchControlState(
          confirmedSemitones: port.appliedState.pitchSemitones,
          pendingSemitones: null,
          lastApplyLatency: port.appliedState.lastPitchApplyLatency,
          errorCode: null,
        ),
        _lastAppliedSequence = port.appliedState.lastPitchAppliedSequence {
    _subscription = port.appliedStates.listen(_onApplied);
  }

  static const double minimumSemitones = -12;
  static const double maximumSemitones = 12;

  final AudioProcessingPort _port;
  final StreamController<PitchControlState> _changes =
      StreamController<PitchControlState>.broadcast(sync: true);
  late final StreamSubscription<AudioProcessingAppliedState> _subscription;
  PitchControlState _state;
  int _lastAppliedSequence;
  int _requestSerial = 0;
  int? _pendingSequence;
  bool _disposed = false;

  PitchControlState get state => _state;
  Stream<PitchControlState> get states => _changes.stream;

  /// Returns after queue acceptance, not after audible application.
  ///
  /// A failed request clears its pending value and retains the latest
  /// confirmed one. The adapter must smooth the actual transition; this
  /// controller cannot guarantee click-free output.
  Future<int> setPitchSemitones(double semitones) async {
    if (_disposed) throw StateError('PitchController is disposed.');
    if (!semitones.isFinite ||
        semitones < minimumSemitones ||
        semitones > maximumSemitones) {
      throw RangeError.value(
        semitones,
        'semitones',
        'Must be finite and between -12 and +12',
      );
    }
    if (!_port.support.pitchShift) {
      throw UnsupportedError('Pitch shift is not available for this media.');
    }

    final int request = ++_requestSerial;
    _pendingSequence = null;
    _emit(PitchControlState(
      confirmedSemitones: _state.confirmedSemitones,
      pendingSemitones: semitones,
      lastApplyLatency: _state.lastApplyLatency,
      errorCode: null,
    ));

    try {
      final int sequence = await _port.setPitchSemitones(semitones);
      if (sequence <= 0) throw StateError('Invalid command sequence.');
      if (!_disposed && request == _requestSerial) {
        _pendingSequence = sequence;
        if (_lastAppliedSequence >= sequence) _clearPending();
      }
      return sequence;
    } on Object {
      if (!_disposed && request == _requestSerial) {
        _emit(PitchControlState(
          confirmedSemitones: _state.confirmedSemitones,
          pendingSemitones: null,
          lastApplyLatency: _state.lastApplyLatency,
          errorCode: 'PITCH_COMMAND_FAILED',
        ));
      }
      throw const PitchCommandException();
    }
  }

  void _onApplied(AudioProcessingAppliedState applied) {
    if (_disposed || applied.lastPitchAppliedSequence < _lastAppliedSequence) {
      return;
    }
    _lastAppliedSequence = applied.lastPitchAppliedSequence;
    final bool completed = _pendingSequence != null &&
        applied.lastPitchAppliedSequence >= _pendingSequence!;
    _emit(PitchControlState(
      confirmedSemitones: applied.pitchSemitones,
      pendingSemitones: completed ? null : _state.pendingSemitones,
      lastApplyLatency: applied.lastPitchApplyLatency,
      errorCode: null,
    ));
  }

  void _clearPending() {
    _emit(PitchControlState(
      confirmedSemitones: _state.confirmedSemitones,
      pendingSemitones: null,
      lastApplyLatency: _state.lastApplyLatency,
      errorCode: null,
    ));
  }

  void _emit(PitchControlState state) {
    _state = state;
    _changes.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _changes.close();
  }
}

final class PitchCommandException implements Exception {
  const PitchCommandException();

  String get code => 'PITCH_COMMAND_FAILED';

  @override
  String toString() => 'PitchCommandException($code)';
}
