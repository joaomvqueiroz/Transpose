import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// QA-only microphone lifecycle smoke. Captured PCM stays inside Android RAM.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('transpose/qa_band_acoustic');
  testWidgets('QA acoustic capture starts and cancels without exporting PCM', (
    tester,
  ) async {
    final initial = await channel.invokeMapMethod<String, dynamic>('status');
    expect(initial?['phase'], 'idle');
    await channel.invokeMethod<void>('start', {
      'durationMs': 10000,
      'beatIntervalMs': 500,
    });
    final running = await channel.invokeMapMethod<String, dynamic>('status');
    expect(running?['busy'], true);
    await channel.invokeMethod<void>('cancel');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    Map<String, dynamic>? ended;
    do {
      ended = await channel.invokeMapMethod<String, dynamic>('status');
      if (ended?['busy'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } while (DateTime.now().isBefore(deadline));
    expect(ended?['busy'], false);
    expect(ended?['phase'], 'cancelled');
    expect(ended?.containsKey('pcm'), false);
    expect(ended?.containsKey('samples'), false);
  });
}
