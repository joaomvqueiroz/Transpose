import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:transpose_mobile/microphone_tuner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('as seis referências de piano tocam como assets locais', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MicrophoneTunerTool())),
    );
    for (final note in ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']) {
      final asset = await rootBundle.load('assets/piano/$note.wav');
      expect(asset.lengthInBytes, greaterThan(1000));
      await tester.tap(find.byKey(Key('tunerString$note')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('tunerMicrophoneError')), findsNothing);
      expect(find.text('Nota de referência · piano'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
