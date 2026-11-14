import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/source_picker.dart';

Widget _app() => MaterialApp(
  home: TransponoSourcePicker(
    studioBuilder: (key, query, factory, home) =>
        Text('studio:${home?.host ?? 'spotify'}', key: key),
  ),
);

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets('first launch shows the start screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.textContaining('studio:'), findsNothing);
  });

  testWidgets('the app opens straight in the last source used', (tester) async {
    await SharedPreferencesAsync().setString(
      'transpono.lastSource',
      ListeningSource.soundCloud.name,
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('studio:m.soundcloud.com'), findsOneWidget);
  });

  testWidgets('choosing a source remembers it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('SoundCloud'));
    await tester.pumpAndSettle();
    expect(find.text('studio:m.soundcloud.com'), findsOneWidget);
    expect(
      await SharedPreferencesAsync().getString('transpono.lastSource'),
      'soundCloud',
    );
  });
}
