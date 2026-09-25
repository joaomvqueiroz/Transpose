import 'dart:async';

import 'player_event.dart';
import 'player_state.dart';
import 'player_state_view.dart';
import 'player_transition.dart';

/// Strict state machine for exactly one media session.
///
/// This class accepts confirmed backend events. UI code should observe [state]
/// and [states], while a future application/controller layer translates user
/// intents and backend acknowledgements into [PlayerEvent] values.
final class PlayerStateMachine implements PlayerStateView {
  PlayerStateMachine({
    MonotonicClock? clock,
    TransitionErrorObserver? onTransitionError,
  })  : _clock = clock ?? StopwatchMonotonicClock(),
        _onTransitionError = onTransitionError;

  final MonotonicClock _clock;
  final TransitionErrorObserver? _onTransitionError;
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<PlayerTransition> _transitionController =
      StreamController<PlayerTransition>.broadcast(sync: true);

  PlayerState _state = PlayerState.idle;
  PlayerTransition? _lastTransition;
  int _sequence = 0;
  int _invalidTransitionCount = 0;
  int _transitionErrorCount = 0;
  bool _isDisposed = false;
  bool _isApplying = false;
  bool _isReportingTransitionError = false;

  @override
  PlayerState get state => _state;

  PlayerTransition? get lastTransition => _lastTransition;

  int get invalidTransitionCount => _invalidTransitionCount;

  int get transitionErrorCount => _transitionErrorCount;

  bool get isDisposed => _isDisposed;

  /// Emits every accepted event, including explicit same-state transitions.
  @override
  Stream<PlayerState> get states => _stateController.stream;

  /// Emits diagnostic transition records in the same order as [states].
  Stream<PlayerTransition> get transitions => _transitionController.stream;

  /// Returns whether [event] is valid without changing state.
  bool canApply(PlayerEvent event) {
    _ensureActive();
    return _resolve(_state, event) != null;
  }

  /// Applies a backend-confirmed event and returns its diagnostic record.
  ///
  /// An invalid event increments [invalidTransitionCount], invokes the optional
  /// observer, and throws without mutating state or sequence.
  PlayerTransition applyConfirmedEvent(PlayerEvent event) {
    _ensureActive();

    if (_isApplying || _isReportingTransitionError) {
      final ReentrantPlayerTransition error = ReentrantPlayerTransition(
        state: _state,
        event: event,
      );
      _reportTransitionError(error);
      throw error;
    }

    final PlayerState from = _state;
    final PlayerState? to = _resolve(from, event);
    if (to == null) {
      final InvalidPlayerTransition error = InvalidPlayerTransition(
        state: from,
        event: event,
      );
      _invalidTransitionCount += 1;
      _reportTransitionError(error);
      throw error;
    }

    _isApplying = true;
    try {
      final PlayerTransition transition = PlayerTransition(
        sequence: _sequence + 1,
        from: from,
        event: event,
        to: to,
        monotonicTimestamp: _clock.now(),
      );

      _sequence = transition.sequence;
      _state = to;
      _lastTransition = transition;
      _transitionController.add(transition);
      _stateController.add(to);
      return transition;
    } finally {
      _isApplying = false;
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await Future.wait<void>(<Future<void>>[
      _transitionController.close(),
      _stateController.close(),
    ]);
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('PlayerStateMachine has been disposed.');
    }
  }

  void _reportTransitionError(PlayerStateMachineError error) {
    _transitionErrorCount += 1;
    if (_isReportingTransitionError) {
      return;
    }

    _isReportingTransitionError = true;
    try {
      _onTransitionError?.call(error);
    } finally {
      _isReportingTransitionError = false;
    }
  }

  static PlayerState? _resolve(PlayerState state, PlayerEvent event) {
    if (event == PlayerEvent.fatalError) {
      return PlayerState.error;
    }
    if (event == PlayerEvent.unload) {
      return PlayerState.idle;
    }

    return switch ((state, event)) {
      (PlayerState.idle, PlayerEvent.load) => PlayerState.loading,
      (PlayerState.loading, PlayerEvent.loadOk) => PlayerState.ready,
      (PlayerState.loading, PlayerEvent.loadFail) => PlayerState.error,
      (PlayerState.ready, PlayerEvent.play) => PlayerState.playing,
      (PlayerState.playing, PlayerEvent.pause) => PlayerState.paused,
      (PlayerState.paused, PlayerEvent.play) => PlayerState.playing,
      (PlayerState.playing, PlayerEvent.bufferEmpty) => PlayerState.buffering,
      (PlayerState.buffering, PlayerEvent.bufferReady) => PlayerState.playing,
      (PlayerState.playing, PlayerEvent.interruptionBegin) =>
        PlayerState.interrupted,
      (PlayerState.paused, PlayerEvent.interruptionBegin) =>
        PlayerState.interrupted,
      (PlayerState.interrupted, PlayerEvent.interruptionEnd) =>
        PlayerState.paused,
      (PlayerState.playing, PlayerEvent.endOfMedia) => PlayerState.ended,
      (PlayerState.ended, PlayerEvent.seekValid) => PlayerState.paused,
      (PlayerState.ready, PlayerEvent.seek) => PlayerState.ready,
      (PlayerState.playing, PlayerEvent.seek) => PlayerState.playing,
      (PlayerState.paused, PlayerEvent.seek) => PlayerState.paused,
      (PlayerState.buffering, PlayerEvent.seek) => PlayerState.buffering,
      (PlayerState.interrupted, PlayerEvent.seek) => PlayerState.interrupted,
      _ => null,
    };
  }
}
