import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'spotify_browser.dart';
import 'spotify_library.dart';
import 'studio_appearance.dart';

/// Experiment, iPhone only: «Sua Biblioteca» opens a screen with two
/// segments, «Spotify» (Spotify's DESKTOP web player, in a second WKWebView
/// with a Mac user agent: its mobile page refuses the library with «Baixar
/// app», the desktop one is said to show it) and «Transpono» (the app's own
/// library, unchanged). False: only the app's own library, as before.
const bool spotifyDesktopLibraryExperiment = true;

/// Safari on a Mac: Spotify serves its full (desktop) web player to it.
const String spotifyDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.0 Safari/605.1.15';

/// Where the desktop library opens.
final Uri spotifyDesktopLibraryStart = Uri.https(
  'open.spotify.com',
  '/collection/playlists',
);

/// Run in the desktop page on load and every second (idempotent):
/// - its sound never plays: every audio/video element muted and paused, and
///   `play()` refused, so this page never sounds nor starts a playback
///   (which would also stop the one in the main page);
/// - a 820 px wide viewport, scaled to the screen, and the desktop
///   now-playing bar hidden;
/// - taps on artist, album, playlist and song links (and on play buttons,
///   and double taps on rows) go to the app (`open:URL`) instead of opening
///   here; an in-page route to one of them is reported and undone too;
/// - answers what the page shows, for the note and the diagnostic.
const String _desktopLibraryScript = r'''
(() => {
  const post = (t) => {
    try { if (window.TransponoDesktop) window.TransponoDesktop.postMessage(t); } catch (_) {}
  };
  const KIND = /^\/(?:intl-[a-z-]+\/)?(track|album|playlist|artist|show|episode)\/([A-Za-z0-9]{8,40})/i;
  const itemOf = (href) => {
    try {
      const u = new URL(href || '', location.href);
      if (u.host !== 'open.spotify.com') return '';
      const m = u.pathname.match(KIND);
      return m ? 'https://open.spotify.com/' + m[1].toLowerCase() + '/' + m[2] : '';
    } catch (_) { return ''; }
  };
  const quiet = (m) => {
    try { m.muted = true; m.volume = 0; if (!m.paused) m.pause(); } catch (_) {}
  };
  const ROWS = '[data-testid="tracklist-row"],[role="row"],[data-testid="list-row"],' +
    '[data-encore-id="listRow"],[data-encore-id="card"],[data-testid="card"],[role="listitem"],li';
  // The item a row or card stands for: its first non-artist link, else any
  // item link, else a «spotify:kind:id» in its markup (the sidebar rows).
  const itemIn = (box) => {
    if (!box || !box.querySelectorAll) return '';
    let any = '';
    for (const a of box.querySelectorAll('a[href]')) {
      const u = itemOf(a.getAttribute('href'));
      if (!u) continue;
      if (u.indexOf('/artist/') < 0) return u;
      if (!any) any = u;
    }
    if (any) return any;
    const m = (box.outerHTML || '').slice(0, 20000)
      .match(/spotify:(track|album|playlist|artist|show|episode):([A-Za-z0-9]{8,40})/);
    return m ? 'https://open.spotify.com/' + m[1] + '/' + m[2] : '';
  };
  if (!window.__tpDesk) {
    window.__tpDesk = true;
    window.__tpDeskMedia = new Set();
    try {
      HTMLMediaElement.prototype.play = function () {
        window.__tpDeskMedia.add(this);
        quiet(this);
        return Promise.reject(new DOMException('No sound in this view', 'NotAllowedError'));
      };
    } catch (_) {}
    const PLAY = '[data-testid="play-button"],[data-testid="control-button-playpause"]';
    // A play button (not «Playlists»: the whole first word).
    const playOf = (t) => {
      const p = t.closest(PLAY);
      if (p) return p;
      const b = t.closest('button[aria-label]');
      return b && /^(tocar|reproduzir|play)(\s|$)/i.test(b.getAttribute('aria-label') || '') ? b : null;
    };
    document.addEventListener('click', (event) => {
      const t = event.target;
      if (!t || !t.closest) return;
      let url = '';
      const play = playOf(t);
      if (play) {
        // Never played here: the item goes to the main page, which plays it.
        event.preventDefault();
        event.stopPropagation();
        url = itemIn(play.closest(ROWS)) || itemOf(location.pathname);
        if (url) post('open:' + url);
        return;
      }
      const a = t.closest('a[href]');
      if (a) url = itemOf(a.getAttribute('href'));
      if (!url && !t.closest('button,[role="button"],input,[role="tab"],[role="checkbox"]')) {
        url = itemIn(t.closest(ROWS));
      }
      if (!url) return;
      event.preventDefault();
      event.stopPropagation();
      post('open:' + url);
    }, true);
    // A double tap on a song row plays it on the desktop page: not here.
    document.addEventListener('dblclick', (event) => {
      const t = event.target;
      if (!t || !t.closest) return;
      const row = t.closest(ROWS);
      if (!row) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
  }
  for (const m of document.querySelectorAll('audio, video')) quiet(m);
  for (const m of (window.__tpDeskMedia || [])) quiet(m);
  // A narrow screen: the desktop layout at 820 px, scaled to fit.
  if (document.head) {
    let vp = document.querySelector('meta[name="viewport"]');
    const want = 'width=820, user-scalable=yes';
    if (!vp) {
      vp = document.createElement('meta');
      vp.setAttribute('name', 'viewport');
      document.head.appendChild(vp);
    }
    if (vp.getAttribute('content') !== want) vp.setAttribute('content', want);
    if (!document.getElementById('tp-desk-css')) {
      const css = document.createElement('style');
      css.id = 'tp-desk-css';
      css.textContent =
        '[data-testid="now-playing-bar"],footer[data-testid="now-playing-bar"]{display:none!important}' +
        'html,body{overflow-x:auto!important;-webkit-text-size-adjust:100%!important}';
      document.head.appendChild(css);
    }
  }
  // Moved to an item's page inside the page (no navigation): the app opens
  // it, and this page goes back.
  const here = itemOf(location.pathname);
  if (here && window.__tpDeskLast !== here) {
    window.__tpDeskLast = here;
    post('open:' + here);
    try { history.back(); } catch (_) {}
  }
  const playlists = document.querySelectorAll('a[href*="/playlist/"]').length;
  let items = 0;
  for (const a of document.querySelectorAll('a[href]')) if (itemOf(a.getAttribute('href'))) items++;
  const rows = document.querySelectorAll('[aria-labelledby*="spotify:"]').length;
  let gate = false;
  let login = false;
  if (items === 0 && rows === 0) {
    const text = ((document.body && document.body.innerText) || '').slice(0, 8000);
    gate = /(baixar|obter|get|download)( o| a| the)? app\b|aproveite a sua biblioteca|enjoy your library/i.test(text);
    login = location.host === 'accounts.spotify.com' || /^\/login/.test(location.pathname) ||
      !!document.querySelector('[data-testid="login-button"]');
  }
  return JSON.stringify({
    host: location.host, path: location.pathname, playlists: playlists,
    items: items, rows: rows, gate: gate, login: login,
    ready: document.readyState === 'complete'
  });
})()
''';

