import 'player_event.dart';
import 'player_state.dart';

/// Monotonic time source used for ordering diagnostics and measuring latency.
abstract interface class MonotonicClock {
  Duration now();
}

/// Process-local monotonic clock backed by [Stopwatch].
final class StopwatchMonotonicClock implements MonotonicClock {
  StopwatchMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  Duration now() => _stopwatch.elapsed;
}

/// Immutable diagnostic record for one accepted state-machine event.
final class PlayerTransition {
  const PlayerTransition({
    required this.sequence,
    required this.from,
    required this.event,
    required this.to,
    required this.monotonicTimestamp,
  });

  final int sequence;
  final PlayerState from;
  final PlayerEvent event;
  final PlayerState to;
  final Duration monotonicTimestamp;

  bool get changesState => from != to;

  @override
  String toString() =>
      'PlayerTransition($sequence: ${from.code} --${event.code}--> '
      '${to.code} at ${monotonicTimestamp.inMicroseconds}us)';
}

/// Base class for state-machine programming errors.
sealed class PlayerStateMachineError implements Exception {
  const PlayerStateMachineError({required this.state, required this.event});

  final PlayerState state;
  final PlayerEvent event;
}

/// Raised when an event is impossible in the current state.
final class InvalidPlayerTransition extends PlayerStateMachineError {
  const InvalidPlayerTransition({required super.state, required super.event});

  @override
  String toString() =>
      'InvalidPlayerTransition: ${event.code} is not valid from ${state.code}';
}

/// Raised when a synchronous listener tries to mutate the machine recursively.
final class ReentrantPlayerTransition extends PlayerStateMachineError {
  const ReentrantPlayerTransition({required super.state, required super.event});

  @override
  String toString() =>
      'ReentrantPlayerTransition: ${event.code} was requested while '
      'a transition from ${state.code} was still being published';
}

typedef TransitionErrorObserver = void Function(PlayerStateMachineError error);
