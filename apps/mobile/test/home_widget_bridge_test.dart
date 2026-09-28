import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/home_widget_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'home widget receives the pending action and a real player snapshot',
    () async {
      const channel = MethodChannel('transpose/home_widgets');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'takeAction') return 'tuner';
        return null;
      });
      final actions = <String>[];
      final bridge = HomeWidgetBridge(onAction: actions.add);
      await bridge.initialize();
      expect(actions, ['tuner']);

      final snapshot = <String, Object?>{
        'active': true,
        'title': 'É Ele',
        'playing': false,
        'position': '1:25',
      };
      bridge.schedule(snapshot);
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'update').length, 1);
      expect(calls.last.arguments, snapshot);

      bridge.schedule(snapshot);
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'update').length, 1);
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets('widget updates stay ordered and finish with the newest state', (
    tester,
  ) async {
    const channel = MethodChannel('transpose/home_widgets');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final firstUpdate = Completer<void>();
    final updates = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') {
        updates.add(call.arguments as Map<Object?, Object?>);
        if (updates.length == 1) await firstUpdate.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HomeWidgetBridge(onAction: (_) {});
    addTearDown(bridge.dispose);
    await bridge.initialize();

    bridge.schedule({'title': 'Antiga'});
    await tester.pump();
    bridge.schedule({'title': 'Atual'});
    await tester.pump();
    expect(updates.map((state) => state['title']), ['Antiga']);

    firstUpdate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(updates.map((state) => state['title']), ['Antiga', 'Atual']);
  });

  testWidgets('Android update failure waits for a new snapshot to retry', (
    tester,
  ) async {
    const channel = MethodChannel('transpose/home_widgets');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') {
        attempts++;
        if (attempts == 1) throw PlatformException(code: 'temporary');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HomeWidgetBridge(onAction: (_) {});
    addTearDown(bridge.dispose);
    await bridge.initialize();
    bridge.schedule({'title': 'Primeira'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(attempts, 1);
    bridge.schedule({'title': 'Segunda'});
    await tester.pump();
    expect(attempts, 2);
  });
}
