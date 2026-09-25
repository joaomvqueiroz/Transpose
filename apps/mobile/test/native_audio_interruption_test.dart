import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';
import 'package:transpose_mobile/media/native_audio_media_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native_audio_interruption');
  late _Native native;
  late PlayerSession session;
  final source = LocalFileSource.fromPath(
    id: 'audio',
    displayName: 'Local audio',
    path: '/test/audio.wav',
  );

  setUp(() {
    native = _Native();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    session = PlayerSession(
      sessionId: 'interruption-test',
      loader: NativeAudioMediaLoader(channel: channel),
    );
  });
  tearDown(() async {
    await session.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'native focus/noisy snapshot settles session paused without autoplay',
    () async {
      final states = <PlayerState>[];
      final subscription = session.states.listen(states.add);
      await session.load(source);
      await session.play();
      native.interrupt();
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(session.state, PlayerState.paused);
      expect(session.source, same(source));
      expect(session.position, const Duration(seconds: 4));
      expect(states.takeLast(2), <PlayerState>[
        PlayerState.interrupted,
        PlayerState.paused,
      ]);
      expect(native.releases, 0);
      final revision = session.interruptionRevision;
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(native.plays, 1);
      expect(session.interruptionRevision, revision);
      expect(native.playing, isFalse);
      await session.play();
      expect(session.state, PlayerState.playing);
      expect(native.playing, isTrue);
      expect(native.lastPlayRevision, 1);
      await subscription.cancel();
    },
  );

  test(
    'stale start rejected by native revision retains source, not ERROR',
    () async {
      await session.load(source);
      // Stop before the Dart polling cycle has had a chance to observe it.
      native.interrupt();
      await session.play();
      await Future<void>.delayed(Duration.zero);
      expect(native.playing, isFalse);
      expect(native.lastPlayRevision, 0);
      expect(session.source, same(source));
      expect(session.state, isNot(PlayerState.error));
      expect(native.releases, 0);
      await session.play();
      expect(native.lastPlayRevision, 1);
      expect(session.state, PlayerState.playing);
    },
  );

  test('focus refusal is recoverable and never unloads a valid file', () async {
    await session.load(source);
    native.denyFocus = true;
    await session.play();
    await Future<void>.delayed(Duration.zero);
    expect(session.state, isNot(PlayerState.playing));
    expect(session.state, isNot(PlayerState.error));
    expect(session.source, same(source));
    expect(native.releases, 0);
    native.denyFocus = false;
    await session.play();
    expect(session.state, PlayerState.playing);
  });

  test(
    'buffering without an interruption revision is not a safety pause',
    () async {
      await session.load(source);
      await session.play();
      native.playing = false;
      native.playWhenReady = true;
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(session.state, PlayerState.playing);
      expect(session.interruptionRevision, 0);
    },
  );

  test(
    'play waits for short post-seek buffering without unloading the source',
    () async {
      await session.load(source);
      await session.seek(const Duration(milliseconds: 3800));
      native.bufferOnPlay = true;
      var completed = false;
      final starting = session.play().then((_) => completed = true);
      await native.playSeen.future;
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(native.playWhenReady, isTrue);
      expect(native.playing, isFalse);
      expect(completed, isFalse);
      expect(session.state, isNot(PlayerState.error));
      expect(native.releases, 0);
      native.finishBuffering();
      await starting;
      expect(session.state, PlayerState.playing);
      expect(session.source, same(source));
      expect(native.playing, isTrue);
      expect(native.plays, 1);
      expect(native.releases, 0);
    },
  );

  test(
    'focus loss while initial play waits preserves the source ready and silent',
    () async {
      await session.load(source);
      native.bufferOnPlay = true;
      final starting = session.play();
      await native.playSeen.future;
      await Future<void>.delayed(const Duration(milliseconds: 75));
      final staleQueuedPlay = session.play();
      native.interrupt();
      await Future.wait<void>(<Future<void>>[starting, staleQueuedPlay]);
      await Future<void>.delayed(Duration.zero);
      // PLAYING was never confirmed, so the core correctly remains READY.
      expect(session.state, PlayerState.ready);
      expect(session.source, same(source));
      expect(native.playing, isFalse);
      expect(native.playWhenReady, isFalse);
      expect(native.releases, 0);
      expect(native.plays, 1);
      native.finishBuffering();
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(session.state, PlayerState.ready);
      expect(native.playing, isFalse);
      expect(native.plays, 1);
      native.bufferOnPlay = false;
      await session.play();
      expect(session.state, PlayerState.playing);
      expect(native.plays, 2);
      expect(native.lastPlayRevision, 1);
    },
  );

  test(
    'outer main and local queues discard pre-interruption Play intents',
    () async {
      final local = LocalPlayerController(
        loader: NativeAudioMediaLoader(channel: channel),
      );
      final main = MainPlayerController(local: local);
      await local.load(source);
      await main.playPause();
      native.seekGate = Completer<void>();
      final seeking = main.seek(const Duration(seconds: 8));
      await Future<void>.delayed(Duration.zero);
      final mainPlay = main.playPause();
      final localPlay = local.playPause();
      native.interrupt();
      await Future<void>.delayed(const Duration(milliseconds: 170));
      expect(local.interruptionRevision, 1);
      native.seekGate!.complete();
      await Future.wait<void>(<Future<void>>[seeking, mainPlay, localPlay]);
      await Future<void>.delayed(Duration.zero);
      expect(main.playing, isFalse);
      expect(native.playing, isFalse);
      expect(native.plays, 1);
      await main.playPause();
      expect(main.playing, isTrue);
      expect(native.plays, 2);
      await local.close();
      main.dispose();
    },
  );
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}

class _Native {
  bool playing = false, playWhenReady = false, denyFocus = false;
  bool bufferOnPlay = false, buffering = false;
  final playSeen = Completer<void>();
  int revision = 0, plays = 0, releases = 0;
  int? lastPlayRevision;
  Completer<void>? seekGate;

  void interrupt() {
    revision++;
    playing = false;
    playWhenReady = false;
  }

  void finishBuffering() {
    buffering = false;
    playing = playWhenReady;
  }

  Map<String, Object> snapshot() => <String, Object>{
    'ready': !buffering,
    'ended': false,
    'playing': playing,
    'playWhenReady': playWhenReady,
    'interruptionRevision': revision,
    'interruptionReason': revision == 0 ? '' : 'audioRoute',
    'durationMs': 60000,
    'positionMs': 4000,
    'speed': 1.0,
    'pitch': 1.0,
    'loopEnabled': false,
  };

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'load':
        return snapshot();
      case 'play':
        plays++;
        lastPlayRevision =
            (call.arguments as Map)['interruptionRevision'] as int;
        if (lastPlayRevision == revision && !denyFocus) {
          buffering = bufferOnPlay;
          playing = !buffering;
          playWhenReady = true;
        }
        if (!playSeen.isCompleted) playSeen.complete();
        return snapshot();
      case 'pause':
        playing = false;
        playWhenReady = false;
        return snapshot();
      case 'snapshot':
        return snapshot();
      case 'seek':
        await seekGate?.future;
        return snapshot();
      case 'release':
        releases++;
        playing = false;
        playWhenReady = false;
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}
