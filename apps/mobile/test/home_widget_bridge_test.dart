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
}
