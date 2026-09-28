import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _stems = MethodChannel('transpose/stems');
const _names = ['drums', 'bass', 'other', 'vocals', 'guitar', 'piano'];

Future<Map<String, Object?>> _status() async =>
    (await _stems.invokeMapMethod<String, Object?>('status'))!;

Future<Map<String, Object?>> _until(
  Set<String> terminal, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final current = await _status();
    if (terminal.contains(current['phase']) && current['busy'] != true) {
      return current;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TimeoutException('Separação/modelo excedeu o tempo de prova.', timeout);
}

Future<File> _fixture(
  String name, {
  required bool valid,
  bool silence = false,
}) async {
  final root = Directory('${(await getTemporaryDirectory()).path}/stem_inputs');
  await root.create(recursive: true);
  final file = File('${root.path}/$name.wav');
  if (!valid) return file.writeAsBytes(List<int>.filled(100, 0));
  const frames = 44100;
  final data = ByteData(44 + frames * 4);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, 44100, Endian.little);
  data.setUint32(28, 176400, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 4, Endian.little);
  if (!silence) {
    for (var i = 0; i < frames; i++) {
      final sample = (sin(i * 2 * pi * 440 / 44100) * 10000).round();
      data.setInt16(44 + i * 4, sample, Endian.little);
      data.setInt16(46 + i * 4, sample, Endian.little);
    }
  }
  return file.writeAsBytes(data.buffer.asUint8List());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('six local outputs, invalid WAV and real cancellation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Stem QA'))),
    );
    expect(await _stems.invokeMethod<bool>('available'), isTrue);
    await _stems.invokeMethod<void>('prepare');
    final prepared = await _until({
      'ready',
      'error',
      'cancelled',
    }, timeout: const Duration(minutes: 5));
    expect(prepared['phase'], 'ready', reason: '${prepared['error']}');
    expect(prepared['modelReady'], isTrue);
    debugPrint(
      'Stem QA memory: available=${prepared['availableMemoryBytes']} threshold=${prepared['lowMemoryThresholdBytes']} bytes',
    );

    // Measure first-operation inference in a fresh QA process when requested.
    if (const bool.fromEnvironment('STEMS_TONE_ONLY')) {
      final tone = await _fixture('fresh_tone', valid: true);
      await _stems.invokeMethod<void>('start', {'input': tone.path});
      final inferred = await _until({
        'done',
        'error',
      }, timeout: const Duration(minutes: 8));
      expect(inferred['phase'], 'done', reason: '${inferred['error']}');
      final paths = inferred['paths'] as Map;
      var nonzero = 0;
      for (final name in _names) {
        final bytes = await File(paths[name] as String).readAsBytes();
        expect(bytes.length, 44 + 44100 * 4);
        for (var i = 44; i < bytes.length; i += 2) {
          if (bytes[i] != 0 || bytes[i + 1] != 0) nonzero++;
        }
      }
      expect(nonzero, greaterThan(0));
      return;
    }

    final invalid = await _fixture('invalid', valid: false);
    await expectLater(
      _stems.invokeMethod<void>('start', {'input': invalid.path}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INPUT')),
    );

    final silence = await _fixture('silence', valid: true, silence: true);
    await _stems.invokeMethod<void>('start', {'input': silence.path});
    final finished = await _until({
      'done',
      'error',
    }, timeout: const Duration(minutes: 8));
    expect(finished['phase'], 'done', reason: '${finished['error']}');
    final paths = finished['paths'] as Map;
    expect(paths.keys.toSet(), _names.toSet());
    for (final name in _names) {
      final output = File(paths[name] as String);
      expect(await output.exists(), isTrue);
      expect(await output.length(), 44 + 44100 * 4);
      expect((await output.openRead(0, 4).first), [82, 73, 70, 70]);
    }
    final afterSilence = await _status();
    debugPrint(
      'Stem QA after silence: available=${afterSilence['availableMemoryBytes']} threshold=${afterSilence['lowMemoryThresholdBytes']} bytes',
    );

    final tone = await _fixture('tone', valid: true);
    await _stems.invokeMethod<void>('start', {'input': tone.path});
    final inferred = await _until({
      'done',
      'error',
    }, timeout: const Duration(minutes: 8));
    expect(inferred['phase'], 'done', reason: '${inferred['error']}');
    final tonePaths = inferred['paths'] as Map;
    var audibleSamples = 0;
    for (final name in _names) {
      final output = File(tonePaths[name] as String);
      expect(await output.length(), 44 + 44100 * 4);
      final bytes = await output.readAsBytes();
      for (var i = 44; i < bytes.length; i += 2) {
        if (bytes[i] != 0 || bytes[i + 1] != 0) audibleSamples++;
      }
    }
    expect(audibleSamples, greaterThan(0));

    final cancelTone = await _fixture('cancel_tone', valid: true);
    await _stems.invokeMethod<void>('start', {'input': cancelTone.path});
    await Future<void>.delayed(const Duration(seconds: 2));
    final active = await _status();
    expect(
      active['phase'],
      'separating',
      reason: 'Cancelamento deve ocorrer durante trabalho nativo ativo.',
    );
    await _stems.invokeMethod<void>('cancel');
    final cancelled = await _until({
      'cancelled',
      'error',
      'done',
    }, timeout: const Duration(minutes: 2));
    expect(cancelled['phase'], 'cancelled');
    expect((cancelled['paths'] as Map).keys.toSet(), _names.toSet());
  });
}
