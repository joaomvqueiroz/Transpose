import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/ambient_rhythm_trial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('transpose/qa_phone_rhythm_features');

  testWidgets('personal rhythm trial shows an estimate without claiming sync', (
    tester,
  ) async {
    var cancelled = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'start':
        case 'finish':
          return null;
        case 'cancel':
          cancelled = true;
          return null;
        case 'status':
          return {
            'busy': false,
            'phase': 'done',
            'quality': 'availableForReview',
            'routeChanged': false,
            'featureCount': 1000,
          };
        case 'readFeatures':
          final offset = (call.arguments as Map)['offset'] as int;
          return {
            'offset': offset,
            'total': 1000,
            'windowMs': 10,
            'features': [
              for (var i = offset; i < offset + 500; i++)
                {'novelty': i % 50 == 0 ? (i % 200 == 0 ? 1.0 : .3) : 0.0},
            ],
          };
      }
      throw StateError('Unexpected method ${call.method}');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AmbientRhythmTrial(requestPermission: () async => true),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('measureAmbientRhythm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('BPM ·'), findsWidgets);
    expect(find.textContaining('não sincronizada com o vídeo'), findsOneWidget);
    expect(cancelled, isTrue);
  });
}
