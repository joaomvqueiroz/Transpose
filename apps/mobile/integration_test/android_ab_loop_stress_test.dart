import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/media/native_audio_media_loader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android 500 ms A/B loop survives 100 transitions and parameter changes',
    (_) async {
      final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
      final Directory work = await Directory.systemTemp.createTemp(
        'ab_stress_',
      );
      final File input = File('${work.path}/input.wav');
      await input.writeAsBytes(
        fixture.buffer.asUint8List(
          fixture.offsetInBytes,
          fixture.lengthInBytes,
        ),
      );
      final NativeAudioMediaLoader loader = NativeAudioMediaLoader();
      NativeAudioLoadedMedia? media;
      try {
        await loader.load(
          LocalFileSource.fromPath(
            id: 'loop-stress-fixture',
            displayName: 'input.wav',
            path: input.path,
          ),
        );
        media = loader.currentAudio!;
        final LoopRange range = LoopRange(
          start: const Duration(seconds: 2),
          end: const Duration(milliseconds: 2500),
        );
        await media.setParameters(semitones: -2, speed: 1);
        await media.setLoop(range);
        _expectParameters(media, semitones: -2, speed: 1);
        await media.play();

        await _waitForLoops(media, 20);
        await media.setParameters(semitones: 3, speed: 0.75);
        _expectParameters(media, semitones: 3, speed: 0.75);
        await _waitForLoops(media, 40);
        await media.setParameters(semitones: -5, speed: 2);
        _expectParameters(media, semitones: -5, speed: 2);
        await _waitForLoops(media, 100);

        expect(media.loopEnabled, isTrue);
        expect(
          media.position >= range.start && media.position <= range.end,
          isTrue,
        );
        expect(media.duration, const Duration(seconds: 12));
        _expectParameters(media, semitones: -5, speed: 2);
        await media.clearLoop();
        expect(media.loopEnabled, isFalse);
        expect(media.loopRange, range);
        _expectParameters(media, semitones: -5, speed: 2);
        await media.pause();
      } finally {
        await media?.release();
        await work.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Android active playback survives 100 A/B on/off cycles',
    (_) async {
      final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
      final Directory work = await Directory.systemTemp.createTemp(
        'ab_toggle_',
      );
      final File input = File('${work.path}/input.wav');
      await input.writeAsBytes(
        fixture.buffer.asUint8List(
          fixture.offsetInBytes,
          fixture.lengthInBytes,
        ),
      );
      final NativeAudioMediaLoader loader = NativeAudioMediaLoader();
      NativeAudioLoadedMedia? media;
      try {
        await loader.load(
          LocalFileSource.fromPath(
            id: 'loop-toggle-fixture',
            displayName: 'input.wav',
            path: input.path,
          ),
        );
        media = loader.currentAudio!;
        final LoopRange range = LoopRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 4),
        );
        await media.setParameters(semitones: 2, speed: 0.75);
        await media.play();
        for (int cycle = 0; cycle < 100; ++cycle) {
          await media.setLoop(range);
          expect(media.loopEnabled, isTrue, reason: 'ON cycle $cycle');
          expect(media.loopRange, range);
          _expectParameters(media, semitones: 2, speed: 0.75);
          await media.clearLoop();
          expect(media.loopEnabled, isFalse, reason: 'OFF cycle $cycle');
          expect(media.loopRange, range);
          _expectParameters(media, semitones: 2, speed: 0.75);
        }
        await media.pause();
      } finally {
        await media?.release();
        await work.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Android active loop survives 200 A and 200 B edits',
    (_) async {
      final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
      final Directory work = await Directory.systemTemp.createTemp('ab_edit_');
      final File input = File('${work.path}/input.wav');
      await input.writeAsBytes(
        fixture.buffer.asUint8List(
          fixture.offsetInBytes,
          fixture.lengthInBytes,
        ),
      );
      final NativeAudioMediaLoader loader = NativeAudioMediaLoader();
      NativeAudioLoadedMedia? media;
      try {
        await loader.load(
          LocalFileSource.fromPath(
            id: 'loop-edit-fixture',
            displayName: 'input.wav',
            path: input.path,
          ),
        );
        media = loader.currentAudio!;
        LoopRange range = LoopRange(
          start: const Duration(milliseconds: 2000),
          end: const Duration(milliseconds: 2200),
        );
        await media.setParameters(semitones: -2, speed: 0.75);
        await media.setLoop(range);
        await media.play();
        for (int edit = 0; edit < 200; ++edit) {
          final Duration nextA = Duration(milliseconds: 2000 + (edit % 5) * 10);
          range = LoopRange(start: nextA, end: range.end);
          await media.setLoop(range);
          expect(media.loopEnabled, isTrue, reason: 'A edit $edit');
          expect(media.loopRange, range);

          final Duration nextB = Duration(milliseconds: 2070 + (edit % 5) * 10);
          range = LoopRange(start: nextA, end: nextB);
          await media.setLoop(range);
          expect(media.loopEnabled, isTrue, reason: 'B edit $edit');
          expect(media.loopRange, range);
          _expectParameters(media, semitones: -2, speed: 0.75);
        }
        await media.pause();
      } finally {
        await media?.release();
        await work.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _waitForLoops(NativeAudioLoadedMedia media, int target) async {
  for (int attempt = 0; attempt < 250 && media.loopCount < target; ++attempt) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(media.loopCount, greaterThanOrEqualTo(target));
}

void _expectParameters(
  NativeAudioLoadedMedia media, {
  required double semitones,
  required double speed,
}) {
  expect(media.platformSpeed, closeTo(speed, 0.001));
  expect(media.platformPitch, closeTo(math.pow(2, semitones / 12), 0.001));
}
