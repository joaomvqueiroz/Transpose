import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('normal Android build excludes the Rubber Band spike', (_) async {
    final AudioCoreFfi core = AudioCoreFfi();
    expect(core.dspAvailable, isFalse);
    final AudioCoreHandle handle = core.create();
    try {
      expect(handle.liveFrames, -5);
      expect(handle.liveQueueUnderruns, -5);
      expect(
        () => handle.startLiveDsp(
          '/does/not/exist.wav',
          semitones: 0,
          speed: 1,
          finer: false,
        ),
        throwsStateError,
      );
    } finally {
      handle.dispose();
    }
  }, skip: !Platform.isAndroid);
}
