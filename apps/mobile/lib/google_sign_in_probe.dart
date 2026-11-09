import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'youtube_search.dart';

/// First step of "two engines, one browser" on iPhone: Google refuses to sign
/// in on Gecko without JIT ("Algo correu mal"), so try the sign-in in Safari's
/// engine (WKWebView). This page only shows whether it works: once YouTube
/// opens with a session cookie it says so. Copying the session into Gecko is
/// the next step and only happens if this one passes.
///
/// The engine keeps its own identity (no user-agent changes): Google decides
/// with the truth.
class GoogleSignInProbePage extends StatefulWidget {
  const GoogleSignInProbePage({super.key});

  static final Uri start = Uri.https('accounts.google.com', '/ServiceLogin', {
    'service': 'youtube',
    'continue': 'https://m.youtube.com/',
  });

  @override
  State<GoogleSignInProbePage> createState() => _GoogleSignInProbePageState();
}

/// Hosts the sign-in may visit in the main frame.
bool isGoogleSignInProbeUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (isYouTubeBrowserUri(uri) || isGoogleSignInUri(uri)) return true;
  final host = uri.host;
  return host == 'accounts.youtube.com' ||
      RegExp(r'^(?:[a-z0-9-]+\.)?google\.(?:com|[a-z]{2}|com?\.[a-z]{2})$')
          .hasMatch(host);
}

class _GoogleSignInProbePageState extends State<GoogleSignInProbePage> {
  late final WebViewController _controller;
  String _host = '';
  int _progress = 0;
  bool? _signedIn;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) => setState(() => _progress = value),
          onPageFinished: (url) => _check(url),
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            return uri != null && isGoogleSignInProbeUri(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(GoogleSignInProbePage.start);
  }

  Future<void> _check(String url) async {
    final uri = Uri.tryParse(url);
    if (!mounted || uri == null) return;
    setState(() => _host = uri.host);
    if (!isYouTubeBrowserUri(uri)) return;
    // SAPISID is the readable half of a signed-in Google session.
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "document.cookie.indexOf('SAPISID=') >= 0",
      );
      if (!mounted) return;
      setState(() => _signedIn = result == true || '$result' == '1');
    } catch (_) {
      if (mounted) setState(() => _signedIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String status = switch (_signedIn) {
      true => 'Sessão iniciada no motor do Safari. O teste passou.',
      false => 'O YouTube abriu, mas sem sessão iniciada.',
      null => 'Inicie sessão na conta Google. ($_host)',
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Conta Google (teste)'),
        leading: IconButton(
          key: const Key('googleProbeClose'),
          tooltip: 'Fechar',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(34),
          child: Column(
            children: [
              if (_progress < 100)
                LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Text(
                  status,
                  key: const Key('googleProbeStatus'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _signedIn == true
                        ? const Color(0xFF34D399)
                        : const Color(0xFFB8B8BC),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
