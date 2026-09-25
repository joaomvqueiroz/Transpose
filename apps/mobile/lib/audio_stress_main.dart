// Diagnostic entry point only. The normal app still starts from main.dart.
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';

const int _stressSeconds = int.fromEnvironment(
  'AUDIO_STRESS_SECONDS',
  defaultValue: 30,
);
const int _bufferBursts = int.fromEnvironment(
  'AUDIO_BUFFER_BURSTS',
  defaultValue: 2,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Audio output stress test'))),
    ),
  );
  if (_stressSeconds < 30 || _stressSeconds % 30 != 0) {
    throw ArgumentError.value(_stressSeconds, 'AUDIO_STRESS_SECONDS');
  }

  final AudioCoreHandle handle = AudioCoreFfi().create();
  try {
    handle.setBufferBursts(_bufferBursts);
    handle.startTone();
    int previousFrames = 0;
    for (int elapsed = 30; elapsed <= _stressSeconds; elapsed += 30) {
      await Future<void>.delayed(const Duration(seconds: 30));
      final int frames = handle.toneFrames;
      final int? xruns = handle.toneXruns;
      debugPrint(
        'S-002 release progress: elapsed=${elapsed}s frames=$frames '
        'xruns=$xruns',
      );
      if (frames <= previousFrames) {
        throw StateError('Native output stopped advancing at ${elapsed}s.');
      }
      previousFrames = frames;
    }
    final int sampleRate = handle.toneSampleRate;
    final int burstFrames = handle.toneBurstFrames;
    final int bufferFrames = handle.toneBufferFrames;
    final int frames = handle.toneFrames;
    final int? xruns = handle.toneXruns;
    handle.stopTone();
    if (sampleRate <= 0 || frames <= sampleRate * (_stressSeconds - 5)) {
      throw StateError('Native output produced too few frames.');
    }
    if (_stressSeconds >= 600 && xruns != null && xruns != 0) {
      throw StateError('Native output reported $xruns XRuns.');
    }
    debugPrint(
      'S-002 release PASS: duration=${_stressSeconds}s '
      'sampleRate=$sampleRate burstFrames=$burstFrames '
      'bufferFrames=$bufferFrames frames=$frames xruns=$xruns '
      'callbacks=${handle.callbackCalls} '
      'maxCallbackUs=${handle.callbackMaxMicroseconds} '
      'overBudget=${handle.callbacksOverBudget}',
    );
  } catch (error, stackTrace) {
    debugPrint('S-002 release FAIL: $error');
    debugPrint('$stackTrace');
    rethrow;
  } finally {
    handle.dispose();
  }
}
