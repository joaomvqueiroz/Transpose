/// webview_flutter backend for iOS that renders with Gecko instead of WebKit.
///
/// iPhone WebKit plays YouTube through native HLS, whose audio never reaches
/// Web Audio, so Transpono's page-local pitch/EQ bridge hears silence. Gecko
/// plays the same page through MSE, where the bridge works as on Android.
///
/// The engine exists only in builds that embed the Transpono Gecko engine kit
/// (see .github/workflows/ios-gecko.yml). Elsewhere [GeckoEngine.isAvailable]
/// is false and callers keep using the platform WebView.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const MethodChannel _channel = MethodChannel('transpono/gecko_view');
const String _viewType = 'transpono/gecko_view';

/// Whether this app build runs Gecko.
abstract final class GeckoEngine {
  static bool _available = false;
  static bool _initialized = false;

  /// Resolve once at startup, before any web session is created.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on Object {
      _available = false;
    }
  }

  static bool get isAvailable => _available;

  /// For tests only.
  @visibleForTesting
  static void debugSetAvailable(bool value) {
    _initialized = true;
    _available = value;
  }
}

/// Exception raised when page JavaScript cannot run (no page context yet,
/// navigation in progress, or a script error).
class GeckoJavaScriptException implements Exception {
  GeckoJavaScriptException(this.message);
  final String message;
  @override
  String toString() => 'GeckoJavaScriptException: $message';
}

class GeckoWebViewController extends PlatformWebViewController {
  GeckoWebViewController({MethodChannel? channel})
    : _methods = channel ?? _channel,
      super.implementation(const PlatformWebViewControllerCreationParams()) {
    _ready = _create();
  }

  final MethodChannel _methods;
  late final Future<int> _ready;
  MethodChannel? _events;
  GeckoNavigationDelegate? _delegate;
  final Map<String, JavaScriptChannelParams> _javaScriptChannels = {};
  String? _url;
  bool _canGoBack = false;
  bool _disposed = false;

  /// Native session id, once created.
  Future<int> get sessionId => _ready;

  Future<int> _create() async {
    final int? id = await _methods.invokeMethod<int>('create');
    if (id == null) throw StateError('Gecko session was not created');
    final MethodChannel events = MethodChannel('transpono/gecko_view/$id');
    events.setMethodCallHandler(handleEvent);
    _events = events;
    return id;
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    final int id = await _ready;
    if (_disposed) return null;
    try {
      return await _methods.invokeMethod<T>(method, <String, Object?>{
        'id': id,
        ...?args,
      });
    } on PlatformException catch (error) {
      if (error.code == 'JS_ERROR' || error.code == 'NO_CONTEXT') {
        throw GeckoJavaScriptException(error.message ?? error.code);
      }
      rethrow;
    }
  }

