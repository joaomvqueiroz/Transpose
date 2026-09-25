import 'dart:async';

import 'package:player_core/player_core.dart';
import 'package:test/test.dart';

void main() {
  final source = LocalFileSource.fromPath(
    id: 'track',
    displayName: 'Track',
    path: '/track.wav',
  );

  test('external pause cancels already queued Play, preserves source',
      () async {
    final media = _Media();
    final player = PlayerSession(sessionId: 'one', loader: _Loader(media));
    await player.load(source);
    await player.play();
    media.seekGate = Completer<void>();
    final seek = player.seek(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    final queuedPlay = player.play();
    media.interrupt();
    expect(player.interruptionRevision, 1);
    media.seekGate!.complete();
    await seek;
    await queuedPlay;
    await Future<void>.delayed(Duration.zero);
    expect(player.state, PlayerState.paused);
    expect(media.playCalls, 1);
    expect(player.source, same(source));
    expect(media.released, isFalse);
    await player.play();
    expect(media.playCalls, 2);
    expect(player.state, PlayerState.playing);
    await player.dispose();
  });

  test('late acknowledgement after interruption cannot promote to playing',
      () async {
    final media = _Media()..playGate = Completer<void>();
    final player = PlayerSession(sessionId: 'two', loader: _Loader(media));
    await player.load(source);
    final play = player.play();
    await Future<void>.delayed(Duration.zero);
    media.interrupt();
    media.playGate!.complete();
    await play;
    await Future<void>.delayed(Duration.zero);
    expect(player.state, isNot(PlayerState.playing));
    expect(media.playing, isFalse);
    expect(media.pauseCalls, 1);
    expect(media.released, isFalse);
    await player.dispose();
  });

  test('refused start is not a fatal media failure', () async {
    final media = _Media()..refusePlay = true;
    final player = PlayerSession(sessionId: 'three', loader: _Loader(media));
    await player.load(source);
    await player.play();
    expect(player.state, PlayerState.ready);
    expect(media.released, isFalse);
    media.refusePlay = false;
    await player.play();
    expect(player.state, PlayerState.playing);
    await player.dispose();
  });
}

class _Loader implements MediaLoader {
  _Loader(this.media);
  final _Media media;
  @override
  Future<LoadedMedia> load(MediaSource source) async => media;
}

class _Media implements InterruptedLoadedMedia {
  final events = StreamController<void>.broadcast(sync: true);
  final ends = StreamController<void>.broadcast();
  Completer<void>? seekGate, playGate;
  bool released = false, playing = false, refusePlay = false;
  int playCalls = 0, pauseCalls = 0;
  @override
  Duration get duration => const Duration(minutes: 1);
  @override
  Duration position = Duration.zero;
  @override
  Stream<void> get endEvents => ends.stream;
  @override
  Stream<void> get interruptionEvents => events.stream;
  void interrupt() {
    playing = false;
    events.add(null);
  }

  @override
  Future<void> play() async {
    playCalls++;
    await playGate?.future;
    if (refusePlay) throw const MediaPlaybackInterrupted();
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<Duration> seek(Duration target) async {
    await seekGate?.future;
    position = target;
    return target;
  }

  @override
  Future<void> release() async {
    released = true;
    playing = false;
    await events.close();
    await ends.close();
  }
}
