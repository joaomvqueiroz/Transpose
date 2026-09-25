import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const MethodChannel _probe = MethodChannel('transpose/native_processing_probe');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Media3 accepts independent pitch and speed on Android', (
    _,
  ) async {
    final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
    final Directory work = await Directory.systemTemp.createTemp(
      'media3_probe_',
    );
    final File input = File('${work.path}/input.wav');
    await input.writeAsBytes(
      fixture.buffer.asUint8List(fixture.offsetInBytes, fixture.lengthInBytes),
    );

    try {
      await _probe.invokeMethod<Object>('prepare', {'path': input.path});
      Map<Object?, Object?> state = await _waitReady();
      expect(state['ready'], isTrue);
      expect(state['durationMs'], closeTo(12000, 100));

      state = await _setParameters(-2, 0.75);
      expect((state['speed'] as num).toDouble(), closeTo(0.75, 0.001));
      expect(
        (state['pitch'] as num).toDouble(),
        closeTo(math.pow(2, -2 / 12).toDouble(), 0.001),
      );
      await _probe.invokeMethod<Object>('play');
      await Future<void>.delayed(const Duration(seconds: 2));
      final Map<Object?, Object?> first = await _snapshot();
      final int firstPosition = first['positionMs'] as int;
      debugPrint('Native Media3 0.75x/-2: $first');
      expect(first['playing'], isTrue);
      expect(firstPosition, inInclusiveRange(900, 2200));

      state = await _setParameters(3, 1.25);
      expect((state['speed'] as num).toDouble(), closeTo(1.25, 0.001));
      expect(
        (state['pitch'] as num).toDouble(),
        closeTo(math.pow(2, 3 / 12).toDouble(), 0.001),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      final Map<Object?, Object?> second = await _snapshot();
      final int secondDelta = (second['positionMs'] as int) - firstPosition;
      debugPrint('Native Media3 1.25x/+3: $second, delta=$secondDelta');
      expect(second['playing'], isTrue);
      expect(secondDelta, inInclusiveRange(1800, 3200));
    } finally {
      await _probe.invokeMethod<void>('release');
      await work.delete(recursive: true);
    }
  }, skip: !Platform.isAndroid);
}

Future<Map<Object?, Object?>> _setParameters(
  double semitones,
  double speed,
) async {
  final Map<Object?, Object?>? state = await _probe
      .invokeMapMethod<Object?, Object?>('setParameters', {
        'semitones': semitones,
        'speed': speed,
      });
  return state!;
}

Future<Map<Object?, Object?>> _snapshot() async {
  final Map<Object?, Object?>? state = await _probe
      .invokeMapMethod<Object?, Object?>('snapshot');
  return state!;
}

Future<Map<Object?, Object?>> _waitReady() async {
  for (int attempt = 0; attempt < 50; ++attempt) {
    final Map<Object?, Object?> state = await _snapshot();
    if (state['ready'] == true) return state;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Media3 did not prepare the QA WAV within 5 seconds.');
}
