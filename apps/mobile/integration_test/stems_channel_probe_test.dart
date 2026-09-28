import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _stems = MethodChannel('transpose/stems');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('six-stem channel rejects unsafe inputs without inference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Stem QA'))),
    );
    expect(await _stems.invokeMethod<bool>('available'), isTrue);
    final before = await _stems.invokeMapMethod<String, Object?>('status');
    expect(before, isNotNull);
    expect(before!['phase'], isNot('separating'));
    expect(before['modelReady'], isA<bool>());
    await expectLater(
      _stems.invokeMethod<void>('start', {
        'input': '/sdcard/Music/unowned.wav',
      }),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INPUT')),
    );
    await _stems.invokeMethod<void>('cancel');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final after = await _stems.invokeMapMethod<String, Object?>('status');
    expect(after?['phase'], isNot('separating'));
  });
}
