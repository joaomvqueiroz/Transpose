import 'dart:async';

import 'package:player_core/player_core.dart';
import 'package:test/test.dart';

void main() {
  group('PlayerSession load/unload', () {
    test('enters LOADING, then READY only after the loader confirms', () async {
      final _TrackingLoader loader = _TrackingLoader();
      final Completer<LoadedMedia> pending = Completer<LoadedMedia>();
      loader.nextLoad = pending.future;
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      final List<PlayerState> states = <PlayerState>[];
      final StreamSubscription<PlayerState> subscription =
          session.states.listen(states.add);
      final LocalFileSource source = _source('one');

      final Future<void> loading = session.load(source);
      await _settle();
      expect(session.state, PlayerState.loading);
      expect(session.source, isNull);
      expect(states, <PlayerState>[PlayerState.loading]);

      pending
          .complete(_TrackedMedia(loader, 'one', const Duration(seconds: 42)));
      await loading;
      expect(session.state, PlayerState.ready);
      expect(session.source, same(source));
      expect(session.duration, const Duration(seconds: 42));
      expect(states, <PlayerState>[PlayerState.loading, PlayerState.ready]);

      await subscription.cancel();
      await session.dispose();
    });

    test('unload releases the resource before entering IDLE', () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));

      await session.unload();

      expect(loader.events, <String>['load:one', 'release:one']);
      expect(loader.activeCount, 0);
      expect(session.state, PlayerState.idle);
      expect(session.source, isNull);
      expect(session.duration, isNull);
      await session.dispose();
    });

    test('a replacement releases the prior handle before preparing the next',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );

      await session.load(_source('one'));
      await session.load(_source('two'));

      expect(
        loader.events,
        <String>['load:one', 'release:one', 'load:two'],
      );
      expect(loader.peakActiveCount, 1);
      expect(loader.activeCount, 1);
      expect(session.source?.id, 'two');
      expect(session.sessionId, 'session-1');
      expect(session.state, PlayerState.ready);
      await session.dispose();
    });

    test('concurrent load requests remain serialized with one active handle',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final Completer<LoadedMedia> firstPending = Completer<LoadedMedia>();
      loader.nextLoad = firstPending.future;
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );

      final Future<void> first = session.load(_source('one'));
      final Future<void> second = session.load(_source('two'));
      await _settle();
      expect(loader.events, <String>['load:one']);
      expect(session.state, PlayerState.loading);

      firstPending.complete(_TrackedMedia(loader, 'one', null));
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(
        loader.events,
        <String>['load:one', 'release:one', 'load:two'],
      );
      expect(loader.peakActiveCount, 1);
      expect(session.source?.id, 'two');
      await session.dispose();
    });

    test('an unload queued during loading releases the prepared resource',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final Completer<LoadedMedia> pending = Completer<LoadedMedia>();
      loader.nextLoad = pending.future;
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );

      final Future<void> loading = session.load(_source('one'));
      final Future<void> unloading = session.unload();
      await _settle();
      expect(session.state, PlayerState.loading);

      pending.complete(_TrackedMedia(loader, 'one', null));
      await Future.wait<void>(<Future<void>>[loading, unloading]);

      expect(loader.events, <String>['load:one', 'release:one']);
      expect(loader.activeCount, 0);
      expect(session.state, PlayerState.idle);
      await session.dispose();
    });

    test('load failure enters ERROR and a later load can recover', () async {
      final _TrackingLoader loader = _TrackingLoader()..failNextLoad = true;
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );

      await expectLater(
          session.load(_source('broken')),
          throwsA(
            isA<PlayerLoadException>()
                .having((PlayerLoadException error) => error.code, 'code',
                    'PLAYER_LOAD_FAILED')
                .having((PlayerLoadException error) => error.toString(),
                    'sanitized message', isNot(contains('private file path'))),
          ));
      expect(session.state, PlayerState.error);
      expect(session.source, isNull);
      expect(loader.activeCount, 0);

      await session.load(_source('good'));
      expect(session.state, PlayerState.ready);
      expect(session.source?.id, 'good');
      expect(loader.events, <String>['load:broken', 'load:good']);
      await session.dispose();
    });

    test('release failure blocks replacement and permits explicit retry',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      loader.failNextRelease = true;

      await expectLater(
        session.load(_source('two')),
        throwsA(isA<PlayerReleaseException>()),
      );

      expect(session.state, PlayerState.error);
      expect(session.source?.id, 'one');
      expect(loader.events, <String>['load:one', 'release:one']);
      expect(loader.activeCount, 1);

      await session.unload();
      expect(session.state, PlayerState.idle);
      expect(loader.activeCount, 0);
      await session.dispose();
    });

    test('dispose releases media, closes streams and rejects new commands',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));

      await session.dispose();

      expect(session.isDisposed, isTrue);
      expect(session.state, PlayerState.idle);
      expect(loader.activeCount, 0);
      await expectLater(session.load(_source('two')), throwsStateError);
      await expectLater(session.unload(), throwsStateError);
      await session.dispose();
    });

    test('failed disposal can be retried after resource release recovers',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      loader.failNextRelease = true;

      await expectLater(
          session.dispose(), throwsA(isA<PlayerReleaseException>()));
      expect(session.isDisposed, isFalse);
      expect(session.state, PlayerState.error);
      expect(loader.activeCount, 1);

      await session.dispose();
      expect(session.isDisposed, isTrue);
      expect(session.state, PlayerState.idle);
      expect(loader.activeCount, 0);
    });

    test('a blank session id is rejected before loading', () {
      expect(
        () => PlayerSession(sessionId: ' ', loader: _TrackingLoader()),
        throwsArgumentError,
      );
    });
  });

  group('PlayerSession play/pause', () {
    test('changes state only after play and pause are confirmed', () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));

      final Completer<void> playAck = Completer<void>();
      loader.nextPlay = playAck.future;
      final Future<void> playing = session.play();
      await _settle();
      expect(session.state, PlayerState.ready);
      expect(loader.events, <String>['load:one', 'play:one']);
      playAck.complete();
      await playing;
      expect(session.state, PlayerState.playing);

      final Completer<void> pauseAck = Completer<void>();
      loader.nextPause = pauseAck.future;
      final Future<void> pausing = session.pause();
      await _settle();
      expect(session.state, PlayerState.playing);
      expect(loader.events.last, 'pause:one');
      pauseAck.complete();
      await pausing;
      expect(session.state, PlayerState.paused);
      await session.dispose();
    });

    test('repeated commands are idempotent and do not duplicate output',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));

      await session.play();
      await session.play();
      await session.pause();
      await session.pause();
      expect(loader.events, <String>[
        'load:one',
        'play:one',
        'pause:one',
      ]);
      expect(loader.outputCount, 0);
      expect(loader.peakOutputCount, 1);
      expect(session.state, PlayerState.paused);
      await session.dispose();
    });

    test('20 sequences of 30 rapid alternations never overlap output',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));

      final List<Future<void>> commands = <Future<void>>[];
      for (int sequence = 0; sequence < 20; sequence++) {
        for (int i = 0; i < 30; i++) {
          commands.add(session.play());
          commands.add(session.pause());
        }
      }
      await Future.wait<void>(commands);

      expect(session.state, PlayerState.paused);
      expect(loader.outputCount, 0);
      expect(loader.peakOutputCount, 1);
      expect(loader.events.where((String event) => event == 'play:one').length,
          600);
      expect(loader.events.where((String event) => event == 'pause:one').length,
          600);
      await session.dispose();
    });

    test('invalid commands do not reach the backend', () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await expectLater(session.play(), throwsStateError);
      await expectLater(session.pause(), throwsStateError);
      await session.load(_source('one'));
      await expectLater(session.pause(), throwsStateError);
      expect(loader.events, <String>['load:one']);
      await session.dispose();
    });

    test('play and pause failures enter ERROR with sanitized codes', () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      loader.failNextPlay = true;
      await expectLater(
        session.play(),
        throwsA(isA<PlayerCommandException>().having(
          (PlayerCommandException error) => error.code,
          'code',
          'PLAYER_PLAY_FAILED',
        )),
      );
      expect(session.state, PlayerState.error);
      expect(loader.outputCount, 0);
      expect(loader.activeCount, 0);

      await session.load(_source('two'));
      await session.play();
      loader.failNextPause = true;
      await expectLater(
        session.pause(),
        throwsA(isA<PlayerCommandException>().having(
          (PlayerCommandException error) => error.code,
          'code',
          'PLAYER_PAUSE_FAILED',
        )),
      );
      expect(session.state, PlayerState.error);
      expect(loader.outputCount, 0);
      expect(loader.activeCount, 0);
      await session.unload();
      await session.dispose();
    });

    test('replacing a playing source stops it before loading the next',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      await session.play();
      await session.load(_source('two'));

      expect(loader.events,
          <String>['load:one', 'play:one', 'release:one', 'load:two']);
      expect(loader.outputCount, 0);
      expect(loader.peakOutputCount, 1);
      expect(session.state, PlayerState.ready);
      await session.dispose();
    });

    test('a failed safety release remains retryable after pause failure',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      await session.play();
      loader.failNextPause = true;
      loader.failNextRelease = true;

      await expectLater(
        session.pause(),
        throwsA(isA<PlayerCommandException>()),
      );
      expect(session.state, PlayerState.error);
      expect(loader.activeCount, 1);

      await session.unload();
      expect(session.state, PlayerState.idle);
      expect(loader.activeCount, 0);
      expect(loader.outputCount, 0);
      await session.dispose();
    });
  });

  group('PlayerSession seek', () {
    test('seeks only after backend confirmation and preserves play state',
        () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(minutes: 10);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      await session.play();
      final Completer<void> ack = Completer<void>();
      loader.nextSeek = ack.future;

      final Future<Duration> seeking = session.seek(const Duration(minutes: 7));
      await _settle();
      expect(session.position, Duration.zero);
      expect(session.state, PlayerState.playing);
      ack.complete();
      expect(await seeking, const Duration(minutes: 7));
      expect(session.position, const Duration(minutes: 7));
      expect(session.state, PlayerState.playing);
      expect(loader.outputCount, 1);

      await session.pause();
      expect(await session.seek(const Duration(minutes: 2)),
          const Duration(minutes: 2));
      expect(session.state, PlayerState.paused);
      await session.dispose();
    });

    test('rejects invalid range, state and capability before backend calls',
        () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(seconds: 30);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await expectLater(session.seek(Duration.zero), throwsStateError);
      await session.load(_source('one'));
      await expectLater(
          session.seek(const Duration(seconds: -1)), throwsRangeError);
      await expectLater(
          session.seek(const Duration(seconds: 31)), throwsRangeError);
      expect(loader.events, <String>['load:one']);

      await session.load(_NoSeekSource());
      await expectLater(
          session.seek(Duration.zero), throwsA(isA<UnsupportedError>()));
      expect(loader.events.last, 'load:no-seek');
      await session.dispose();
    });

    test('rapid seek requests remain serialized and final position wins',
        () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(minutes: 10);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      final List<Future<Duration>> seeks = <Future<Duration>>[];
      for (int second = 1; second <= 30; second++) {
        seeks.add(session.seek(Duration(seconds: second)));
      }
      final List<Duration> results = await Future.wait<Duration>(seeks);
      expect(results.last, const Duration(seconds: 30));
      expect(session.position, const Duration(seconds: 30));
      expect(session.state, PlayerState.ready);
      expect(loader.events.where((String event) => event.startsWith('seek:')),
          hasLength(30));
      await session.dispose();
    });

    test('backend failure is sanitized and leaves session retryable', () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(minutes: 10);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      await session.play();
      loader.failNextSeek = true;

      await expectLater(
        session.seek(const Duration(minutes: 7)),
        throwsA(isA<PlayerCommandException>().having(
          (PlayerCommandException error) => error.code,
          'code',
          'PLAYER_SEEK_FAILED',
        )),
      );
      expect(session.state, PlayerState.playing);
      expect(session.position, Duration.zero);
      expect(loader.outputCount, 1);
      expect(await session.seek(const Duration(minutes: 7)),
          const Duration(minutes: 7));
      await session.dispose();
    });
  });

  group('PlayerSession end of media', () {
    test('natural end enters ENDED once and explicit replay starts at zero',
        () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(seconds: 3);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      final List<PlayerState> states = <PlayerState>[];
      final StreamSubscription<PlayerState> subscription =
          session.states.listen(states.add);
      await session.load(_source('one'));
      await session.play();

      loader.lastMedia!.emitEnd();
      await _settle();
      expect(session.state, PlayerState.ended);
      expect(session.position, const Duration(seconds: 3));
      expect(loader.outputCount, 0);
      expect(states.where((PlayerState state) => state == PlayerState.ended),
          hasLength(1));

      loader.lastMedia!.emitEnd();
      await _settle();
      expect(states.where((PlayerState state) => state == PlayerState.ended),
          hasLength(1));
      await session.seek(Duration.zero);
      expect(session.state, PlayerState.paused);
      await session.play();
      expect(session.state, PlayerState.playing);
      expect(session.position, Duration.zero);
      await subscription.cancel();
      await session.dispose();
    });

    test('100 non-looping endings leave no output or unexpected restart',
        () async {
      final _TrackingLoader loader = _TrackingLoader();
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );

      for (int i = 0; i < 100; i++) {
        loader.nextDuration = const Duration(milliseconds: 500);
        await session.load(_source('one'));
        await session.play();
        loader.lastMedia!.emitEnd();
        await _settle();
        expect(session.state, PlayerState.ended);
        expect(session.position, const Duration(milliseconds: 500));
        expect(loader.outputCount, 0);
        await session.unload();
      }
      expect(loader.peakActiveCount, 1);
      expect(loader.activeCount, 0);
      await session.dispose();
    });

    test('completion emitted by old resource during release is ignored',
        () async {
      final _TrackingLoader loader = _TrackingLoader()
        ..nextDuration = const Duration(seconds: 3);
      final PlayerSession session = PlayerSession(
        sessionId: 'session-1',
        loader: loader,
      );
      await session.load(_source('one'));
      await session.play();
      loader.lastMedia!.emitEndOnRelease = true;

      await session.load(_source('two'));
      await _settle();
      expect(session.state, PlayerState.ready);
      expect(session.source?.id, 'two');
      expect(loader.activeCount, 1);
      await session.dispose();
    });
  });
}

