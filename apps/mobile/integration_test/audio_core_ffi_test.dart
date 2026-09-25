import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const int _bufferBursts = int.fromEnvironment(
  'AUDIO_BUFFER_BURSTS',
  defaultValue: 2,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Flutter reaches C++ through the C ABI', (_) async {
    final AudioCoreFfi core = AudioCoreFfi();
    expect(core.abiVersion, 6);
    final AudioCoreHandle handle = core.create();
    expect(handle.ping(41), 42);
    expect(() => handle.ping(-1), throwsRangeError);
    handle.dispose();
    handle.dispose();
    expect(() => handle.ping(41), throwsStateError);
  }, skip: !Platform.isAndroid);

  testWidgets('native Android output advances and stops without DSP', (
    _,
  ) async {
    final AudioCoreHandle handle = AudioCoreFfi().create();
    try {
      handle.startTone();
      expect(handle.toneSampleRate, greaterThan(0));
      expect(handle.toneBurstFrames, greaterThan(0));
      expect(handle.toneBufferFrames, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final int framesDuringOutput = handle.toneFrames;
      expect(framesDuringOutput, greaterThan(0));
      handle.stopTone();
      final int stoppedFrames = handle.toneFrames;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(handle.toneFrames, stoppedFrames);
      expect(handle.toneXruns, anyOf(isNull, greaterThanOrEqualTo(0)));
    } finally {
      handle.dispose();
    }
  }, skip: !Platform.isAndroid);

  testWidgets('native Android output plays a local PCM16 WAV to its end', (
    _,
  ) async {
    final ByteData asset = await rootBundle.load('assets/qa_tone.wav');
    final File fixture = File(
      '${Directory.systemTemp.path}/transpose_qa_'
      '${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final File invalidFixture = File('${fixture.path}.invalid');
    await fixture.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    await invalidFixture.writeAsBytes(<int>[0, 1, 2, 3]);
    final AudioCoreHandle handle = AudioCoreFfi().create();
    try {
      handle.setBufferBursts(_bufferBursts);
      expect(
        () => handle.startWav('${fixture.path}.missing'),
        throwsStateError,
      );
      expect(() => handle.startWav(invalidFixture.path), throwsStateError);
      handle.startWav(fixture.path);
      expect(handle.toneSampleRate, 48000);
      debugPrint(
        'S-002 WAV buffer: requestedBursts=$_bufferBursts '
        'burstFrames=${handle.toneBurstFrames} '
        'bufferFrames=${handle.toneBufferFrames}',
      );
      int? lastXruns = handle.toneXruns;
      debugPrint('S-002 WAV start: xruns=$lastXruns');
      for (int attempt = 0; attempt < 32 && !handle.wavFinished; ++attempt) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final int? currentXruns = handle.toneXruns;
        if (currentXruns != lastXruns) {
          debugPrint(
            'S-002 WAV xrun change: elapsed~${(attempt + 1) * 500}ms '
            'frames=${handle.wavFrames} xruns=$currentXruns',
          );
          lastXruns = currentXruns;
        }
      }
      final int frames = handle.wavFrames;
      final int? xruns = handle.toneXruns;
      debugPrint(
        'S-002 WAV: frames=$frames finished=${handle.wavFinished} '
        'xruns=$xruns callbacks=${handle.callbackCalls} '
        'maxCallbackUs=${handle.callbackMaxMicroseconds} '
        'overBudget=${handle.callbacksOverBudget}',
      );
      expect(handle.wavFinished, isTrue);
      expect(frames, 48000 * 12);
      expect(handle.callbackCalls, greaterThan(0));
      expect(handle.callbackMaxMicroseconds, greaterThan(0));
      expect(xruns, anyOf(isNull, greaterThanOrEqualTo(0)));
      handle.stopOutput();
    } finally {
      handle.dispose();
      await fixture.delete();
      await invalidFixture.delete();
    }
  }, skip: !Platform.isAndroid);

  testWidgets('native tone runs for the configured stress duration', (_) async {
    const int stressSeconds = int.fromEnvironment(
      'AUDIO_STRESS_SECONDS',
      defaultValue: 30,
    );
    expect(stressSeconds, greaterThanOrEqualTo(30));
    expect(stressSeconds % 30, 0);
    final AudioCoreHandle handle = AudioCoreFfi().create();
    try {
      handle.setBufferBursts(_bufferBursts);
      handle.startTone();
      int previousFrames = 0;
      int? previousXruns = handle.toneXruns;
      debugPrint(
        'S-002 tone start: requestedBursts=$_bufferBursts '
        'burstFrames=${handle.toneBurstFrames} '
        'bufferFrames=${handle.toneBufferFrames} xruns=$previousXruns',
      );
      for (int elapsed = 5; elapsed <= stressSeconds; elapsed += 5) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final int currentFrames = handle.toneFrames;
        final int? currentXruns = handle.toneXruns;
        if (currentXruns != previousXruns) {
          debugPrint(
            'S-002 tone xrun change: elapsed~${elapsed}s '
            'frames=$currentFrames xruns=$currentXruns '
            'maxCallbackUs=${handle.callbackMaxMicroseconds} '
            'overBudget=${handle.callbacksOverBudget}',
          );
          previousXruns = currentXruns;
        }
        if (elapsed % 30 == 0) {
          debugPrint(
            'S-002 progress: elapsed=${elapsed}s frames=$currentFrames '
            'xruns=$currentXruns',
          );
        }
        expect(currentFrames, greaterThan(previousFrames));
        previousFrames = currentFrames;
      }
      final int sampleRate = handle.toneSampleRate;
      final int burstFrames = handle.toneBurstFrames;
      final int bufferFrames = handle.toneBufferFrames;
      final int frames = handle.toneFrames;
      final int? xruns = handle.toneXruns;
      handle.stopTone();
      debugPrint(
        'S-002 final: duration=${stressSeconds}s sampleRate=$sampleRate '
        'burstFrames=$burstFrames bufferFrames=$bufferFrames '
        'frames=$frames xruns=$xruns callbacks=${handle.callbackCalls} '
        'maxCallbackUs=${handle.callbackMaxMicroseconds} '
        'overBudget=${handle.callbacksOverBudget}',
      );
      expect(sampleRate, greaterThan(0));
      expect(frames, greaterThan(sampleRate * (stressSeconds - 5)));
      expect(handle.callbackCalls, greaterThan(0));
      if (stressSeconds >= 600 && xruns != null) {
        expect(xruns, 0, reason: 'Ten-minute stress run must not underrun.');
      }
    } finally {
      handle.dispose();
    }
  }, skip: !Platform.isAndroid);
}
