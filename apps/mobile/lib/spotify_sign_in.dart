import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'google_sign_in_probe.dart';
import 'spotify_browser.dart';

/// Spotify sign-in on iPhone, the same way as the Google one
/// ([GoogleSignInProbePage]): Spotify's sign-in check refuses the Gecko
/// engine ("Ups! Ocorreu um problema"), but accepts Safari's engine
/// (WKWebView). So the user signs in here, with the engine's own identity;
/// when Spotify's player opens, the session is copied into Gecko
/// ([GeckoEngine.importWebKitSession]) and this page closes by itself.
class SpotifySignInPage extends StatefulWidget {
  const SpotifySignInPage({super.key});

  static final Uri start = Uri.https('accounts.spotify.com', '/login', {
    'continue': 'https://open.spotify.com/',
  });

  @override
  State<SpotifySignInPage> createState() => _SpotifySignInPageState();
}

/// Hosts the sign-in may visit in the main frame: Spotify and the sign-in
/// providers its page offers (Google, Apple, Facebook).
bool isSpotifySignInPageUri(Uri uri) =>
    isSpotifyBrowserUri(uri) || isGoogleSignInProbeUri(uri);

/// Signed in and sent on to the player: the sign-in is over.
bool isSpotifySignedInLanding(Uri uri) =>
    uri.scheme == 'https' && uri.host == 'open.spotify.com';

class _SpotifySignInPageState extends State<SpotifySignInPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _handingOver = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: _check,
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            return uri != null && isSpotifySignInPageUri(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(SpotifySignInPage.start);
  }

  Future<void> _check(String url) async {
    final uri = Uri.tryParse(url);
    if (!mounted || _handingOver || uri == null) return;
    if (!isSpotifySignedInLanding(uri)) return;
    await _handOver();
  }

  /// Signed in: copy the session into Gecko and go back to the studio.
  Future<void> _handOver() async {
    setState(() {
      _handingOver = true;
      _error = null;
    });
    try {
      final count = await GeckoEngine.importWebKitSession(scope: 'spotify');
      if (count <= 0) throw StateError('sem sessão do Spotify');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _handingOver = false;
        _error = 'Não foi possível usar a sessão no Transpono ($error).';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Iniciar sessão no Spotify'),
      leading: IconButton(
        key: const Key('spotifySignInClose'),
        tooltip: 'Continuar sem sessão',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(false),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(2),
        child: _progress < 100 || _handingOver
            ? LinearProgressIndicator(
                value: _handingOver ? null : _progress / 100,
                minHeight: 2,
              )
            : const SizedBox(height: 2),
      ),
    ),
    body: Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              _error!,
              key: const Key('spotifySignInError'),
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    ),
  );
}
