import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/main_player_controller.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

/// Runs only in the isolated QA package with the app's generated sample audio.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ordinary Android playback pauses across background and resume', (
    tester,
  ) async {
    final player = MainPlayerController();
    final completed = <String>[];
    var passed = false;
    void report(String step) {
      completed.add(step);
      binding.reportData = {
        'passed': passed,
        'completed': completed,
        'playing': player.playing,
        'pitch': player.pitch,
        'speed': player.speed,
        'positionMs': player.position.inMilliseconds,
      };
      debugPrint('TRANSPONO_BACKGROUND ${jsonEncode(binding.reportData)}');
    }

    Future<void> waitFor(bool Function() condition, String label) async {
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('$label timed out');
    }

    try {
      expect(Platform.isAndroid, isTrue);
      await tester.pumpWidget(StudioVisualApp(playerController: player));
      await player.loadSample();
      await waitFor(() => player.loaded && !player.busy, 'sample');
      expect(
        player.local.locator,
        contains('/com.example.transpose_mobile.qa/'),
      );
      await player.changePitch(2);
      await player.changeSpeed(.8);
      await waitFor(
        () => !player.busy && player.pitch == 2 && player.speed == .8,
        'confirmed settings',
      );
      report('sample-and-settings-confirmed');

      await player.playPause();
      await waitFor(
        () => player.playing && player.position.inMilliseconds > 200,
        'playing output',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await waitFor(() => !player.playing, 'background pause');
      final paused = player.position.inMilliseconds;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await tester.pump();
      expect((player.position.inMilliseconds - paused).abs(), lessThan(150));
      report('paused-and-position-held');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await tester.pump();
      expect(player.playing, isFalse);
      expect(player.pitch, 2);
      expect(player.speed, .8);
      report('resumed-without-autoplay');
      passed = true;
      report('passed');
    } finally {
      await player.pause();
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
    }
  }, skip: !Platform.isAndroid);
}
