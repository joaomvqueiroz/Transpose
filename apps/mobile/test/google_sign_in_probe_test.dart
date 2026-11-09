import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transpose_mobile/google_sign_in_probe.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => GeckoEngine.debugSetAvailable(false));

  test('the sign-in stays on Google and YouTube pages', () {
    bool ok(String url) => isGoogleSignInProbeUri(Uri.parse(url));
    expect(ok(GoogleSignInProbePage.start.toString()), isTrue);
    expect(ok('https://accounts.google.com/v3/signin/challenge/pwd'), isTrue);
    expect(ok('https://accounts.youtube.com/accounts/SetSID'), isTrue);
    expect(ok('https://www.google.pt/accounts/SetSID'), isTrue);
    expect(ok('https://m.youtube.com/'), isTrue);
    expect(ok('https://music.youtube.com/'), isTrue);
    expect(ok('http://accounts.google.com/'), isFalse);
    expect(ok('https://evil.example/accounts.google.com'), isFalse);
    expect(ok('https://google.com.evil.example/'), isFalse);
  });

  test('remembers that the session was handed over', () async {
    expect(await GoogleSession.imported(), isFalse);
    await GoogleSession.markImported();
    expect(await GoogleSession.imported(), isTrue);
  });

  Future<void> openGate(WidgetTester tester, GoogleSignInGate gate) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => gate.beforeOpening(context),
            child: const Text('YouTube'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('asks once per run, only with Gecko and no session yet', (
    tester,
  ) async {
    final gate = GoogleSignInGate();
    await openGate(tester, gate);
    expect(find.byKey(const Key('googleSignInAsk')), findsNothing);

    GeckoEngine.debugSetAvailable(true);
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('googleSignInAsk')), findsOneWidget);
    await tester.tap(find.byKey(const Key('googleSignInLater')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('googleSignInAsk')), findsNothing);

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('googleSignInAsk')), findsNothing);
  });

  testWidgets('does not ask once the session is in Gecko', (tester) async {
    GeckoEngine.debugSetAvailable(true);
    await GoogleSession.markImported();
    await openGate(tester, GoogleSignInGate());
    expect(find.byKey(const Key('googleSignInAsk')), findsNothing);
  });
}
