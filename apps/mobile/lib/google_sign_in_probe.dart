import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'youtube_search.dart';

/// Google sign-in on iPhone ("two engines, one browser").
///
/// Google refuses to sign in on Gecko without JIT ("Algo correu mal"), but
/// signs in in Safari's engine (WKWebView). So the sign-in happens here, in
/// WKWebView, with the engine's own identity; as soon as YouTube opens with a
/// session it is copied into Gecko ([GeckoEngine.importWebKitSession]) and
/// the page closes by itself: the studio then opens signed in.
class GoogleSignInProbePage extends StatefulWidget {
  const GoogleSignInProbePage({super.key});

  static final Uri start = Uri.https('accounts.google.com', '/ServiceLogin', {
    'service': 'youtube',
    'continue': 'https://m.youtube.com/',
  });

  @override
  State<GoogleSignInProbePage> createState() => _GoogleSignInProbePageState();
}

/// Whether Transpono already carries the user's Google session into Gecko.
abstract final class GoogleSession {
  static const String _key = 'transpono.googleSessionImported';

  static Future<bool> imported({SharedPreferencesAsync? preferences}) async {
    try {
      return await (preferences ?? SharedPreferencesAsync()).getBool(_key) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markImported({SharedPreferencesAsync? preferences}) =>
      (preferences ?? SharedPreferencesAsync()).setBool(_key, true);
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
    if (!mounted || _handingOver || uri == null) return;
    if (!isYouTubeBrowserUri(uri)) return;
    // SAPISID is the readable half of a signed-in Google session.
    bool signedIn;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "document.cookie.indexOf('SAPISID=') >= 0",
      );
      signedIn = result == true || '$result' == '1';
    } catch (_) {
      signedIn = false;
    }
    if (!mounted || !signedIn) return;
    await _handOver();
  }

  /// Signed in: copy the session into Gecko and go back to the studio.
  Future<void> _handOver() async {
    setState(() {
      _handingOver = true;
      _error = null;
    });
    try {
      final count = await GeckoEngine.importWebKitSession();
      if (count <= 0) throw StateError('sem cookies da Google');
      await GoogleSession.markImported();
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
      title: const Text('Iniciar sessão'),
      leading: IconButton(
        key: const Key('googleProbeClose'),
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
              key: const Key('googleProbeError'),
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    ),
  );
}

/// Asks once per app run, before YouTube or YouTube Music opens, whether to
/// sign in; then opens [GoogleSignInProbePage]. Only where Gecko runs (on
/// Android the page signs in by itself) and only until the session is in.
class GoogleSignInGate {
  bool _askedThisRun = false;

  Future<void> beforeOpening(BuildContext context) async {
    if (!GeckoEngine.isAvailable || _askedThisRun) return;
    if (await GoogleSession.imported()) return;
    if (!context.mounted) return;
    _askedThisRun = true;
    final bool? signIn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('googleSignInAsk'),
        title: const Text('Iniciar sessão na Google?'),
        content: const Text(
          'Para ver as suas listas, músicas guardadas e recomendações do '
          'YouTube e do YouTube Music.',
        ),
        actions: [
          TextButton(
            key: const Key('googleSignInLater'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            key: const Key('googleSignInYes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Iniciar sessão'),
          ),
        ],
      ),
    );
    if (signIn != true || !context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const GoogleSignInProbePage()),
    );
  }
}