LocalFileSource _source(String id) => LocalFileSource.fromPath(
      id: id,
      displayName: 'Fixture $id',
      path: '/fixtures/$id.wav',
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _NoSeekSource extends MediaSource {
  _NoSeekSource()
      : super(
          id: 'no-seek',
          type: MediaSourceType.authorizedRemote,
          displayName: 'No seek',
          locator: Uri.parse('https://example.invalid/media'),
          capabilities: MediaCapabilities.none,
        );
}

final class _TrackingLoader implements MediaLoader {
  final List<String> events = <String>[];
  Future<LoadedMedia>? nextLoad;
  bool failNextLoad = false;
  bool failNextRelease = false;
  bool failNextPlay = false;
  bool failNextPause = false;
  bool failNextSeek = false;
  Future<void>? nextPlay;
  Future<void>? nextPause;
  Future<void>? nextSeek;
  Duration? nextDuration;
  _TrackedMedia? lastMedia;
  int activeCount = 0;
  int peakActiveCount = 0;
  int outputCount = 0;
  int peakOutputCount = 0;

  @override
  Future<LoadedMedia> load(MediaSource source) async {
    events.add('load:${source.id}');
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('private file path should not escape');
    }

    final Future<LoadedMedia>? pending = nextLoad;
    if (pending != null) {
      nextLoad = null;
      return pending;
    }
    final Duration? duration = nextDuration;
    nextDuration = null;
    final _TrackedMedia media = _TrackedMedia(this, source.id, duration);
    lastMedia = media;
    return media;
  }
}

