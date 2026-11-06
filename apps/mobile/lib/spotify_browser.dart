import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'chord_browser.dart';

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
      host == 'appleid.apple.com' ||
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

  /// Reads `{title, artist, documentTitle}` from the page script below.
  static SpotifyTrack? decode(Object? raw) {
    Object? value = raw;
    // Android may return the JSON quoted; WebKit and Gecko return the string.
    for (var i = 0; value is String && i < 2; i++) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return null;
      }
    }
    if (value is! Map) return null;
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

const String _trackScript = '''
(() => {
  const m = navigator.mediaSession && navigator.mediaSession.metadata;
  return JSON.stringify({
    title: (m && m.title) || '',
    artist: (m && m.artist) || '',
    documentTitle: document.title || ''
  });
})()
''';

/// Spotify's web player inside Transpono, for listening.
///
/// Spotify's audio is DRM-protected, so Transpono cannot reach it: pitch, EQ
/// and effects stay on YouTube. This page shows the chords for the song that
/// is playing and can hand the same song to the YouTube studio.
class SpotifyPage extends StatefulWidget {
  const SpotifyPage({
    super.key,
    required this.onBack,
    required this.onPlayOnYouTube,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onPlayOnYouTube;

  @override
  State<SpotifyPage> createState() => _SpotifyPageState();
}

class _SpotifyPageState extends State<SpotifyPage> {
  static final Uri _home = Uri.https('open.spotify.com', '/');

  GeckoWebViewController? _gecko;
  late final WebViewController _controller;
  late final Widget _view;
  Timer? _poll;
  bool _reading = false;
  bool _disposed = false;
  int _progress = 0;
  String? _error;
  SpotifyTrack? _track;

  WebViewController _createController() {
    if (GeckoEngine.isAvailable) {
      final gecko = GeckoWebViewController();
      _gecko = gecko;
      return WebViewController.fromPlatform(gecko);
    }
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    return WebViewController.fromPlatformCreationParams(params);
  }

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    final gecko = _gecko;
    _view = gecko != null
        ? WebViewWidget.fromPlatform(
            platform: GeckoWebViewWidget(
              gecko,
              key: const Key('spotifyWebView'),
            ),
          )
        : WebViewWidget(
            key: const Key('spotifyWebView'),
            controller: _controller,
          );
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(Colors.black);
      await _controller.setNavigationDelegate(_navigationDelegate());
      if (_disposed) return;
      await _controller.loadRequest(_home);
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_readTrack()),
      );
    } on Object {
      if (!_disposed) {
        setState(() => _error = 'Não foi possível abrir o Spotify.');
      }
    }
  }

  NavigationDelegate _navigationDelegate() {
    void onProgress(int value) {
      if (!_disposed) setState(() => _progress = value);
    }

    void onPageStarted(String _) {
      if (!_disposed) setState(() => _error = null);
    }

    void onError(WebResourceError failure) {
      if (failure.isForMainFrame != true || _disposed) return;
      setState(
        () => _error = 'Não foi possível carregar o Spotify. Verifique a ligação.',
      );
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

  Future<void> _readTrack() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      final raw = await _controller.runJavaScriptReturningResult(_trackScript);
      final track = SpotifyTrack.decode(raw);
      if (!_disposed && track != null && track != _track) {
        setState(() => _track = track);
      }
    } on Object {
      // No page context yet (loading or navigating); the next poll retries.
    } finally {
      _reading = false;
    }
  }

  Future<void> _openChords() async {
    final track = _track;
    final chord = await Navigator.of(context).push<ImportedChord>(
      MaterialPageRoute<ImportedChord>(
        builder: (_) => ChordBrowserPage(initialQuery: track?.query ?? ''),
      ),
    );
    if (chord == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => _ChordTextPage(chord: chord)),
    );
  }

  void _playOnYouTube() {
    final track = _track;
    if (track == null || track.isEmpty) return;
    widget.onPlayOnYouTube(track.query);
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

  @override
  Widget build(BuildContext context) {
    final SpotifyTrack? track = _track;
    final bool playing = track != null && !track.isEmpty;
    final String nowPlaying = track == null || track.isEmpty
        ? 'Toque uma música no Spotify.'
        : track.artist.isEmpty
        ? track.title
        : '${track.title} · ${track.artist}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('spotifyBack'),
                      tooltip: 'Voltar',
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: widget.onBack,
                    ),
                    const _SpotifyBadge(),
                    const SizedBox(width: 10),
                    const Text(
                      'Spotify',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Atualizar',
                      color: Colors.white,
                      icon: const Icon(Icons.refresh),
                      onPressed: () => unawaited(_controller.reload()),
                    ),
                  ],
                ),
              ),
              if (_progress < 100)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  color: const Color(0xFF1ED760),
                  backgroundColor: Colors.transparent,
                ),
              Expanded(child: _view),
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF121214),
                  border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error ?? nowPlaying,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _error != null
                            ? const Color(0xFFFCA5A5)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'No Spotify a música é protegida: o tom, o EQ e os efeitos '
                      'funcionam no YouTube.',
                      style: TextStyle(color: Color(0xFF9E9EA4), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('spotifyChords'),
                            onPressed: () => unawaited(_openChords()),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0x55FFFFFF)),
                              shape: const StadiumBorder(),
                              minimumSize: const Size(0, 46),
                            ),
                            icon: const Icon(Icons.queue_music),
                            label: const Text(
                              'Ver cifra',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            key: const Key('spotifyPlayOnYouTube'),
                            onPressed: playing ? _playOnYouTube : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF0033),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF3A3A3F),
                              shape: const StadiumBorder(),
                              minimumSize: const Size(0, 46),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const FittedBox(
                              child: Text(
                                'Tocar no YouTube com tom',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotifyBadge extends StatelessWidget {
  const _SpotifyBadge();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 26,
    height: 26,
    child: CustomPaint(painter: _SpotifyBadgePainter()),
  );
}

class _SpotifyBadgePainter extends CustomPainter {
  const _SpotifyBadgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, d / 2, Paint()..color = const Color(0xFF1ED760));
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (y, w, t) in const [(-.17, .62, .085), (.03, .52, .07), (.2, .42, .058)]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - d * w / 2, c.dy + d * y + d * .02)
          ..quadraticBezierTo(
            c.dx,
            c.dy + d * y - d * w * .26,
            c.dx + d * w / 2,
            c.dy + d * y + d * .05,
          ),
        stroke..strokeWidth = d * t,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Plain view of a chord sheet picked from a chord site.
class _ChordTextPage extends StatelessWidget {
  const _ChordTextPage({required this.chord});

  final ImportedChord chord;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(chord.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        child: SelectableText(
          chord.text,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Menlo',
            fontFamilyFallback: ['Courier', 'monospace'],
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ),
    ),
  );
}
