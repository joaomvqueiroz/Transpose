import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'youtube_browser.dart';

/// Main-frame destinations the embedded Spotify player may open: Spotify
/// itself and the sign-in providers its login page offers.
bool isSpotifyBrowserUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  final host = uri.host;
  bool under(String domain) => host == domain || host.endsWith('.$domain');
  return under('spotify.com') ||
      under('spotifycdn.com') ||
      under('scdn.co') ||
      host == 'accounts.google.com' ||
      host == 'accounts.youtube.com' ||
      host == 'appleid.apple.com' ||
      host == 'idmsa.apple.com' ||
      host == 'www.facebook.com' ||
      host == 'm.facebook.com';
}

/// The song the Spotify web player reports, from Media Session or the title.
class SpotifyTrack {
  const SpotifyTrack({required this.title, this.artist = ''});

  final String title, artist;

  bool get isEmpty => title.trim().isEmpty;

  /// Search text for YouTube and chord sites.
  String get query => artist.isEmpty ? title : '$title $artist';

  /// "Song - Artist", the shape the studio's chord search expects.
  String get displayTitle => artist.isEmpty ? title : '$title - $artist';

  /// Stable id for the studio (chords, setlist). Never an 11-character
  /// YouTube id, so it can never be opened as a YouTube video by mistake.
  String get id =>
      'spotify-${base64Url.encode(utf8.encode(query.toLowerCase())).replaceAll('=', '')}';

  /// Reads `{title, artist, documentTitle}` from the page script below.
  static SpotifyTrack? decode(Object? raw) {
    final Map<Object?, Object?>? value = _decodeMap(raw);
    if (value == null) return null;
    final title = '${value['title'] ?? ''}'.trim();
    final artist = '${value['artist'] ?? ''}'.trim();
    if (title.isNotEmpty) return SpotifyTrack(title: title, artist: artist);
    return fromDocumentTitle('${value['documentTitle'] ?? ''}');
  }

  /// While a song plays, the web player titles the tab "Song • Artist".
  static SpotifyTrack? fromDocumentTitle(String text) {
    final parts = text.split(' • ');
    if (parts.length < 2) return null;
    final title = parts.first.trim();
    final artist = parts.sublist(1).join(', ').trim();
    if (title.isEmpty || title.toLowerCase().contains('spotify')) return null;
    return SpotifyTrack(title: title, artist: artist);
  }

  @override
  bool operator ==(Object other) =>
      other is SpotifyTrack && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

Map<Object?, Object?>? _decodeMap(Object? raw) {
  Object? value = raw;
  // Android may return the JSON quoted; WebKit and Gecko return the string.
  for (var i = 0; value is String && i < 2; i++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? value : null;
}

/// "1:23" or "1:02:03" from the player's time labels, in seconds.
double parseSpotifyClock(Object? text) {
  final parts = '${text ?? ''}'.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return 0;
  var seconds = 0.0;
  for (final part in parts) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) return 0;
    seconds = seconds * 60 + value;
  }
  return seconds;
}

/// Reads what the web player shows. Text and attributes only; no audio.
const String _snapshotScript = '''
(() => {
  const m = navigator.mediaSession && navigator.mediaSession.metadata;
  const text = s => { const e = document.querySelector(s); return e ? (e.textContent || '').trim() : ''; };
  const button = document.querySelector('[data-testid="control-button-playpause"]');
  const label = button ? (button.getAttribute('aria-label') || '') : '';
  return JSON.stringify({
    title: (m && m.title) || '',
    artist: (m && m.artist) || '',
    documentTitle: document.title || '',
    position: text('[data-testid="playback-position"]'),
    duration: text('[data-testid="playback-duration"]'),
    state: (navigator.mediaSession && navigator.mediaSession.playbackState) || '',
    label: label
  });
})()
''';

/// Presses the player's own play/pause button when its state differs.
String _playPauseScript(bool play) => '''
(() => {
  const button = document.querySelector('[data-testid="control-button-playpause"]');
  if (!button) return false;
  const label = (button.getAttribute('aria-label') || '').toLowerCase();
  const showsPause = label.includes('pause') || label.includes('pausa');
  if (showsPause !== $play) button.click();
  return true;
})()
''';

/// Moves the player's own progress slider, as a user drag would.
String _seekScript(double seconds) => '''
(() => {
  const input = document.querySelector('[data-testid="playback-progressbar"] input[type="range"]');
  if (!input) return false;
  const max = Number(input.max) || 0;
  const value = max > 1000 ? ${seconds * 1000} : $seconds;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  setter.call(input, String(Math.max(0, Math.min(max || value, value))));
  input.dispatchEvent(new Event('input', {bubbles: true}));
  input.dispatchEvent(new Event('change', {bubbles: true}));
  return true;
})()
''';

/// Spotify's web player as the studio's media source.
///
/// The studio shows exactly what it shows for YouTube. Spotify's audio is
/// DRM-protected, so Transpono cannot reach it: pitch, EQ and effects report
/// themselves unavailable here. Play, pause and seeking press the player's
/// own controls. The song title feeds the studio's chord search.
class SpotifyStudioSession extends YouTubeBrowserSession {
  SpotifyStudioSession() {
    if (GeckoEngine.isAvailable) {
      final gecko = GeckoWebViewController();
      _gecko = gecko;
      _controller = WebViewController.fromPlatform(gecko);
    } else {
      final PlatformWebViewControllerCreationParams params =
          WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      _controller = WebViewController.fromPlatformCreationParams(params);
    }
  }

