import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/media/native_audio_media_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native_audio_loop_observation');
  final source = LocalFileSource.fromPath(
    id: 'loop-observation',
    displayName: 'Loop observation',
    path: '/test/loop.wav',
  );
  late _Native native;
  late NativeAudioMediaLoader loader;

  setUp(() {
    native = _Native();
    loader = NativeAudioMediaLoader(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
  });
  tearDown(() async {
    await loader.currentAudio?.release();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mediaTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // testWidgets checks pending timers before the outer tearDown runs.
        await loader.currentAudio?.release();
      }
    });
  }

  mediaTest('exports native epoch/count and actual readiness', (tester) async {
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    expect(media.loopEventsAvailable, isTrue);
    expect(media.loopEpoch, 1);
    expect(media.loopCount, 0);
    expect(media.nativeReady, isTrue);
    expect(media.nativePlaying, isFalse);

    await media.setLoop(
      LoopRange(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
      ),
    );
    expect(media.loopEpoch, 2);
    expect(media.loopCount, 0);
    await media.play();
    expect(media.nativePlaying, isTrue);
    native.completeLoop();
    native.completeLoop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.loopCount, 2);
    expect(media.loopEpoch, 2);

    native.ready = false;
    native.playing = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.nativeReady, isFalse);
    expect(media.nativePlaying, isFalse);
    expect(media.loopCount, 2);
    expect(media.loopEventsAvailable, isTrue);
  });

  mediaTest('seek changes epoch without inventing a repetition', (
    tester,
  ) async {
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    await media.setLoop(
      LoopRange(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
      ),
    );
    native.completeLoop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.loopCount, 1);
    final previousEpoch = media.loopEpoch;
    await media.seek(const Duration(milliseconds: 3800));
    expect(media.loopEpoch, greaterThan(previousEpoch));
    expect(media.loopCount, 0);
    expect(media.position, const Duration(milliseconds: 3800));
    // This is a native contract mock, not evidence of an acoustic boundary.
    // Only native engine count changes may create repetitions in the adapter.
    native.positionMs = 2000;
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.loopCount, 0);
    native.completeLoop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.loopCount, 1);
  });

  mediaTest('pause/resume preserves the native counting scope', (tester) async {
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    await media.setLoop(
      LoopRange(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
      ),
    );
    await media.play();
    native.completeLoop();
    await tester.pump(const Duration(milliseconds: 100));
    final epoch = media.loopEpoch;
    await media.pause();
    await tester.pump(const Duration(seconds: 20));
    expect(media.loopCount, 1);
    expect(media.loopEpoch, epoch);
    expect(media.nativePlaying, isFalse);
    await media.play();
    expect(media.loopCount, 1);
    expect(media.loopEpoch, epoch);
  });

  mediaTest('stale polling response cannot roll back a seek epoch', (
    tester,
  ) async {
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    await media.setLoop(
      LoopRange(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
      ),
    );
    native.completeLoop();
    final gate = Completer<Map<String, Object>>();
    native.nextSnapshotGate = gate;
    final oldSnapshot = native.snapshot();
    await tester.pump(const Duration(milliseconds: 100));
    await media.seek(const Duration(milliseconds: 2500));
    final epochAfterSeek = media.loopEpoch;
    expect(media.loopCount, 0);
    gate.complete(oldSnapshot);
    await tester.pump();
    expect(media.loopEpoch, epochAfterSeek);
    expect(media.loopCount, 0);
    expect(media.position, const Duration(milliseconds: 2500));
  });

  mediaTest('older native schema does not claim confirmed loop support', (
    tester,
  ) async {
    native.providesLoopObservations = false;
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    expect(media.loopEventsAvailable, isFalse);
    native.positionMs = 2000;
    await tester.pump(const Duration(milliseconds: 100));
    native.positionMs = 4000;
    await tester.pump(const Duration(milliseconds: 100));
    native.positionMs = 2000;
    await tester.pump(const Duration(milliseconds: 100));
    expect(media.loopCount, 0);
    expect(media.loopEventsAvailable, isFalse);
  });

  mediaTest('release invalidates observation readiness and support', (
    tester,
  ) async {
    final media = await loader.load(source) as NativeAudioLoadedMedia;
    await media.play();
    await media.release();
    expect(media.loopEventsAvailable, isFalse);
    expect(media.nativeReady, isFalse);
    expect(media.nativePlaying, isFalse);
    expect(loader.currentAudio, isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}

class _Native {
  bool providesLoopObservations = true;
  bool ready = true, playing = false, loopEnabled = false;
  int epoch = 1, count = 0, revision = 0, positionMs = 2000;
  Completer<Map<String, Object>>? nextSnapshotGate;

  void completeLoop() {
    count++;
    positionMs = 2000;
  }

  Map<String, Object> snapshot() => <String, Object>{
    'ready': ready,
    'playing': playing,
    'playWhenReady': playing,
    'ended': false,
    'durationMs': 60000,
    'positionMs': positionMs,
    'speed': 1.0,
    'pitch': 1.0,
    'loopEnabled': loopEnabled,
    'loopCount': count,
    if (providesLoopObservations) ...<String, Object>{
      'loopEventsAvailable': true,
      'loopEpoch': epoch,
      'snapshotRevision': ++revision,
    },
  };

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'load':
        return snapshot();
      case 'snapshot':
        final gate = nextSnapshotGate;
        nextSnapshotGate = null;
        return gate == null ? snapshot() : gate.future;
      case 'setLoop':
        loopEnabled = true;
        epoch++;
        count = 0;
        return snapshot();
      case 'clearLoop':
        loopEnabled = false;
        epoch++;
        count = 0;
        return snapshot();
      case 'seek':
        positionMs = (call.arguments as Map)['positionMs'] as int;
        epoch++;
        count = 0;
        return snapshot();
      case 'play':
        playing = true;
        return snapshot();
      case 'pause':
        playing = false;
        return snapshot();
      case 'release':
        playing = false;
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}
