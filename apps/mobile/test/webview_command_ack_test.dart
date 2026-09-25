import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/youtube_browser.dart';
import 'package:transpose_mobile/web_media_command.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  late _Browser browser;
  late WebViewYouTubeSession session;
  setUp(() {
    browser = _Browser();
    session = WebViewYouTubeSession(controller: browser);
  });
  tearDown(() => session.dispose());

  test(
    'a pending periodic poll cannot suppress a command acknowledgement',
    () async {
      final back = Completer<bool>();
      browser.backGate = back;
      browser.pollState = _state(1, speed: 1);
      final polling = session.refresh();
      await Future<void>.delayed(Duration.zero);
      browser.commandState = _state(3, speed: .65);
      await session.command('speed', .65);
      expect(session.media.speed, .65);
      back.complete(false);
      await polling;
      expect(
        session.media.speed,
        .65,
        reason: 'Old poll must not roll back ACK',
      );
    },
  );

  test('command waits for asynchronous Play before exposing playing', () async {
    final reply = Completer<Object>();
    browser.replyGate = reply;
    var finished = false;
    final playing = session.command('playPause').then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(session.media.playing, isFalse);
    reply.complete(
      jsonEncode({'status': 'done', 'snapshot': _state(2, playing: true)}),
    );
    await playing;
    expect(session.media.playing, isTrue);
    expect(finished, isTrue);
  });

  test(
    'a newer periodic observation wins over an earlier command result',
    () async {
      final reply = Completer<Object>();
      browser.replyGate = reply;
      final changing = session.command('speed', .6);
      await Future<void>.delayed(Duration.zero);
      browser.pollState = _state(5, speed: .8);
      await session.refresh();
      reply.complete(
        jsonEncode({'status': 'done', 'snapshot': _state(4, speed: .6)}),
      );
      await changing;
      expect(session.media.speed, .8);
    },
  );

  test(
    'page errors expose confirmed fallback then report command failure',
    () async {
      browser.commandState = _state(1)..['pitchStatus'] = 'unavailable';
      browser.commandStatus = 'error';
      await expectLater(
        session.command('pitch', 1),
        throwsA(isA<WebMediaCommandException>()),
      );
      expect(session.media.pitchStatus, 'unavailable');
      expect(session.media.pitch, 0);
    },
  );

  test(
    'priority Pause works on pages before the bridge is installed',
    () async {
      browser.missingBridge = true;
      await session.command('pause');
      expect(
        browser.scripts.any(
          (s) => s.contains("querySelectorAll('video,audio')"),
        ),
        isTrue,
      );
      await expectLater(
        session.command('speed', .7),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'invalid or duplicate revisions cannot overwrite confirmed state',
    () async {
      browser.pollState = _state(10, speed: .7);
      await session.refresh();
      for (final revision in [null, -1, 9, 10, 10.5, '11', 9007199254740992]) {
        browser.pollState = _state(revision, speed: 1);
        await session.refresh();
        expect(session.media.speed, .7);
      }
      browser.pollState = _state(11, speed: .9);
      await session.refresh();
      expect(session.media.speed, .9);
    },
  );

  test('disposal while awaiting a reply cannot update media', () async {
    final reply = Completer<Object>();
    browser.replyGate = reply;
    final pending = session.command('playPause');
    session.dispose();
    reply.complete(
      jsonEncode({'status': 'done', 'snapshot': _state(1, playing: true)}),
    );
    await expectLater(pending, throwsA(isA<WebMediaCommandCancelled>()));
    expect(session.media.playing, isFalse);
    // Replace the disposed test subject for teardown's single disposal.
    session = WebViewYouTubeSession(controller: browser);
  });

  test('restored watch page is focused once when its video appears', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    WebViewPlatform.instance = _TestWebViewPlatform();
    await session.start(Uri.https('m.youtube.com', '/'));
    await session.openVideo('aqz-KE-bpKQ');
    expect(browser.loaded?.queryParameters['v'], 'aqz-KE-bpKQ');
    browser.pollState = _state(2)..['hasVideo'] = false;
    await session.refresh();
    expect(browser.focusCalls, 0);
    browser.pollState = _state(3);
    await session.refresh();
    expect(browser.focusCalls, 1);
    browser.pollState = _state(4);
    await session.refresh();
    expect(browser.focusCalls, 1, reason: 'Do not undo later user scrolling');
  });
}

Map<String, dynamic> _state(
  Object? revision, {
  double speed = 1,
  bool playing = false,
}) => {
  'snapshotRevision': revision,
  'videoId': 'aqz-KE-bpKQ',
  'hasVideo': true,
  'playing': playing,
  'speed': speed,
  'duration': 120,
  'loopCount': 0,
  'loopEpoch': 1,
  'loopEventsSupported': true,
  'playbackReady': true,
};

class _Browser implements WebViewController {
  @override
  PlatformWebViewController get platform => _FakePlatformController();
  Map<String, dynamic> pollState = _state(0), commandState = _state(1);
  String commandStatus = 'done';
  bool missingBridge = false;
  Completer<bool>? backGate;
  Completer<Object>? replyGate;
  final scripts = <String>[];
  Uri? loaded;
  NavigationDelegate? navigationDelegate;
  int get focusCalls =>
      scripts.where((s) => s.contains('window.scrollTo')).length;
  @override
  Future<void> loadRequest(
    Uri uri, {
    LoadRequestMethod method = LoadRequestMethod.get,
    Map<String, String> headers = const <String, String>{},
    body,
  }) async {
    loaded = uri;
    navigationDelegate?.onPageStarted?.call(uri.toString());
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setNavigationDelegate(NavigationDelegate delegate) async {
    navigationDelegate = delegate;
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    if (missingBridge && script.startsWith('window.TransponoMedia.dispatch')) {
      throw StateError('Bridge not installed yet');
    }
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    if (script.contains('commandResult')) {
      return replyGate?.future ??
          jsonEncode({'status': commandStatus, 'snapshot': commandState});
    }
    return jsonEncode(pollState);
  }

  @override
  Future<bool> canGoBack() async => backGate?.future ?? false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatformController extends PlatformWebViewController {
  _FakePlatformController()
    : super.implementation(const PlatformWebViewControllerCreationParams());
}

class _TestWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}
