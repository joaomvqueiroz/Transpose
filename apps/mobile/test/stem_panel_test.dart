import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/stem_panel.dart';

void main() {
  const channel = MethodChannel('transpose/stems');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('closing during initialization leaves no polling timer', (
    tester,
  ) async {
    final available = Completer<bool>();
    var statusCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'available') return available.future;
          if (call.method == 'status') statusCalls++;
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(home: StemPanel(onBeforePreview: () async {})),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    available.complete(true);
    await tester.pump(const Duration(seconds: 2));
    expect(statusCalls, 0);
  });

  testWidgets(
    'preview cannot start after its pause callback outlives the panel',
    (tester) async {
      final paused = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'available') return true;
            if (call.method == 'status') {
              return {
                'phase': 'done',
                'progress': 100,
                'downloaded': 0,
                'modelReady': true,
                'paths': {'drums': '/unplayed.wav'},
              };
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StemPanel(onBeforePreview: () => paused.future)),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Ouvir Bateria'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      paused.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
