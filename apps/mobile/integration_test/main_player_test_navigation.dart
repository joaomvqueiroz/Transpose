import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reaches a main-player control through its current visible UI. Opening the
/// settings sheet and revealing transport never dispatch audio commands here.
Future<void> prepareMainPlayerControl(WidgetTester tester, String key) async {
  if (key.startsWith('visualTab')) {
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      final menu = find.byKey(const Key('visualPlayerMenu'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pump(const Duration(milliseconds: 400));
    }
    return;
  }
  final bool settingsControl =
      key.startsWith('visualPlayerPitch') ||
      key.startsWith('visualPlayerSpeed') ||
      key.startsWith('visualPlayerMark') ||
      key.startsWith('visualPlayerLoop') ||
      key == 'visualPlayerClearLoop' ||
      key == 'visualPlayerStudyTools' ||
      key.startsWith('visualPlayerTool_') ||
      key == 'visualPlayerAdvancedTools';
  final Finder sheet = find.byKey(const Key('visualPlayerSettingsSheet'));

  Future<void> navigate(String buttonKey) async {
    final Finder button = find.byKey(Key(buttonKey));
    await tester.ensureVisible(button);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 400));
  }

  if (settingsControl &&
      sheet.evaluate().isEmpty &&
      find.byKey(const Key('visualPlayerSettings')).evaluate().isNotEmpty) {
    await navigate('visualPlayerSettings');
  } else if (settingsControl &&
      sheet.evaluate().isEmpty &&
      find.byKey(Key(key)).evaluate().isEmpty &&
      find.byKey(const Key('visualMainAdjustments')).evaluate().isNotEmpty) {
    await navigate('visualMainAdjustments');
  } else if (settingsControl &&
      sheet.evaluate().isEmpty &&
      find.byKey(Key(key)).evaluate().isEmpty &&
      find
          .byKey(const Key('visualPlayerControlsToggle'))
          .evaluate()
          .isNotEmpty) {
    await navigate('visualPlayerControlsToggle');
  } else if (!settingsControl &&
      sheet.evaluate().isNotEmpty &&
      key != 'visualPlayerSettingsClose') {
    await navigate('visualPlayerSettingsClose');
  }
  if ((key.startsWith('visualPlayerTool_') ||
          key == 'visualPlayerAdvancedTools') &&
      find.byKey(Key(key)).evaluate().isEmpty) {
    await navigate('visualPlayerStudyTools');
  }
  if (<String>{
    'visualPlayerPlay',
    'visualPlayerBack10',
    'visualPlayerForward10',
    'visualPlayerFullscreen',
    'visualPlayerSeek',
  }.contains(key)) {
    final Finder surface = find.byKey(const Key('visualPlayerMediaSurface'));
    await tester.ensureVisible(surface);
    await tester.pump(const Duration(milliseconds: 100));
    // Touch away from the central native Play button so revealing our overlay
    // does not also select that button in the underlying browser.
    final Rect bounds = tester.getRect(surface);
    await tester.tapAt(bounds.topCenter + const Offset(0, 12));
    await tester.pump();
  }
}
