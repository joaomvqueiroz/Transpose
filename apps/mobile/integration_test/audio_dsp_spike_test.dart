import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('internal Rubber Band spike keeps pitch and speed independent', (
    _,
  ) async {
    final AudioCoreFfi core = AudioCoreFfi();
    expect(core.dspAvailable, isTrue);
    final ByteData fixtureAsset = await rootBundle.load('assets/qa_tone.wav');
    final Directory work = await Directory.systemTemp.createTemp('rb_spike_');
    final File input = File('${work.path}/input.wav');
    await input.writeAsBytes(
      fixtureAsset.buffer.asUint8List(
        fixtureAsset.offsetInBytes,
        fixtureAsset.lengthInBytes,
      ),
    );

    try {
      final List<
        ({
          String name,
          double semitones,
          double speed,
          bool finer,
          double hertz,
          double seconds,
        })
      >
      cases = [
        (
          name: 'identity_r2',
          semitones: 0,
          speed: 1,
          finer: false,
          hertz: 440,
          seconds: 12,
        ),
        (
          name: 'pitch_r2',
          semitones: -2,
          speed: 1,
          finer: false,
          hertz: 392,
          seconds: 12,
        ),
        (
          name: 'speed_r2',
          semitones: 0,
          speed: 0.75,
          finer: false,
          hertz: 440,
          seconds: 16,
        ),
        (
          name: 'combined_r2',
          semitones: -2,
          speed: 0.75,
          finer: false,
          hertz: 392,
          seconds: 16,
        ),
        (
          name: 'combined_r3',
          semitones: -2,
          speed: 0.75,
          finer: true,
          hertz: 392,
          seconds: 16,
        ),
      ];
      File? playbackFile;
      for (final sampleCase in cases) {
        final File output = File('${work.path}/${sampleCase.name}.wav');
        core.renderWavDsp(
          inputPath: input.path,
          outputPath: output.path,
          semitones: sampleCase.semitones,
          speed: sampleCase.speed,
          finer: sampleCase.finer,
        );
        final Uint8List bytes = await output.readAsBytes();
        final ByteData data = ByteData.sublistView(bytes);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(data.getUint16(22, Endian.little), 1);
        final int sampleRate = data.getUint32(24, Endian.little);
        expect(sampleRate, 48000);
        final double seconds = (bytes.length - 44) / (sampleRate * 2);
        final double hertz = _countHertz(data, sampleRate);
        debugPrint(
          'S-003 ${sampleCase.name}: duration=${seconds.toStringAsFixed(3)}s '
          'pitch=${hertz.toStringAsFixed(1)}Hz bytes=${bytes.length}',
        );
        expect(seconds, closeTo(sampleCase.seconds, 0.5));
        expect(hertz, closeTo(sampleCase.hertz, 10));
        if (sampleCase.name == 'combined_r2') playbackFile = output;
      }

      final AudioCoreHandle handle = core.create();
      try {
        handle.startWav(playbackFile!.path);
        for (int attempt = 0; attempt < 40 && !handle.wavFinished; ++attempt) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        debugPrint(
          'S-003 device playback: frames=${handle.wavFrames} '
          'xruns=${handle.toneXruns} finished=${handle.wavFinished}',
        );
        expect(handle.wavFinished, isTrue);
        expect(handle.wavFrames, greaterThan(48000 * 15));
        handle.stopOutput();

        for (final bool finer in <bool>[false, true]) {
          handle.startLiveDsp(
            input.path,
            semitones: -2,
            speed: 0.75,
            finer: finer,
          );
          for (
            int attempt = 0;
            attempt < 44 && !handle.liveFinished;
            ++attempt
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          debugPrint(
            'S-003 live ${finer ? 'R3' : 'R2'}: '
            'frames=${handle.liveFrames} '
            'queueUnderruns=${handle.liveQueueUnderruns} '
            'xruns=${handle.toneXruns} '
            'callbacks=${handle.callbackCalls} '
            'maxCallbackUs=${handle.callbackMaxMicroseconds} '
            'overBudget=${handle.callbacksOverBudget} '
            'finished=${handle.liveFinished}',
          );
          expect(handle.liveFinished, isTrue);
          expect(handle.liveFrames, greaterThan(48000 * 15));
          expect(handle.liveQueueUnderruns, 0);
          handle.stopOutput();
        }
      } finally {
        handle.dispose();
      }
    } finally {
      await work.delete(recursive: true);
    }
  }, skip: !Platform.isAndroid);
}

double _countHertz(ByteData wav, int sampleRate) {
  const int startSecond = 4;
  bool armed = false;
  int crossings = 0;
  for (
    int frame = startSecond * sampleRate;
    frame < (startSecond + 1) * sampleRate;
    ++frame
  ) {
    final int sample = wav.getInt16(44 + frame * 2, Endian.little);
    if (sample < -400) armed = true;
    if (armed && sample > 400) {
      ++crossings;
      armed = false;
    }
  }
  return crossings.toDouble();
}
