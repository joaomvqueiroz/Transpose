import 'dart:async';

import 'package:player_core/player_core.dart';
import 'package:player_core/src/player_state_machine.dart';
import 'package:test/test.dart';

void main() {
  group('PlayerStateMachine', () {
    test('starts in IDLE without independent playback flags', () async {
      final PlayerStateMachine machine = PlayerStateMachine();

      expect(machine.state, PlayerState.idle);
      expect(machine.state.code, 'IDLE');
      expect(machine.lastTransition, isNull);
      expect(machine.invalidTransitionCount, 0);

      await machine.dispose();
    });

    test('implements the documented happy-path transitions', () async {
      final PlayerStateMachine machine = PlayerStateMachine();

      _apply(machine, PlayerEvent.load, PlayerState.loading);
      _apply(machine, PlayerEvent.loadOk, PlayerState.ready);
      _apply(machine, PlayerEvent.play, PlayerState.playing);
      _apply(machine, PlayerEvent.pause, PlayerState.paused);
      _apply(machine, PlayerEvent.play, PlayerState.playing);
      _apply(machine, PlayerEvent.bufferEmpty, PlayerState.buffering);
      _apply(machine, PlayerEvent.bufferReady, PlayerState.playing);
      _apply(machine, PlayerEvent.interruptionBegin, PlayerState.interrupted);
      _apply(machine, PlayerEvent.interruptionEnd, PlayerState.paused);
      _apply(machine, PlayerEvent.unload, PlayerState.idle);

      await machine.dispose();
    });

    test('maps load failure to ERROR', () async {
      final PlayerStateMachine machine = PlayerStateMachine();

      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadFail);

      expect(machine.state, PlayerState.error);
      await machine.dispose();
    });

    test('maps natural end and validated seek to ENDED then PAUSED', () async {
      final PlayerStateMachine machine = PlayerStateMachine();

      _driveTo(machine, PlayerState.playing);
      _apply(machine, PlayerEvent.endOfMedia, PlayerState.ended);
      _apply(machine, PlayerEvent.seekValid, PlayerState.paused);

      await machine.dispose();
    });

    test('SEEK preserves each loaded logical state', () async {
      const List<PlayerState> seekableStates = <PlayerState>[
        PlayerState.ready,
        PlayerState.playing,
        PlayerState.paused,
        PlayerState.buffering,
        PlayerState.interrupted,
      ];

      for (final PlayerState state in seekableStates) {
        final PlayerStateMachine machine = PlayerStateMachine();
        _driveTo(machine, state);

        final PlayerTransition transition =
            machine.applyConfirmedEvent(PlayerEvent.seek);

        expect(machine.state, state, reason: state.code);
        expect(transition.changesState, isFalse, reason: state.code);
        await machine.dispose();
      }
    });

    test('an interruption always ends safely in PAUSED', () async {
      for (final PlayerState source in <PlayerState>[
        PlayerState.playing,
        PlayerState.paused,
      ]) {
        final PlayerStateMachine machine = PlayerStateMachine();
        _driveTo(machine, source);

        machine
          ..applyConfirmedEvent(PlayerEvent.interruptionBegin)
          ..applyConfirmedEvent(PlayerEvent.interruptionEnd);

        expect(machine.state, PlayerState.paused, reason: source.code);
        await machine.dispose();
      }
    });

    test('FATAL_ERROR is valid from every state', () async {
      for (final PlayerState state in PlayerState.values) {
        final PlayerStateMachine machine = PlayerStateMachine();
        _driveTo(machine, state);

        final PlayerTransition transition =
            machine.applyConfirmedEvent(PlayerEvent.fatalError);

        expect(machine.state, PlayerState.error, reason: state.code);
        expect(transition.event, PlayerEvent.fatalError);
        await machine.dispose();
      }
    });

    test('UNLOAD is valid from every state and releases to IDLE', () async {
      for (final PlayerState state in PlayerState.values) {
        final PlayerStateMachine machine = PlayerStateMachine();
        _driveTo(machine, state);

        final PlayerTransition transition =
            machine.applyConfirmedEvent(PlayerEvent.unload);

        expect(machine.state, PlayerState.idle, reason: state.code);
        expect(transition.event, PlayerEvent.unload);
        await machine.dispose();
      }
    });

    test('rejects every undocumented transition without state mutation',
        () async {
      for (final PlayerState state in PlayerState.values) {
        for (final PlayerEvent event in PlayerEvent.values) {
          if (_isDocumented(state, event)) {
            continue;
          }

          final List<InvalidPlayerTransition> diagnostics =
              <InvalidPlayerTransition>[];
          final PlayerStateMachine machine = PlayerStateMachine(
            onTransitionError: (PlayerStateMachineError error) {
              if (error is InvalidPlayerTransition) {
                diagnostics.add(error);
              }
            },
          );
          _driveTo(machine, state);
          final PlayerTransition? before = machine.lastTransition;

          expect(
            () => machine.applyConfirmedEvent(event),
            throwsA(
              isA<InvalidPlayerTransition>()
                  .having(
                    (InvalidPlayerTransition error) => error.state,
                    'state',
                    state,
                  )
                  .having(
                    (InvalidPlayerTransition error) => error.event,
                    'event',
                    event,
                  ),
            ),
            reason: '${state.code} + ${event.code}',
          );
          expect(machine.state, state);
          expect(machine.lastTransition, same(before));
          expect(machine.invalidTransitionCount, 1);
          expect(machine.transitionErrorCount, 1);
          expect(diagnostics, hasLength(1));
          await machine.dispose();
        }
      }
    });

    test('emits ordered transitions and states with monotonic timestamps',
        () async {
      final _FakeClock clock = _FakeClock();
      final PlayerStateMachine machine = PlayerStateMachine(clock: clock);
      final List<PlayerTransition> transitions = <PlayerTransition>[];
      final List<PlayerState> states = <PlayerState>[];
      final StreamSubscription<PlayerTransition> transitionSubscription =
          machine.transitions.listen(transitions.add);
      final StreamSubscription<PlayerState> stateSubscription =
          machine.states.listen(states.add);

      clock.value = const Duration(microseconds: 100);
      machine.applyConfirmedEvent(PlayerEvent.load);
      clock.value = const Duration(microseconds: 250);
      machine.applyConfirmedEvent(PlayerEvent.loadOk);

      expect(states, <PlayerState>[PlayerState.loading, PlayerState.ready]);
      expect(transitions.map((PlayerTransition item) => item.sequence),
          <int>[1, 2]);
      expect(
        transitions.map(
          (PlayerTransition item) => item.monotonicTimestamp.inMicroseconds,
        ),
        <int>[100, 250],
      );

      await transitionSubscription.cancel();
      await stateSubscription.cancel();
      await machine.dispose();
    });

    test('does not expose PLAYING before a confirmed PLAY event', () async {
      final PlayerStateMachine machine = PlayerStateMachine();
      final PlayerStateView uiState = machine;
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk);

      // The public UI boundary is read-only and has no event/mutation method.
      expect(uiState.state, PlayerState.ready);

      machine.applyConfirmedEvent(PlayerEvent.play);
      expect(uiState.state, PlayerState.playing);

      await machine.dispose();
    });

    test('rejects reentrant listener transitions before mutation', () async {
      final List<PlayerTransition> transitions = <PlayerTransition>[];
      final List<PlayerState> states = <PlayerState>[];
      final List<PlayerStateMachineError> diagnostics =
          <PlayerStateMachineError>[];
      final PlayerStateMachine machine = PlayerStateMachine(
        onTransitionError: diagnostics.add,
      );
      Object? reentrantError;
      final StreamSubscription<PlayerTransition> transitionSubscription =
          machine.transitions.listen((PlayerTransition transition) {
        transitions.add(transition);
        try {
          machine.applyConfirmedEvent(PlayerEvent.loadOk);
        } on Object catch (error) {
          reentrantError = error;
        }
      });
      final StreamSubscription<PlayerState> stateSubscription =
          machine.states.listen(states.add);

      machine.applyConfirmedEvent(PlayerEvent.load);

      expect(reentrantError, isA<ReentrantPlayerTransition>());
      expect(machine.state, PlayerState.loading);
      expect(machine.lastTransition?.sequence, 1);
      expect(transitions, hasLength(1));
      expect(states, <PlayerState>[PlayerState.loading]);
      expect(machine.invalidTransitionCount, 0);
      expect(machine.transitionErrorCount, 1);
      expect(diagnostics.single, isA<ReentrantPlayerTransition>());

      await transitionSubscription.cancel();
      await stateSubscription.cancel();
      machine.applyConfirmedEvent(PlayerEvent.loadOk);
      expect(machine.state, PlayerState.ready);
      await machine.dispose();
    });

    test('cannot be used after disposal', () async {
      final PlayerStateMachine machine = PlayerStateMachine();
      await machine.dispose();

      expect(machine.isDisposed, isTrue);
      expect(
        () => machine.applyConfirmedEvent(PlayerEvent.load),
        throwsStateError,
      );
      expect(() => machine.canApply(PlayerEvent.load), throwsStateError);
      await machine.dispose();
    });
  });
}