Map<Object?, Object?>? _decode(Object? raw) {
  Object? value = raw;
  for (var i = 0; value is String && i < 2; i++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? value : null;
}

int _int(Object? value) => value is num && value.isFinite ? value.toInt() : 0;

enum _LibrarySource { spotify, transpono }

/// The library screen of the experiment: «Spotify» (the desktop web
/// player's library, in its own WKWebView) and «Transpono» ([transpono],
/// the app's own library). A tap on an item of the Spotify one hands its
/// address to [onOpenLink] (the main, mobile Spotify page opens it).
class SpotifyLibraryScreen extends StatefulWidget {
  const SpotifyLibraryScreen({
    super.key,
    required this.transpono,
    required this.onOpenLink,
  });

  final Widget transpono;
  final ValueChanged<String> onOpenLink;

  static const String gateNote =
      'O Spotify não mostrou a biblioteca nesta versão. Usa o separador '
      'Transpono.';

  @override
  State<SpotifyLibraryScreen> createState() => _SpotifyLibraryScreenState();
}

class _SpotifyLibraryScreenState extends State<SpotifyLibraryScreen> {
  _LibrarySource _source = _LibrarySource.spotify;
  late final WebViewController _controller;
  Timer? _poll;
  bool _reading = false;
  DateTime? _lastOpen;
  int _progress = 0;
  String _host = '';
  String _path = '';
  int _playlists = 0;
  int _items = 0;
  int _rows = 0;
  bool _gate = false;
  bool _login = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Its own controller (the main page's scripts never run here), with
    // the default website data store, the main page's: the same sign-in.
    // Media keep needing a user gesture to play (the default).
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
          )
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(spotifyBase);
      await _controller.setUserAgent(spotifyDesktopUserAgent);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (String _) => unawaited(_read()),
          onWebResourceError: (WebResourceError failure) {
            if (failure.isForMainFrame != true) return;
            if (failure.errorCode == -999 || failure.errorCode == 102) return;
            if (mounted) {
              setState(() {
                _error = 'Não foi possível carregar a biblioteca do Spotify.';
                _progress = 100;
              });
            }
          },
          onNavigationRequest: _decide,
        ),
      );
      await _controller.addJavaScriptChannel(
        'TransponoDesktop',
        onMessageReceived: (JavaScriptMessage message) {
          final String text = message.message;
          if (text.startsWith('open:')) _open(text.substring(5));
        },
      );
      if (!mounted) return;
      _poll = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_read()),
      );
      await _controller.loadRequest(spotifyDesktopLibraryStart);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  /// Item pages never open here: the main page opens them.
  NavigationDecision _decide(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null || !isSpotifyBrowserUri(uri)) {
      return NavigationDecision.prevent;
    }
    if (uri.host == 'open.spotify.com' &&
        canonicalSpotifyItemUrl(request.url) != null) {
      _open(request.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _open(String url) {
    if (!mounted) return;
    final canonical = canonicalSpotifyItemUrl(url);
    if (canonical == null) return;
    // One tap may arrive twice (the click and the in-page route).
    final DateTime now = DateTime.now();
    final DateTime? last = _lastOpen;
    if (last != null && now.difference(last).inMilliseconds < 1500) return;
    _lastOpen = now;
    widget.onOpenLink(canonical.url);
  }

  Future<void> _read() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final Object? raw = await _controller.runJavaScriptReturningResult(
        _desktopLibraryScript,
      );
      final Map<Object?, Object?>? values = _decode(raw);
      if (!mounted || values == null) return;
      setState(() {
        _host = '${values['host'] ?? ''}';
        _path = '${values['path'] ?? ''}';
        _playlists = _int(values['playlists']);
        _items = _int(values['items']);
        _rows = _int(values['rows']);
        _gate = values['gate'] == true;
        _login = values['login'] == true;
      });
    } on Object {
      // No page yet; the next poll reads it.
    } finally {
      _reading = false;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _error = null;
      _gate = false;
      _login = false;
    });
    try {
      await _controller.loadRequest(spotifyDesktopLibraryStart);
    } on Object catch (failure) {
      if (mounted) setState(() => _error = '$failure');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final bool spotify = _source == _LibrarySource.spotify;
    return Material(
      color: spotifyBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 8),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                _segment('Spotify', _LibrarySource.spotify),
                const SizedBox(width: 8),
                _segment('Transpono', _LibrarySource.transpono),
                const Spacer(),
                if (spotify)
                  IconButton(
                    tooltip: 'Recarregar',
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () => unawaited(_reload()),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: IndexedStack(
              index: spotify ? 0 : 1,
              sizing: StackFit.expand,
              children: [
                _spotifyPane(),
                // The app's library under the segments: no status-bar gap.
                MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: widget.transpono,
                ),
              ],
            ),
          ),
          if (spotify && defaultTargetPlatform == TargetPlatform.iOS)
            _diagnostic(),
        ],
      ),
    );
  }

  Widget _segment(String label, _LibrarySource source) {
    final bool on = source == _source;
    return Material(
      color: on ? spotifyGreen : const Color(0x1AFFFFFF),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _source = source),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.black : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _spotifyPane() {
    final String? error = _error;
    final bool note = _gate || _login || error != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(
          key: const Key('spotifyDesktopLibrary'),
          controller: _controller,
        ),
        if (_progress < 100)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress / 100,
              minHeight: 2,
              color: spotifyGreen,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (note)
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Material(
              color: const Color(0xF0282828),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error == null
                            ? SpotifyLibraryScreen.gateNote
                            : '$error ${SpotifyLibraryScreen.gateNote}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(_reload()),
                      child: const Text(
                        'Recarregar',
                        style: TextStyle(color: spotifyGreen),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// For the owner's screenshots: where the desktop page is and whether it
  /// shows a library.
  Widget _diagnostic() {
    final String where = _path.isEmpty
        ? '-'
        : (_host == 'open.spotify.com' ? _path : '$_host$_path');
    final String flags = [
      if (_gate) 'gate',
      if (_login) 'login',
    ].join(' ');
    final String text =
        'Diag: $where · playlists: $_playlists · itens: $_items · '
        'linhas: $_rows${flags.isEmpty ? '' : ' · $flags'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: spotifySubdued, fontSize: 11),
      ),
    );
  }
}
