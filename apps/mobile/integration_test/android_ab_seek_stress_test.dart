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
    'Android 100 seeks outside A/B preserve markers and parameters',
    (_) async {
      final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
      final Directory work = await Directory.systemTemp.createTemp('ab_seek_');
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
            id: 'loop-seek-fixture',
            displayName: 'input.wav',
            path: input.path,
          ),
        );
        media = loader.currentAudio!;
        final LoopRange range = LoopRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 4),
        );
        await media.setParameters(semitones: -3, speed: 0.75);
        await media.play();
        for (int cycle = 0; cycle < 100; ++cycle) {
          await media.setLoop(range);
          expect(media.loopEnabled, isTrue, reason: 'loop ON cycle $cycle');
          await media.seek(const Duration(milliseconds: 3000));
          expect(media.loopEnabled, isTrue, reason: 'inside seek cycle $cycle');
          await media.seek(const Duration(seconds: 8));
          expect(
            media.loopEnabled,
            isFalse,
            reason: 'outside seek cycle $cycle',
          );
          expect(media.loopRange, range);
          expect(media.platformSpeed, closeTo(0.75, 0.001));
          expect(media.platformPitch, closeTo(math.pow(2, -3 / 12), 0.001));
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(media.position >= const Duration(seconds: 8), isTrue);
        expect(media.position < const Duration(seconds: 9), isTrue);
        await media.pause();
      } finally {
        await media?.release();
        await work.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