void _apply(
  PlayerStateMachine machine,
  PlayerEvent event,
  PlayerState expected,
) {
  final PlayerTransition transition = machine.applyConfirmedEvent(event);
  expect(machine.state, expected, reason: event.code);
  expect(transition.to, expected, reason: event.code);
}

void _driveTo(PlayerStateMachine machine, PlayerState target) {
  switch (target) {
    case PlayerState.idle:
      return;
    case PlayerState.loading:
      machine.applyConfirmedEvent(PlayerEvent.load);
    case PlayerState.ready:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk);
    case PlayerState.playing:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk)
        ..applyConfirmedEvent(PlayerEvent.play);
    case PlayerState.paused:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk)
        ..applyConfirmedEvent(PlayerEvent.play)
        ..applyConfirmedEvent(PlayerEvent.pause);
    case PlayerState.buffering:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk)
        ..applyConfirmedEvent(PlayerEvent.play)
        ..applyConfirmedEvent(PlayerEvent.bufferEmpty);
    case PlayerState.interrupted:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk)
        ..applyConfirmedEvent(PlayerEvent.play)
        ..applyConfirmedEvent(PlayerEvent.interruptionBegin);
    case PlayerState.error:
      machine.applyConfirmedEvent(PlayerEvent.fatalError);
    case PlayerState.ended:
      machine
        ..applyConfirmedEvent(PlayerEvent.load)
        ..applyConfirmedEvent(PlayerEvent.loadOk)
        ..applyConfirmedEvent(PlayerEvent.play)
        ..applyConfirmedEvent(PlayerEvent.endOfMedia);
  }
}

