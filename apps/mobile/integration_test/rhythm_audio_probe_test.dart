import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/rhythm_map.dart';
import 'package:transpose_mobile/study_tools.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('synthetic rhythm preview plays without modifying source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Rhythm audio QA'))),
    );
    final source = buildMetronomeWav(
      bpm: 120,
      beatsPerBar: 3,
      bars: 8,
      sampleRate: 16000,
    );
    final original = Uint8List.fromList(source);
    final map = analyzeRhythm(source);
    expect(map.sections, isNotEmpty);
    expect(map.sections.first.beatsPerBar, 3);
    final preview = mixRhythmPreview((source, map.sections));
    expect(source, original);
    expect(preview.length, source.length);

    final directory = await Directory.systemTemp.createTemp(
      'transpono-rhythm-qa-',
    );
    final file = File('${directory.path}/synthetic-preview.wav');
    VideoPlayerController? player;
    try {
      await file.writeAsBytes(preview, flush: true);
      player = VideoPlayerController.file(file);
      await player.initialize();
      expect(player.value.duration, greaterThan(const Duration(seconds: 10)));
      await player.setLooping(false);
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await tester.pump();
      expect(player.value.hasError, isFalse);
      expect(player.value.position, greaterThan(Duration.zero));
      binding.reportData = {
        'passed': true,
        'tempoBpm': map.sections.first.bpm,
        'beatsPerBar': map.sections.first.beatsPerBar,
        'positionMs': player.value.position.inMilliseconds,
        'scope': 'Synthetic WAV decoding/playback only; no acoustic alignment measurement',
      };
      debugPrint('TRANSPONO_RHYTHM ${jsonEncode(binding.reportData)}');
    } finally {
      await player?.dispose();
      await file.delete();
      await directory.delete();
    }
  });

  testWidgets('approved preview uses main transport for seek pitch and speed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Main rhythm QA'))),
    );
    final source = buildMetronomeWav(
      bpm: 120,
      beatsPerBar: 3,
      bars: 8,
      sampleRate: 16000,
    );
    final map = analyzeRhythm(source);
    final preview = mixRhythmPreview((source, map.sections));
    final player = MainPlayerController();
    File? generated;
    final states = <Map<String, Object?>>[];
    const native = MethodChannel('transpose/native_audio_player');
    Future<void> record(String stage) async {
      final status = await native.invokeMapMethod<Object?, Object?>('snapshot');
      states.add({
        'stage': stage,
        'positionMs': player.position.inMilliseconds,
        'playing': player.playing,
        'nativeReady': status?['ready'],
        'nativePlaying': status?['playing'],
        'nativePositionMs': status?['positionMs'],
        'message': player.message,
      });
    }
    try {
      await player.loadApprovedRhythmPreview(preview);
      await record('loaded');
      expect(player.isRhythmPreview, isTrue);
      expect(player.playing, isTrue);
      expect(player.canPitch, isTrue);
      expect(player.snapshot('temporary'), isNull);
      generated = File.fromUri(Uri.parse(player.local.locator!));
      expect(await generated.exists(), isTrue);
      await player.seek(const Duration(seconds: 3));
      await record('seek');
      await player.changePitch(2);
      await record('pitch');
      await player.changeSpeed(.75);
      await record('speed');
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
        await record('poll${i + 1}');
        if (player.position > const Duration(seconds: 3) &&
            states.last['nativePlaying'] == true) {
          break;
        }
      }
      debugPrint('TRANSPONO_RHYTHM_STATES ${jsonEncode(states)}');
      expect(player.position, greaterThan(const Duration(seconds: 3)));
      expect(states.last['nativePlaying'], isTrue);
      expect(player.pitch, 2);
      expect(player.speed, .75);
      await player.stopRhythmPreview();
      expect(player.playing, isFalse);
      binding.reportData = {
        ...?binding.reportData,
        'mainTransport': {
          'passed': true,
          'positionMs': player.position.inMilliseconds,
          'pitch': player.pitch,
          'speed': player.speed,
          'snapshotExcluded': player.snapshot('temporary') == null,
          'states': states,
        },
      };
      debugPrint('TRANSPONO_RHYTHM_MAIN ${jsonEncode(binding.reportData)}');
    } finally {
      await player.local.close();
      if (generated != null) expect(await generated.exists(), isFalse);
      player.dispose();
    }
  });
}