final class _TrackedMedia implements LoadedMedia {
  _TrackedMedia(this.owner, this.id, this.duration) {
    owner.activeCount += 1;
    if (owner.activeCount > owner.peakActiveCount) {
      owner.peakActiveCount = owner.activeCount;
    }
  }

  final _TrackingLoader owner;
  final String id;
  bool _playing = false;
  bool emitEndOnRelease = false;
  final StreamController<void> _ends =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get endEvents => _ends.stream;

  @override
  Duration position = Duration.zero;

  @override
  final Duration? duration;

  @override
  Future<void> play() async {
    owner.events.add('play:$id');
    if (owner.failNextPlay) {
      owner.failNextPlay = false;
      throw StateError('private playback details should not escape');
    }
    final Future<void>? pending = owner.nextPlay;
    owner.nextPlay = null;
    if (pending != null) {
      await pending;
    }
    if (!_playing) {
      _playing = true;
      owner.outputCount += 1;
      if (owner.outputCount > owner.peakOutputCount) {
        owner.peakOutputCount = owner.outputCount;
      }
    }
  }

  @override
  Future<void> pause() async {
    owner.events.add('pause:$id');
    if (owner.failNextPause) {
      owner.failNextPause = false;
      throw StateError('private playback details should not escape');
    }
    final Future<void>? pending = owner.nextPause;
    owner.nextPause = null;
    if (pending != null) {
      await pending;
    }
    if (_playing) {
      _playing = false;
      owner.outputCount -= 1;
    }
  }

  @override
  Future<Duration> seek(Duration target) async {
    owner.events.add('seek:$id:${target.inMilliseconds}');
    if (owner.failNextSeek) {
      owner.failNextSeek = false;
      throw StateError('private decoder details should not escape');
    }
    final Future<void>? pending = owner.nextSeek;
    owner.nextSeek = null;
    if (pending != null) {
      await pending;
    }
    position = target;
    return position;
  }

  void emitEnd() {
    owner.events.add('end:$id');
    if (_playing) {
      _playing = false;
      owner.outputCount -= 1;
    }
    position = duration ?? position;
    _ends.add(null);
  }

  @override
  Future<void> release() async {
    owner.events.add('release:$id');
    if (emitEndOnRelease) {
      emitEnd();
    }
    if (owner.failNextRelease) {
      owner.failNextRelease = false;
      throw StateError('private resource details should not escape');
    }
    if (_playing) {
      _playing = false;
      owner.outputCount -= 1;
    }
    owner.activeCount -= 1;
    await _ends.close();
  }
}
