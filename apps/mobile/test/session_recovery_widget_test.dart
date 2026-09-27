import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/studio_visual_app.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('player has no session recovery or sidebar controls', (
    tester,
  ) async {
    await tester.pumpWidget(const StudioVisualApp());
    await tester.tap(find.byKey(const Key('visualMainAdjustments')));
    await tester.pump();
    expect(find.byKey(const Key('recoveryRestoreFromPlayer')), findsNothing);
    expect(find.byKey(const Key('recoveryRestoreFromMenu')), findsNothing);
    expect(find.byKey(const Key('visualSidebarClose')), findsNothing);
    expect(find.text('Retomar última sessão'), findsNothing);
  });
}
