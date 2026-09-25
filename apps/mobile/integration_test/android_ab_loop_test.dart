import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/media/native_audio_media_loader.dart';
import 'package:transpose_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android A/B repeat stays on the same Media3 output', (_) async {
    final ByteData fixture = await rootBundle.load('assets/qa_tone.wav');
    final Directory work = await Directory.systemTemp.createTemp('ab_loop_');
    final File input = File('${work.path}/input.wav');
    await input.writeAsBytes(
      fixture.buffer.asUint8List(fixture.offsetInBytes, fixture.lengthInBytes),
    );
    final NativeAudioMediaLoader loader = NativeAudioMediaLoader();
    NativeAudioLoadedMedia? media;
    try {
      await loader.load(
        LocalFileSource.fromPath(
          id: 'loop-fixture',
          displayName: 'input.wav',
          path: input.path,
        ),
      );
      media = loader.currentAudio!;
      final LoopRange range = LoopRange(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
      );
      await media.setLoop(range);
      expect(media.loopEnabled, isTrue);
      expect(media.duration, const Duration(seconds: 12));
      await media.play();
      for (int attempt = 0; attempt < 75 && media.loopCount < 2; ++attempt) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      debugPrint(
        'A/B native: loops=${media.loopCount}, position=${media.position}',
      );
      expect(media.loopCount, greaterThanOrEqualTo(2));
      expect(
        media.position >= range.start && media.position <= range.end,
        isTrue,
      );
      await media.setParameters(semitones: -2, speed: 0.75);
      expect(media.requestedSemitones, -2);
      expect(media.requestedSpeed, 0.75);
      await media.seek(const Duration(seconds: 8));
      expect(media.loopEnabled, isFalse);
      expect(media.loopRange, range);
      await media.pause();
    } finally {
      await media?.release();
      await work.delete(recursive: true);
    }
  }, skip: !Platform.isAndroid);

  testWidgets('Android A/B controls retain markers after seek outside', (
    tester,
  ) async {
    await tester.pumpWidget(const app.TransposeApp());
    await tester.tap(find.byKey(const Key('sampleButton')));
    await _waitFor(
      tester,
      () => find.byKey(const Key('markAButton')).evaluate().isNotEmpty,
    );
    await _mark(tester, 'markAButton');
    final Slider seek = tester.widget<Slider>(
      find.byKey(const Key('seekSlider')),
    );
    seek.onChanged!(2000);
    seek.onChangeEnd!(2000);
    await _waitFor(tester, () => find.text('00:02').evaluate().isNotEmpty);
    await _mark(tester, 'markBButton');
    await tester.pump();
    expect(find.text('Loop A/B: 00:00 → 00:02'), findsOneWidget);
    tester
        .widget<FilledButton>(find.byKey(const Key('loopToggleButton')))
        .onPressed!();
    await _waitFor(
      tester,
      () => find.text('Loop ligado').evaluate().isNotEmpty,
    );
    final Slider outside = tester.widget<Slider>(
      find.byKey(const Key('seekSlider')),
    );
    outside.onChanged!(8000);
    outside.onChangeEnd!(8000);
    await _waitFor(
      tester,
      () => find.text('Ativar loop').evaluate().isNotEmpty,
    );
    expect(find.text('Loop A/B: 00:00 → 00:02'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isAndroid);

  testWidgets('Android live A/B edits keep UI and native loop in sync', (
    tester,
  ) async {
    await tester.pumpWidget(const app.TransposeApp());
    await tester.tap(find.byKey(const Key('sampleButton')));
    await _waitFor(
      tester,
      () => find.byKey(const Key('markAButton')).evaluate().isNotEmpty,
    );
    await _mark(tester, 'markAButton');
    await _waitFor(
      tester,
      () => find.text('Loop A/B: 00:00 → --:--').evaluate().isNotEmpty,
    );
    await _seek(tester, 3000);
    await _mark(tester, 'markBButton');
    await _waitFor(
      tester,
      () => find.text('Loop A/B: 00:00 → 00:03').evaluate().isNotEmpty,
    );
    tester
        .widget<FilledButton>(find.byKey(const Key('loopToggleButton')))
        .onPressed!();
    await _waitFor(
      tester,
      () => find.text('Loop ligado').evaluate().isNotEmpty,
    );

    await _seek(tester, 1000);
    await _mark(tester, 'markAButton');
    await _waitFor(
      tester,
      () => find.text('Loop A/B: 00:01 → 00:03').evaluate().isNotEmpty,
    );
    expect(find.text('Loop ligado'), findsOneWidget);

    await _seek(tester, 2000);
    await _mark(tester, 'markBButton');
    await _waitFor(
      tester,
      () => find.text('Loop A/B: 00:01 → 00:02').evaluate().isNotEmpty,
    );
    expect(find.text('Loop ligado'), findsOneWidget);

    await _seek(tester, 1000);
    await _mark(tester, 'markBButton');
    await _waitFor(
      tester,
      () => find
          .textContaining('pelo menos 1 ms depois de A')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Loop A/B: 00:01 → 00:02'), findsOneWidget);
    expect(find.text('Loop ligado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isAndroid);
}

Future<void> _seek(WidgetTester tester, double milliseconds) async {
  await _waitFor(tester, () {
    final Slider slider = tester.widget<Slider>(
      find.byKey(const Key('seekSlider')),
    );
    return slider.onChangeEnd != null;
  });
  final Slider slider = tester.widget<Slider>(
    find.byKey(const Key('seekSlider')),
  );
  slider.onChanged!(milliseconds);
  slider.onChangeEnd!(milliseconds);
  await _waitFor(
    tester,
    () => find.text(_displaySeconds(milliseconds)).evaluate().isNotEmpty,
  );
}

Future<void> _mark(WidgetTester tester, String key) async {
  await _waitFor(tester, () {
    final TextButton button = tester.widget<TextButton>(find.byKey(Key(key)));
    return button.onPressed != null;
  });
  tester.widget<TextButton>(find.byKey(Key(key))).onPressed!();
}

String _displaySeconds(double milliseconds) =>
    '00:${(milliseconds ~/ 1000).toString().padLeft(2, '0')}';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (int attempt = 0; attempt < 60; ++attempt) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('A/B UI did not reach its expected state.');
}