  static final Uri home = Uri.https('open.spotify.com', '/');
  static const String protectedMessage =
      'No Spotify a música é protegida: o tom, o EQ e os efeitos só '
      'funcionam no YouTube.';

  late final WebViewController _controller;
  GeckoWebViewController? _gecko;
  Timer? _poll;
  bool _reading = false;
  bool _disposed = false;
  bool _started = false;
  int _progress = 0;
  String? _error;
  bool _canGoBack = false;
  SpotifyTrack? _track;
  YouTubeMediaState _media = const YouTubeMediaState(
    pitchStatus: 'unavailable',
    keyStatus: 'unavailable',
  );

  /// The song playing now, for "Tocar no YouTube com tom".
  SpotifyTrack? get track => _track;

  @override
  YouTubeMediaState get media => _media;
  @override
  int get progress => _progress;
  @override
  String? get error => _error;
  @override
  bool get canGoBack => _canGoBack;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Always opens Spotify, whatever [uri] the studio passes for YouTube.
  @override
  Future<void> start(Uri uri) async {
    if (_started) return;
    _started = true;
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.black);
    await _controller.setNavigationDelegate(_navigationDelegate());
    if (_disposed) return;
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_refresh()),
    );
    await _controller.loadRequest(home);
  }

  NavigationDelegate _navigationDelegate() {
    void onProgress(int value) {
      _progress = value;
      _notify();
    }

    void onPageStarted(String _) {
      _error = null;
      _notify();
    }

    void onError(WebResourceError failure) {
      if (failure.isForMainFrame != true) return;
      _error = 'Não foi possível carregar o Spotify. Verifique a ligação.';
      _progress = 100;
      _notify();
    }

    NavigationDecision decide(NavigationRequest request) {
      if (!request.isMainFrame) return NavigationDecision.navigate;
      final Uri? uri = Uri.tryParse(request.url);
      // "Abrir app", spotify: links and other sites stay out of the player.
      return uri != null && isSpotifyBrowserUri(uri)
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }

    if (_gecko != null) {
      return NavigationDelegate.fromPlatform(
        GeckoNavigationDelegate(),
        onProgress: onProgress,
        onPageStarted: onPageStarted,
        onWebResourceError: onError,
        onNavigationRequest: decide,
      );
    }
    return NavigationDelegate(
      onProgress: onProgress,
      onPageStarted: onPageStarted,
      onWebResourceError: onError,
      onNavigationRequest: decide,
    );
  }

  Future<void> _refresh() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _snapshotScript,
      );
      final back = await _controller.canGoBack();
      if (_disposed) return;
      final values = _decodeMap(raw);
      final track = SpotifyTrack.decode(raw);
      final label = '${values?['label'] ?? ''}'.toLowerCase();
      final playing =
          values?['state'] == 'playing' ||
          label.contains('pause') ||
          label.contains('pausa');
      _track = track;
      _canGoBack = back;
      _media = YouTubeMediaState(
        videoId: track?.id ?? '',
        title: track?.displayTitle ?? '',
        hasVideo: track != null,
        playing: track != null && playing,
        position: parseSpotifyClock(values?['position']),
        duration: parseSpotifyClock(values?['duration']),
        pitchStatus: 'unavailable',
        pitchMessage: track == null ? '' : protectedMessage,
        playbackReady: track != null,
        keyStatus: 'unavailable',
      );
      _notify();
    } on Object {
      // No page context yet (loading or navigating); the next poll retries.
    } finally {
      _reading = false;
    }
  }

  /// Spotify has no YouTube ids; a saved YouTube item cannot open here.
  @override
  Future<void> openVideo(String videoId) async {}

  @override
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _controller.loadRequest(
      Uri.https('open.spotify.com', '/search/${Uri.encodeComponent(trimmed)}'),
    );
  }

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<void> command(String action, [num? value]) async {
    String? script;
    switch (action) {
      case 'play':
        script = _playPauseScript(true);
      case 'pause':
        script = _playPauseScript(false);
      case 'seekTo':
        if (value != null && value.isFinite) {
          script = _seekScript(value.toDouble().clamp(0, 86400).toDouble());
        }
    }
    // Pitch, speed, loop, EQ and effects cannot reach protected audio.
    if (script == null || _disposed) return;
    try {
      await _controller.runJavaScript(script);
    } on Object {
      // The page may be navigating; the user can press the control again.
    }
    unawaited(_refresh());
  }

  @override
  Widget buildView() {
    final gecko = _gecko;
    if (gecko != null) {
      return WebViewWidget.fromPlatform(
        platform: GeckoWebViewWidget(gecko, key: const Key('spotifyWebView')),
      );
    }
    return WebViewWidget(
      key: const Key('spotifyWebView'),
      controller: _controller,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    // Closing the Gecko session also stops Spotify's audio.
    final gecko = _gecko;
    if (gecko != null) unawaited(gecko.dispose());
    super.dispose();
  }
}
