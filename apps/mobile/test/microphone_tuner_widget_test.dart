import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/microphone_tuner.dart';

void main() {
  testWidgets('afinador mostra alvo e permite selecionar uma corda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MicrophoneTunerTool()),
        ),
      ),
    );
    expect(find.byKey(const Key('chromaticTunerCard')), findsOneWidget);
    expect(find.byKey(const Key('tunerMicrophoneToggle')), findsOneWidget);
    expect(find.text('E2'), findsWidgets);

    await tester.tap(find.byKey(const Key('tunerStringA2')));
    await tester.pump();
    expect(find.text('A2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