bool _isDocumented(PlayerState state, PlayerEvent event) {
  if (event == PlayerEvent.fatalError || event == PlayerEvent.unload) {
    return true;
  }

  return switch ((state, event)) {
    (PlayerState.idle, PlayerEvent.load) => true,
    (PlayerState.loading, PlayerEvent.loadOk) => true,
    (PlayerState.loading, PlayerEvent.loadFail) => true,
    (PlayerState.ready, PlayerEvent.play) => true,
    (PlayerState.playing, PlayerEvent.pause) => true,
    (PlayerState.paused, PlayerEvent.play) => true,
    (PlayerState.playing, PlayerEvent.bufferEmpty) => true,
    (PlayerState.buffering, PlayerEvent.bufferReady) => true,
    (PlayerState.playing, PlayerEvent.interruptionBegin) => true,
    (PlayerState.paused, PlayerEvent.interruptionBegin) => true,
    (PlayerState.interrupted, PlayerEvent.interruptionEnd) => true,
    (PlayerState.playing, PlayerEvent.endOfMedia) => true,
    (PlayerState.ended, PlayerEvent.seekValid) => true,
    (PlayerState.ready, PlayerEvent.seek) => true,
    (PlayerState.playing, PlayerEvent.seek) => true,
    (PlayerState.paused, PlayerEvent.seek) => true,
    (PlayerState.buffering, PlayerEvent.seek) => true,
    (PlayerState.interrupted, PlayerEvent.seek) => true,
    _ => false,
  };
}

final class _FakeClock implements MonotonicClock {
  Duration value = Duration.zero;

  @override
  Duration now() => value;
}
