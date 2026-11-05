import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('transpono/gecko_view');
  final List<MethodCall> calls = <MethodCall>[];
  Object? Function(MethodCall call)? reply;

  setUp(() {
    calls.clear();
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'create') return 7;
          if (call.method == 'isAvailable') return true;
          return reply?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('routes calls to the native session id', () async {
    final GeckoWebViewController controller = GeckoWebViewController();
    expect(await controller.sessionId, 7);
    await controller.loadRequest(
      LoadRequestParams(uri: Uri.parse('https://m.youtube.com/')),
    );
    final MethodCall load = calls.lastWhere((c) => c.method == 'load');
    expect(load.arguments, <String, Object?>{
      'id': 7,
      'url': 'https://m.youtube.com/',
    });
  });

  test('returns evaluate results like WKWebView', () async {
    reply = (MethodCall call) => call.method == 'evaluate' ? '{"a":1}' : null;
    final GeckoWebViewController controller = GeckoWebViewController();
    expect(await controller.runJavaScriptReturningResult('x'), '{"a":1}');
    reply = (_) => null;
    expect(await controller.runJavaScriptReturningResult('y'), 'null');
  });

  test('maps missing page context to an exception', () async {
    reply = (MethodCall call) => throw PlatformException(
      code: 'NO_CONTEXT',
      message: 'NO_CONTEXT: sem página',
    );
    final GeckoWebViewController controller = GeckoWebViewController();
    await expectLater(
      controller.runJavaScript('1'),
      throwsA(isA<GeckoJavaScriptException>()),
    );
  });

  test('forwards navigation events and decisions', () async {
    final GeckoWebViewController controller = GeckoWebViewController();
    final GeckoNavigationDelegate delegate = GeckoNavigationDelegate();
    final List<String> started = <String>[];
    final List<int> progress = <int>[];
    final List<String> finished = <String>[];
    await delegate.setOnPageStarted(started.add);
    await delegate.setOnPageFinished(finished.add);
    await delegate.setOnProgress(progress.add);
    await delegate.setOnNavigationRequest(
      (NavigationRequest request) => request.url.contains('youtube')
          ? NavigationDecision.navigate
          : NavigationDecision.prevent,
    );
    await controller.setPlatformNavigationDelegate(delegate);
    expect(
      calls.lastWhere((c) => c.method == 'setDecisions').arguments,
      <String, Object?>{'id': 7, 'enabled': true},
    );

    await controller.handleEvent(
      const MethodCall('pageStart', <String, Object?>{'url': 'https://m.youtube.com/'}),
    );
    await controller.handleEvent(
      const MethodCall('progress', <String, Object?>{'value': 60}),
    );
    await controller.handleEvent(const MethodCall('pageStop'));
    expect(started, <String>['https://m.youtube.com/']);
    expect(progress, <int>[60]);
    expect(finished, <String>['https://m.youtube.com/']);

    expect(
      await controller.handleEvent(
        const MethodCall('loadRequest', <String, Object?>{
          'url': 'https://m.youtube.com/watch?v=x',
          'isMainFrame': true,
        }),
      ),
      true,
    );
    expect(
      await controller.handleEvent(
        const MethodCall('loadRequest', <String, Object?>{
          'url': 'https://example.com/',
          'isMainFrame': true,
        }),
      ),
      false,
    );
    expect(await controller.currentUrl(), 'https://m.youtube.com/');
  });

  test('is unavailable off iOS', () async {
    await GeckoEngine.ensureInitialized();
    expect(GeckoEngine.isAvailable, isFalse);
  });
}