  /// Native → Dart events. Public for unit tests.
  @visibleForTesting
  Future<Object?> handleEvent(MethodCall call) async {
    final Map<String, Object?> args =
        (call.arguments as Map<Object?, Object?>?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final GeckoNavigationDelegate? delegate = _delegate;
    switch (call.method) {
      case 'pageStart':
        _url = args['url'] as String? ?? _url;
        delegate?._onPageStarted?.call(_url ?? '');
      case 'pageStop':
        delegate?._onPageFinished?.call(_url ?? '');
      case 'progress':
        delegate?._onProgress?.call((args['value'] as num?)?.toInt() ?? 0);
      case 'location':
        _url = args['url'] as String? ?? _url;
        delegate?._onUrlChange?.call(UrlChange(url: _url));
      case 'canGoBack':
        _canGoBack = args['value'] == true;
      case 'loadError':
        delegate?._onWebResourceError?.call(
          WebResourceError(
            errorCode: (args['code'] as num?)?.toInt() ?? -1,
            description: args['description'] as String? ?? '',
            isForMainFrame: true,
            url: args['url'] as String? ?? _url,
          ),
        );
      case 'loadRequest':
        final NavigationRequestCallback? decide = delegate?._onNavigationRequest;
        if (decide == null) return true;
        final NavigationDecision decision = await decide(
          NavigationRequest(
            url: args['url'] as String? ?? '',
            isMainFrame: args['isMainFrame'] != false,
          ),
        );
        return decision == NavigationDecision.navigate;
      case 'channel':
        final JavaScriptChannelParams? params =
            _javaScriptChannels[args['name']];
        params?.onMessageReceived(
          JavaScriptMessage(message: args['message'] as String? ?? ''),
        );
    }
    return null;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) =>
      _call<void>('load', <String, Object?>{'url': params.uri.toString()});

  @override
  Future<String?> currentUrl() async =>
      await _call<String>('currentUrl') ?? _url;

  @override
  Future<bool> canGoBack() async => await _call<bool>('canGoBack') ?? _canGoBack;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goBack() => _call<void>('goBack');

  @override
  Future<void> goForward() async {}

  @override
  Future<void> reload() => _call<void>('reload');

  @override
  Future<void> runJavaScript(String javaScript) async {
    await _call<Object?>('evaluate', <String, Object?>{'code': javaScript});
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final Object? value = await _call<Object?>('evaluate', <String, Object?>{
      'code': javaScript,
    });
    return value ?? 'null';
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _delegate = handler is GeckoNavigationDelegate ? handler : null;
    await _call<void>('setDecisions', <String, Object?>{
      'enabled': _delegate?._onNavigationRequest != null,
    });
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    _javaScriptChannels[params.name] = params;
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    _javaScriptChannels.remove(javaScriptChannelName);
  }

  @override
  Future<void> setBackgroundColor(Color color) => _call<void>(
    'setBackgroundColor',
    <String, Object?>{'color': color.toARGB32()},
  );

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {}

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {}

  /// Pause/resume rendering and timers when the view is hidden.
  Future<void> setActive(bool active) =>
      _call<void>('setActive', <String, Object?>{'active': active});

  Future<void> dispose() async {
    if (_disposed) return;
    final int id = await _ready;
    _disposed = true;
    _events?.setMethodCallHandler(null);
    await _methods.invokeMethod<void>('dispose', <String, Object?>{'id': id});
  }
}

class GeckoNavigationDelegate extends PlatformNavigationDelegate {
  GeckoNavigationDelegate()
    : super.implementation(const PlatformNavigationDelegateCreationParams());

  NavigationRequestCallback? _onNavigationRequest;
  PageEventCallback? _onPageStarted;
  PageEventCallback? _onPageFinished;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  UrlChangeCallback? _onUrlChange;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async => _onNavigationRequest = onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async =>
      _onPageStarted = onPageStarted;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      _onPageFinished = onPageFinished;

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async =>
      _onProgress = onProgress;

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async => _onWebResourceError = onWebResourceError;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async =>
      _onUrlChange = onUrlChange;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}
}

class GeckoWebViewWidget extends PlatformWebViewWidget {
  GeckoWebViewWidget(GeckoWebViewController controller, {Key? key})
    : super.implementation(
        PlatformWebViewWidgetCreationParams(key: key, controller: controller),
      );

  @override
  Widget build(BuildContext context) {
    final GeckoWebViewController controller =
        params.controller as GeckoWebViewController;
    return FutureBuilder<int>(
      future: controller.sessionId,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        final int? id = snapshot.data;
        if (id == null) return const SizedBox.expand();
        return UiKitView(
          key: params.key,
          viewType: _viewType,
          // Gecko reads touches through its own UIKit gesture handling; let
          // the page have every pointer at once (as a browser view should)
          // instead of only those no Flutter recognizer claimed.
          gestureRecognizers: params.gestureRecognizers.isNotEmpty
              ? params.gestureRecognizers
              : <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                },
          creationParams: <String, Object?>{'id': id},
          creationParamsCodec: const StandardMessageCodec(),
        );
      },
    );
  }
}
