import 'dart:async';

import 'media_loader.dart';
import 'media_source.dart';
import 'player_event.dart';
import 'player_state.dart';
import 'player_state_machine.dart';
import 'player_state_view.dart';
import 'player_transition.dart';

/// Sanitized public failure to prepare a source.
final class PlayerLoadException implements Exception {
  const PlayerLoadException();

  String get code => 'PLAYER_LOAD_FAILED';

  @override
  String toString() => 'PlayerLoadException($code)';
}

/// Sanitized public failure to release a loaded resource.
final class PlayerReleaseException implements Exception {
  const PlayerReleaseException();

  @override
  String toString() => 'PlayerReleaseException';
}

/// Sanitized public failure from a playback command.
final class PlayerCommandException implements Exception {
  const PlayerCommandException(this.code);

  final String code;

  @override
  String toString() => 'PlayerCommandException($code)';
}

/// Owns one state machine and at most one loaded media resource.
///
/// Commands are serialized. A new load first releases the previous resource,
/// including when two load requests arrive while preparation is in progress.
/// The same [sessionId] stays in use throughout those changes.
final class PlayerSession implements PlayerStateView {
  PlayerSession({
    required this.sessionId,
    required MediaLoader loader,
    MonotonicClock? clock,
    TransitionErrorObserver? onTransitionError,
  })  : _loader = loader,
        _machine = PlayerStateMachine(
          clock: clock,
          onTransitionError: onTransitionError,
        ) {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError('must not be blank', 'sessionId');
    }
  }

  final String sessionId;
  final MediaLoader _loader;
  final PlayerStateMachine _machine;

  Future<void> _operationTail = Future<void>.value();
  Future<void>? _disposeFuture;
  LoadedMedia? _loaded;
  StreamSubscription<void>? _endSubscription;
  StreamSubscription<void>? _interruptionSubscription;
  int _interruptionRevision = 0;
  MediaSource? _source;
  bool _closing = false;
  bool _disposed = false;

  @override
  PlayerState get state => _machine.state;

  @override
  Stream<PlayerState> get states => _machine.states;

  Stream<PlayerTransition> get transitions => _machine.transitions;

  MediaSource? get source => _source;

  Duration? get duration => _loaded?.duration;

  Duration? get position => _loaded?.position;

  bool get isDisposed => _disposed;

  /// Monotonic safety revision, also usable by outer command queues to discard
  /// Play intents that were enqueued before an external interruption.
  int get interruptionRevision => _interruptionRevision;

  /// Replaces the current media without creating a second active resource.
  ///
  /// `LOADING` begins before the adapter runs. `READY` is emitted only after
  /// the adapter returns a prepared [LoadedMedia]. A failure enters `ERROR`.
  Future<void> load(MediaSource source) => _enqueue(() async {
        await _unloadCurrent();
        _machine.applyConfirmedEvent(PlayerEvent.load);

        late final LoadedMedia prepared;
        try {
          prepared = await _loader.load(source);
        } on Object {
          _machine.applyConfirmedEvent(PlayerEvent.loadFail);
          throw const PlayerLoadException();
        }

        _loaded = prepared;
        _source = source;
        _machine.applyConfirmedEvent(PlayerEvent.loadOk);
        if (prepared is InterruptedLoadedMedia) {
          _interruptionSubscription = prepared.interruptionEvents.listen((_) {
            if (_closing || _disposed || !identical(_loaded, prepared)) return;
            // Invalidate queued starts immediately, not when the serialized
            // state update eventually reaches the head of the command queue.
            _interruptionRevision++;
            unawaited(_enqueue(() async {
              if (identical(_loaded, prepared)) _confirmInterruption();
            }).catchError((Object _) {}));
          });
        }
        _endSubscription = prepared.endEvents.listen((_) {
          if (_closing || _disposed) return;
          unawaited(_enqueue(() async {
            if (identical(_loaded, prepared) &&
                _machine.state == PlayerState.playing) {
              _machine.applyConfirmedEvent(PlayerEvent.endOfMedia);
            }
          }).catchError((Object _) {}));
        });
      });

  /// Releases the current resource and returns to `IDLE` on confirmation.
  Future<void> unload() => _enqueue(_unloadCurrent);

  /// Starts output and emits PLAYING only after the adapter confirms it.
  ///
  /// Repeated Play requests are idempotent. Requests queued during loading
  /// run after load completes, but never create a second media resource.
  Future<void> play() {
    final int revision = _interruptionRevision;
    return _enqueue(() async {
      if (revision != _interruptionRevision) return;
      if (_machine.state == PlayerState.playing) {
        return;
      }
      if (_machine.state != PlayerState.ready &&
          _machine.state != PlayerState.paused) {
        throw StateError('Play is not valid from ${_machine.state.code}.');
      }

      try {
        await _loaded!.play();
      } on MediaPlaybackInterrupted {
        // The adapter has already confirmed silence. Keep source and seek
        // position, and never promote a refused start to PLAYING.
        _confirmInterruption();
        return;
      } on Object {
        await _abortFailedCommand();
        throw const PlayerCommandException('PLAYER_PLAY_FAILED');
      }
      if (revision != _interruptionRevision) {
        await _loaded!.pause();
        _confirmInterruption();
        return;
      }
      _machine.applyConfirmedEvent(PlayerEvent.play);
    });
  }

  /// Stops output and emits PAUSED only after the adapter confirms silence.
  /// Repeated Pause requests are idempotent.
  Future<void> pause() => _enqueue(() async {
        if (_machine.state == PlayerState.paused) {
          return;
        }
        if (_machine.state != PlayerState.playing) {
          throw StateError('Pause is not valid from ${_machine.state.code}.');
        }

        try {
          await _loaded!.pause();
        } on Object {
          await _abortFailedCommand();
          throw const PlayerCommandException('PLAYER_PAUSE_FAILED');
        }
        _machine.applyConfirmedEvent(PlayerEvent.pause);
      });

  /// Seeks within the loaded timeline without changing playback intent.
  ///
  /// Invalid targets are rejected before contacting the adapter. A backend
  /// failure retains the current state so the user may retry the seek.
  Future<Duration> seek(Duration target) => _enqueueValue(() async {
        final PlayerState currentState = _machine.state;
        if (currentState != PlayerState.ready &&
            currentState != PlayerState.playing &&
            currentState != PlayerState.paused &&
            currentState != PlayerState.buffering &&
            currentState != PlayerState.interrupted &&
            currentState != PlayerState.ended) {
          throw StateError('Seek is not valid from ${currentState.code}.');
        }
        if (!_source!.capabilities.canSeek) {
          throw UnsupportedError('This source does not support seeking.');
        }
        final Duration? mediaDuration = _loaded!.duration;
        if (target.isNegative ||
            (mediaDuration != null && target > mediaDuration)) {
          throw RangeError('Seek target is outside the media timeline.');
        }

        late final Duration actual;
        try {
          actual = await _loaded!.seek(target);
        } on Object {
          throw const PlayerCommandException('PLAYER_SEEK_FAILED');
        }
        if (actual.isNegative ||
            (mediaDuration != null && actual > mediaDuration)) {
          throw const PlayerCommandException('PLAYER_SEEK_FAILED');
        }
        _machine.applyConfirmedEvent(currentState == PlayerState.ended
            ? PlayerEvent.seekValid
            : PlayerEvent.seek);
        return actual;
      });

  /// Releases the resource, closes streams and rejects later commands.
  ///
  /// A failed release leaves the session in `ERROR` and allows a retry.
  Future<void> dispose() {
    if (_disposed) {
      return Future<void>.value();
    }
    final Future<void>? pending = _disposeFuture;
    if (pending != null) {
      return pending;
    }

    _closing = true;
    final Future<void> result = _operationTail.then((_) async {
      try {
        await _unloadCurrent();
        await _machine.dispose();
        _disposed = true;
      } on Object {
        _closing = false;
        _disposeFuture = null;
        rethrow;
      }
    });
    _disposeFuture = result;
    return result;
  }

  Future<void> _unloadCurrent() async {
    final LoadedMedia? loaded = _loaded;
    if (loaded != null) {
      await _endSubscription?.cancel();
      _endSubscription = null;
      await _interruptionSubscription?.cancel();
      _interruptionSubscription = null;
      try {
        await loaded.release();
      } on Object {
        _machine.applyConfirmedEvent(PlayerEvent.fatalError);
        throw const PlayerReleaseException();
      }
      _loaded = null;
      _source = null;
    }
    if (_machine.state != PlayerState.idle) {
      _machine.applyConfirmedEvent(PlayerEvent.unload);
    }
  }

  Future<void> _abortFailedCommand() async {
    _machine.applyConfirmedEvent(PlayerEvent.fatalError);
    final LoadedMedia? loaded = _loaded;
    if (loaded == null) {
      return;
    }
    await _endSubscription?.cancel();
    _endSubscription = null;
    await _interruptionSubscription?.cancel();
    _interruptionSubscription = null;
    try {
      await loaded.release();
      _loaded = null;
      _source = null;
    } on Object {
      // Retain the handle for an explicit unload/retry. The public command
      // error remains sanitized; the adapter must make release retryable.
    }
  }

  void _confirmInterruption() {
    if (_machine.state == PlayerState.playing ||
        _machine.state == PlayerState.paused) {
      _machine.applyConfirmedEvent(PlayerEvent.interruptionBegin);
      // A native event is emitted after output is paused and pending playback
      // intent cancelled. The settled state requires a fresh user Play.
      _machine.applyConfirmedEvent(PlayerEvent.interruptionEnd);
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    return _enqueueValue<void>(operation);
  }

  Future<T> _enqueueValue<T>(Future<T> Function() operation) {
    if (_closing || _disposed) {
      return Future<T>.error(StateError('PlayerSession is closing.'));
    }

    final Future<T> result = _operationTail.then((_) => operation());
    // Keep the queue alive after a failed operation so a later unload/load
    // can recover from ERROR. The caller still receives the original failure.
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}
