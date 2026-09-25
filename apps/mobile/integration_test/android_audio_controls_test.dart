import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android audio controls use the loaded player', (tester) async {
    await tester.pumpWidget(const app.TransposeApp());
    await tester.tap(find.byKey(const Key('sampleButton')));
    await _waitFor(
      tester,
      () => find.byKey(const Key('pitchSlider')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('speedSlider')), findsOneWidget);

    final Slider pitch = tester.widget<Slider>(
      find.byKey(const Key('pitchSlider')),
    );
    pitch.onChanged!(-2);
    pitch.onChangeEnd!(-2);
    await _waitFor(
      tester,
      () => find.text('Tom: -2 semitons').evaluate().isNotEmpty,
    );

    final Slider speed = tester.widget<Slider>(
      find.byKey(const Key('speedSlider')),
    );
    speed.onChanged!(0.75);
    speed.onChangeEnd!(0.75);
    await _waitFor(
      tester,
      () => find.text('Velocidade: 0.75×').evaluate().isNotEmpty,
    );

    await tester.ensureVisible(find.byKey(const Key('playPauseButton')));
    await tester.tap(find.byKey(const Key('playPauseButton')));
    await _waitFor(tester, () => find.text('Pausar').evaluate().isNotEmpty);
    final Slider livePitch = tester.widget<Slider>(
      find.byKey(const Key('pitchSlider')),
    );
    livePitch.onChanged!(3);
    livePitch.onChangeEnd!(3);
    await _waitFor(
      tester,
      () => find.text('Tom: +3 semitons').evaluate().isNotEmpty,
    );
    expect(find.text('Pausar'), findsOneWidget);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text('00:00'), findsWidgets);

    await tester.tap(find.byKey(const Key('playPauseButton')));
    await _waitFor(tester, () => find.text('Reproduzir').evaluate().isNotEmpty);
  }, skip: !Platform.isAndroid);

  testWidgets(
    'Android background pauses audio and never auto-resumes',
    (tester) async {
      await tester.pumpWidget(const app.TransposeApp());
      await tester.tap(find.byKey(const Key('sampleButton')));
      await _waitFor(
        tester,
        () => find.byKey(const Key('pitchSlider')).evaluate().isNotEmpty,
      );

      final Slider pitch = tester.widget<Slider>(
        find.byKey(const Key('pitchSlider')),
      );
      pitch.onChanged!(-2);
      pitch.onChangeEnd!(-2);
      await _waitFor(
        tester,
        () => find.text('Tom: -2 semitons').evaluate().isNotEmpty,
      );
      final Slider speed = tester.widget<Slider>(
        find.byKey(const Key('speedSlider')),
      );
      speed.onChanged!(0.75);
      speed.onChangeEnd!(0.75);
      await _waitFor(
        tester,
        () => find.text('Velocidade: 0.75×').evaluate().isNotEmpty,
      );

      await _waitFor(
        tester,
        () =>
            tester
                .widget<TextButton>(find.byKey(const Key('markAButton')))
                .onPressed !=
            null,
      );
      tester
          .widget<TextButton>(find.byKey(const Key('markAButton')))
          .onPressed!();
      final Slider seek = tester.widget<Slider>(
        find.byKey(const Key('seekSlider')),
      );
      seek.onChanged!(2000);
      seek.onChangeEnd!(2000);
      await _waitFor(tester, () => find.text('00:02').evaluate().isNotEmpty);
      tester
          .widget<TextButton>(find.byKey(const Key('markBButton')))
          .onPressed!();
      await _waitFor(
        tester,
        () => find.text('Loop A/B: 00:00 → 00:02').evaluate().isNotEmpty,
      );
      tester
          .widget<FilledButton>(find.byKey(const Key('loopToggleButton')))
          .onPressed!();
      await _waitFor(
        tester,
        () => find.text('Loop ligado').evaluate().isNotEmpty,
      );

      await _waitFor(
        tester,
        () =>
            tester
                .widget<FilledButton>(find.byKey(const Key('playPauseButton')))
                .onPressed !=
            null,
      );
      await tester.ensureVisible(find.byKey(const Key('playPauseButton')));
      await tester.tap(find.byKey(const Key('playPauseButton')));
      await _waitFor(tester, () => find.text('Pausar').evaluate().isNotEmpty);
      final double beforeBackground = tester
          .widget<Slider>(find.byKey(const Key('seekSlider')))
          .value;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _waitFor(
        tester,
        () => find.text('Reproduzir').evaluate().isNotEmpty,
      );
      final double afterTenSeconds = tester
          .widget<Slider>(find.byKey(const Key('seekSlider')))
          .value;
      expect(
        (afterTenSeconds - beforeBackground).abs(),
        lessThanOrEqualTo(400),
      );
      expect(find.text('Tom: -2 semitons'), findsOneWidget);
      expect(find.text('Velocidade: 0.75×'), findsOneWidget);
      expect(find.text('Loop ligado'), findsOneWidget);
      expect(find.text('Loop A/B: 00:00 → 00:02'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Reproduzir'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (int attempt = 0; attempt < 60; ++attempt) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Android audio control did not reach the expected state.');
}
