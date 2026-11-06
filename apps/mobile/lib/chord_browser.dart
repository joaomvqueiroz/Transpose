import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'player_chord_sheet.dart';
import 'studio_native_pages.dart';

final Uri cifrasHome = Uri.https('www.cifras.com.br', '/');

/// Flutter skips compositing an iOS platform view at opacity 0, so WebKit
/// treats the hidden site as off-screen and every element reports no client
/// rects. A near-zero opacity keeps it laid out while staying invisible.
@visibleForTesting
double get hiddenChordSiteOpacity =>
    defaultTargetPlatform == TargetPlatform.iOS ? 0.01 : 0;

bool isChordSourceUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    const {'www.cifras.com.br', 'cifras.com.br'}.contains(uri.host);

/// The same chord page, whatever the host spelling (www or not), a trailing
/// slash, a query or a fragment. Gecko can report the address before and
/// after the site's own redirects/updates differently, which made every
/// import fail as "a página mudou".
bool sameChordPage(Uri? a, Uri? b) {
  if (a == null || b == null) return false;
  String host(Uri uri) =>
      uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  String path(Uri uri) => uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return a.scheme == b.scheme && host(a) == host(b) && path(a) == path(b);
}

bool isChordPageUri(Uri uri) =>
    isChordSourceUri(uri) &&
    uri.pathSegments.length >= 3 &&
    uri.pathSegments.first == 'cifra';

/// Opens the site's own visible results page with its search field populated.
Uri chordSearchUri(String query) {
  final value = query.trim();
  if (value.isEmpty || value.length > 240) {
    throw const FormatException(
      'Escreva uma música ou artista (até 240 caracteres).',
    );
  }
  return Uri.https('www.cifras.com.br', '/busca', {'q': value});
}

String chordQueryFromVideoTitle(String title) {
  final value = title
      .replaceFirst(RegExp(r'\s*[-–]\s*YouTube\s*$', caseSensitive: false), '')
      // "(Ao Vivo …)", "[Clipe Oficial]", "| Playlist": noise for the chord
      // site's search, which then finds nothing.
      .replaceAll(RegExp(r'\s*[(\[][^)\]]*[)\]]?'), ' ')
      .replaceFirst(RegExp(r'\s*[|｜].*$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (RegExp(
    r'^(?:YouTube|Vídeo do YouTube)$',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '';
  }
  return value.length <= 240 ? value : value.substring(0, 240).trimRight();
}

Uri? chordNavigationUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (isChordSourceUri(uri)) return uri;
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
    return null;
  }
  return null;
}

/// The chord site is showing its Cloudflare check ("Just a moment...")
/// instead of the song.
class ChordSiteCheckException extends FormatException {
  const ChordSiteCheckException()
    : super('O Cifras.com.br está a verificar o navegador.');
}

class ImportedChord {
  const ImportedChord({
    required this.title,
    required this.url,
    required this.text,
  });
  final String title, text;
  final Uri url;

  factory ImportedChord.decode(Object raw, {required Uri expectedUrl}) {
    dynamic value = raw;
    for (var i = 0; i < 2 && value is String; i++) {
      if (value.length > 100000) {
        throw const FormatException('Página demasiado grande.');
      }
      value = jsonDecode(value);
    }
    if (value is! Map ||
        value['text'] is! String ||
        value['url'] is! String ||
        value['title'] is! String) {
      throw const FormatException(
        'Não foi possível ler uma cifra nesta página.',
      );
    }
    if (value['error'] == 'challenge') throw const ChordSiteCheckException();
    if (value['error'] != null) {
      final detail = '${value['error']}';
      throw FormatException(
        'Abra a página de uma música com a cifra visível. Não é possível importar pesquisa, bloqueios ou conteúdo protegido.'
        '${detail.length > 3 && detail.length < 200 ? ' [$detail]' : ''}',
      );
    }
    final uri = Uri.tryParse(value['url']);
    if (uri == null || !isChordPageUri(uri) || !sameChordPage(uri, expectedUrl)) {
      throw const FormatException('A página mudou. Volte a tocar em importar.');
    }
    final text = validatePlayerChordText(value['text']);
    final chordRows = text
        .split('\n')
        .where(
          (line) => RegExp(
            r'(^|\s)[A-G](?:#|b)?(?:m|maj|sus|dim|add)?\d*(?:/[A-G][#b]?)?(?=\s|$)',
          ).hasMatch(line),
        );
    if (chordRows.isEmpty) {
      throw const FormatException(
        'Não foram encontrados acordes nesta página.',
      );
    }
    final title = (value['title'] as String).trim();
    if (title.length > 240) {
      throw const FormatException('Título da página demasiado longo.');
    }
    return ImportedChord(
      title: title.isEmpty ? 'Cifra importada' : title,
      url: uri,
      text: text,
    );
  }
}

/// Read-only DOM extraction of the visible chord page, before user approval.
/// Does not fetch hidden APIs, alter the site, bypass challenges or execute HTML.
const chordExtractionScript = r'''(() => {
  const result = {title: (document.querySelector('h1')?.innerText || document.title || '').trim().slice(0, 240),
    url: location.href, text: '', error: null};
  // Only the check page itself: every normal page of the site also loads a
  // small Cloudflare "challenge-platform" script, so that is no sign.
  if (/^(just a moment|um momento|attention required)/i.test((document.title || '').trim()) ||
      document.querySelector('#challenge-form, #challenge-running, #challenge-stage')) {
    result.error = 'challenge';
    return JSON.stringify(result);
  }
  const visible = el => {
    for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
      const css = getComputedStyle(node);
      // aria-hidden is not used: a site dialog or ad marks the whole page
      // with it while the chord is still on screen.
      if (node.hidden || css.display === 'none' || css.visibility === 'hidden') return false;
    }
    return el.getClientRects().length > 0;
  };
  const candidates = [...document.querySelectorAll('pre, .cifra_cnt, .cifra-content, #cifra')]
    .filter(visible).map(el => el.innerText || '').filter(text => text.trim().length > 0);
  const score = text => text.split('\n').filter(line => /(^|\s)[A-G](?:#|b)?(?:m|maj|sus|dim|add)?\d*(?:\/[A-G][#b]?)?(?=\s|$)/.test(line)).length;
  candidates.sort((a, b) => score(b) - score(a));
  const chosen = candidates[0] || '';
  if (!chosen || score(chosen) === 0) {
    // Say what the page had, so a failure on the phone can be understood.
    const all = document.querySelectorAll('pre, .cifra_cnt, .cifra-content, #cifra').length;
    result.error = `sem acordes visíveis: ${all} bloco(s) de cifra, ${candidates.length} visível(eis), página «${(document.title || '').slice(0, 60)}», ${innerWidth}x${innerHeight}`;
  }
  else if (chosen.length > 10000) result.error = 'too-long';
  else result.text = chosen;
  return JSON.stringify(result);
})()''';

const chordSearchResultsScrollScript = r'''(() => {
  if (location.pathname !== '/busca' && location.pathname !== '/') return false;
  window.scrollBy({top: window.innerHeight, left: 0, behavior: 'instant'});
  return true;
})()''';

class ChordSearchResult {
  const ChordSearchResult({required this.title, required this.url});
  final String title;
  final Uri url;
}

/// Reads only the song links rendered in the site's public search page.
const chordResultsScript =
    r'''(() => JSON.stringify([...document.querySelectorAll('a[href]')]
  .filter(a => a.getClientRects().length && a.href && new URL(a.href).pathname.startsWith('/cifra/'))
  .map(a => ({title: (a.innerText || a.getAttribute('title') || '').trim().replace(/\s+/g, ' ').slice(0, 180), url: a.href}))
  .filter(item => item.title).slice(0, 60)))()''';

List<ChordSearchResult> decodeChordSearchResults(Object raw) {
  dynamic value = raw;
  for (var i = 0; i < 2 && value is String; i++) {
    if (value.length > 100000) return const [];
    value = jsonDecode(value);
  }
  if (value is! List) return const [];
  final seen = <Uri>{};
  return value
      .whereType<Map>()
      .map((entry) {
        final title = entry['title'];
        final url = entry['url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (title is! String ||
            uri == null ||
            !isChordPageUri(uri) ||
            !seen.add(uri)) {
          return null;
        }
        return ChordSearchResult(title: title.trim(), url: uri);
      })
      .whereType<ChordSearchResult>()
      .toList(growable: false);
}

abstract class ChordBrowserSession extends ChangeNotifier {
  Uri? get currentUri;
  int get progress;
  String? get error;
  bool get canGoBack;
  Future<void> open(Uri uri);
  Future<void> goBack();
  Future<void> reload();
  Future<ImportedChord> extract();
  Future<List<ChordSearchResult>> searchResults() async => const [];
  Widget buildView();
}

class WebViewChordBrowser extends ChordBrowserSession {
  /// [gecko] picks the engine in iPhone builds that embed Gecko (default:
  /// Gecko when available). Cifras.com.br puts song pages behind a Cloudflare
  /// check that Gecko on iPhone does not pass, while Safari's engine does; but
  /// an earlier build saw the site never finish loading in WKWebView there.
  /// The search panel therefore tries WKWebView first and falls back to Gecko.
  WebViewChordBrowser({bool? gecko}) {
    if (gecko ?? GeckoEngine.isAvailable) {
      final gecko = GeckoWebViewController();
      _gecko = gecko;
      controller = WebViewController.fromPlatform(gecko);
    } else {
      controller = WebViewController(
        onPermissionRequest: (request) => request.deny(),
      );
    }
  }
  late final WebViewController controller;
  GeckoWebViewController? _gecko;
  bool get usesGecko => _gecko != null;
  Uri? _uri;
  int _progress = 0, _revision = 0;
  bool _disposed = false, _back = false;
  String? _error;
  Future<void>? _setup;
  @override
  Uri? get currentUri => _uri;
  @override
  int get progress => _progress;
  @override
  bool get canGoBack => _back;
  @override
  String? get error => _error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _configure() async {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(studioBg);
    if (controller.platform is AndroidWebViewController) {
      await AndroidWebViewController.enableDebugging(kDebugMode);
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(true);
    }
    NavigationDecision onNavigationRequest(NavigationRequest request) {
      if (!request.isMainFrame) return NavigationDecision.navigate;
      final target = chordNavigationUri(request.url);
      if (target == null) {
        _error = 'Só é possível abrir páginas do Cifras.com.br.';
        _notify();
        return NavigationDecision.prevent;
      }
      if (target.toString() != request.url) {
        unawaited(open(target));
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }

    void onPageStarted(String url) {
      _revision++;
      _uri = Uri.tryParse(url);
      _progress = 0;
      _error = null;
      _notify();
    }

    void onUrlChange(UrlChange change) {
      final uri = Uri.tryParse(change.url ?? '');
      if (uri == _uri) return;
      // A different spelling of the same page (Gecko reports its location
      // updates separately) must not cancel an import in progress.
      if (!sameChordPage(uri, _uri)) _revision++;
      _uri = uri;
      _notify();
    }

    void onProgress(int value) {
      _progress = value;
      _notify();
    }

    Future<void> onPageFinished(String _) async {
      final revision = _revision;
      try {
        final back = await controller.canGoBack();
        if (_disposed || revision != _revision) return;
        _back = back;
        _progress = 100;
        _notify();
        if (_uri?.path == '/busca' || _uri?.path == '/') {
          unawaited(_scrollSearchResults(revision));
        }
      } on Object {
        // Closing the browser may destroy its platform view mid-callback.
        if (!_disposed && revision == _revision) {
          _progress = 100;
          _notify();
        }
      }
    }

    void onWebResourceError(WebResourceError failure) {
      if (failure.isForMainFrame != true) return;
      _error = 'Não foi possível abrir o Cifras.com.br. Verifique a ligação.';
      _progress = 100;
      _notify();
    }

    await controller.setNavigationDelegate(
      _gecko == null
          ? NavigationDelegate(
              onNavigationRequest: onNavigationRequest,
              onPageStarted: onPageStarted,
              onUrlChange: onUrlChange,
              onProgress: onProgress,
              onPageFinished: onPageFinished,
              onWebResourceError: onWebResourceError,
            )
          : NavigationDelegate.fromPlatform(
              GeckoNavigationDelegate(),
              onNavigationRequest: onNavigationRequest,
              onPageStarted: onPageStarted,
              onUrlChange: onUrlChange,
              onProgress: onProgress,
              onPageFinished: onPageFinished,
              onWebResourceError: onWebResourceError,
            ),
    );
  }

  Future<void> _scrollSearchResults(int revision) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (_disposed ||
        revision != _revision ||
        (_uri?.path != '/busca' && _uri?.path != '/')) {
      return;
    }
    try {
      await controller.runJavaScript(chordSearchResultsScrollScript);
    } on Object {
      // The site can navigate again while this page finishes rendering.
    }
  }

  @override
  Future<void> open(Uri uri) async {
    final target = chordNavigationUri(uri.toString());
    if (target == null) {
      throw const FormatException('Endereço de cifra não suportado.');
    }
    await (_setup ??= _configure());
    if (!_disposed) await controller.loadRequest(target);
  }

  @override
  Future<void> goBack() => controller.goBack();
  @override
  Future<void> reload() => controller.reload();
  @override
  Future<ImportedChord> extract() async {
    final revision = _revision;
    final current = Uri.tryParse(await controller.currentUrl() ?? '');
    if (current == null || !isChordPageUri(current) || _disposed) {
      throw const FormatException('Escolha primeiro uma página de cifra.');
    }
    final result = await controller
        .runJavaScriptReturningResult(chordExtractionScript)
        .timeout(const Duration(seconds: 8));
    final after = Uri.tryParse(await controller.currentUrl() ?? '');
    if (_disposed || revision != _revision || !sameChordPage(current, after)) {
      throw const FormatException(
        'A página mudou durante a importação. Tente novamente.',
      );
    }
    return ImportedChord.decode(result, expectedUrl: current);
  }

  @override
  Future<List<ChordSearchResult>> searchResults() async {
    if (_disposed || _uri?.path != '/busca') return const [];
    final result = await controller.runJavaScriptReturningResult(
      chordResultsScript,
    );
    return decodeChordSearchResults(result);
  }

  @override
  Widget buildView() {
    final gecko = _gecko;
    if (gecko != null) {
      return WebViewWidget.fromPlatform(platform: GeckoWebViewWidget(gecko));
    }
    return WebViewWidget(controller: controller);
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    final gecko = _gecko;
    if (gecko != null) unawaited(gecko.dispose());
    super.dispose();
  }
}

/// Native Transpono search/results UI; the site page is kept in a tiny,
/// non-interactive WebView solely to read its publicly displayed song links.
class ChordSearchPanel extends StatefulWidget {
  const ChordSearchPanel({
    super.key,
    required this.initialQuery,
    required this.onCancel,
    required this.onSelected,
    this.sessionFactory,
  });

  final String initialQuery;
  final VoidCallback onCancel;
  final Future<void> Function(ImportedChord) onSelected;
  final ChordBrowserSession Function()? sessionFactory;

  @override
  State<ChordSearchPanel> createState() => _ChordSearchPanelState();
}

class _ChordSearchPanelState extends State<ChordSearchPanel> {
  // In Gecko builds the chord site first opens in Safari's engine (it passes
  // the site's Cloudflare check); if that page never finishes loading, the
  // panel switches to Gecko once and repeats the last step.
  late bool _canFallBack =
      widget.sessionFactory == null && GeckoEngine.isAvailable;
  late ChordBrowserSession _session =
      widget.sessionFactory?.call() ??
      WebViewChordBrowser(gecko: _canFallBack ? false : null);
  late Widget _siteView = _session.buildView();
  Uri? _lastOpened;
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  List<ChordSearchResult> _results = const [];
  String? _error;
  Uri? _lastReadyUri;
  bool _loading = false;
  int _generation = 0;
  // The site's browser check is on screen: show the page so it can finish
  // (and be answered by a tap if it asks for one).
  bool _siteCheck = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (_query.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  Future<void> _openWatched(Uri uri) async {
    _lastOpened = uri;
    final generation = _generation;
    final session = _session;
    await session.open(uri);
    if (_canFallBack) unawaited(_fallBackIfStuck(generation, session));
  }

  Future<void> _fallBackIfStuck(
    int generation,
    ChordBrowserSession session,
  ) async {
    // Safari's engine did not load a page in 15 s: use Gecko instead.
    await Future<void>.delayed(const Duration(seconds: 15));
    if (!mounted ||
        !_canFallBack ||
        generation != _generation ||
        !identical(session, _session) ||
        session.progress >= 100) {
      return;
    }
    _canFallBack = false;
    session.removeListener(_changed);
    final gecko = WebViewChordBrowser(gecko: true);
    setState(() {
      _session = gecko;
      _siteView = gecko.buildView();
      _lastReadyUri = null;
    });
    session.dispose();
    gecko.addListener(_changed);
    final target = _lastOpened;
    if (target != null) await gecko.open(target);
  }

  @override
  void dispose() {
    _generation++;
    _session.removeListener(_changed);
    _session.dispose();
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final uri = _session.currentUri;
    if (uri != null && _session.progress >= 100 && uri != _lastReadyUri) {
      _lastReadyUri = uri;
      _canFallBack = false; // This engine loads the site: keep it.
      final generation = _generation;
      if (uri.path == '/busca') {
        unawaited(_readResults(generation));
      } else if (isChordPageUri(uri)) {
        unawaited(_readChord(generation, uri));
      }
    }
    setState(() {});
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    Uri uri;
    try {
      uri = chordSearchUri(query);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
      _lastReadyUri = null;
    });
    try {
      await _openWatched(uri);
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível pesquisar no Cifras.com.br.';
        });
      }
    }
  }

  Future<void> _readResults(int generation) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted || generation != _generation) return;
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (!mounted ||
          generation != _generation ||
          _session.currentUri?.path != '/busca') {
        return;
      }
      try {
        final results = await _session.searchResults();
        if (!mounted || generation != _generation) return;
        if (results.isNotEmpty) {
          setState(() {
            _results = results;
            _loading = false;
            _error = null;
          });
          return;
        }
      } on Object {
        // The dynamic results may not have finished rendering yet.
      }
    }
    if (mounted && generation == _generation) {
      setState(() {
        _loading = false;
        _error = _session.error ?? 'Nenhuma cifra encontrada. Experimente pesquisar por música e artista.';
      });
    }
  }

  Future<void> _choose(ChordSearchResult result) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _lastReadyUri = null;
    });
    try {
      await _openWatched(result.url);
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir esta cifra. Tente outra.';
        });
      }
    }
  }

  Future<void> _readChord(int generation, Uri uri) async {
    // Gecko on iPhone has no JIT, so the site can take a few seconds longer
    // to show the chord; keep trying for about 5 s and say why it failed.
    // When the site shows its Cloudflare check instead ("Just a moment..."),
    // wait up to a minute with the page on screen: the check usually passes
    // by itself, and if it asks for a tap the user can give it.
    var lastReason = '';
    var attempts = 12;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (!mounted ||
          generation != _generation ||
          !sameChordPage(_session.currentUri, uri)) {
        if (mounted && _siteCheck) setState(() => _siteCheck = false);
        return;
      }
      try {
        final chord = await _session.extract();
        if (!mounted || generation != _generation) return;
        if (_siteCheck) setState(() => _siteCheck = false);
        await widget.onSelected(chord);
        return;
      } on ChordSiteCheckException catch (failure) {
        lastReason = failure.message;
        attempts = 135; // About a minute in all.
        if (!_siteCheck && mounted) {
          setState(() {
            _siteCheck = true;
            _error =
                'O Cifras.com.br está a verificar o navegador. Aguarde; se '
                'aparecer uma caixa na página acima, toque nela.';
          });
        }
      } on FormatException catch (failure) {
        // A visible chord can be inserted shortly after page load.
        lastReason = failure.message;
      } on Object catch (failure) {
        lastReason = '$failure';
      }
    }
    if (mounted && generation == _generation) {
      final reason = lastReason.length > 260
          ? '${lastReason.substring(0, 260)}…'
          : lastReason;
      setState(() {
        _siteCheck = false;
        _loading = false;
        _error =
            'Não foi possível ler esta cifra. Escolha outro resultado.'
            '${reason.isEmpty ? '' : ' ($reason)'}';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 0,
        right: 0,
        top: _siteCheck ? 150 : 0,
        height: 320,
        child: IgnorePointer(
          ignoring: !_siteCheck,
          child: ExcludeSemantics(
            excluding: !_siteCheck,
            child: Opacity(
              opacity: _siteCheck ? 1 : hiddenChordSiteOpacity,
              child: _siteView,
            ),
          ),
        ),
      ),
      if (!_siteCheck) SingleChildScrollView(
        key: const Key('chordNativeResults'),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chordNativeQuery'),
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'Pesquisar música ou artista',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        suffixIcon: IconButton(
                          key: const Key('chordNativeSearch'),
                          tooltip: 'Pesquisar cifras',
                          onPressed: _search,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('chordNativeClose'),
                    tooltip: 'Fechar pesquisa',
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (_loading || _session.progress < 100)
              const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, key: const Key('chordNativeError')),
              ),
            for (var index = 0; index < _results.length; index++)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Material(
                  color: const Color(0xFF201F21),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: Key('chordNativeResult$index'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: _loading ? null : () => _choose(_results[index]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.library_music_outlined,
                            size: 18,
                            color: studioCyan,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _results[index].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_siteCheck)
        Positioned(
          left: 16,
          right: 8,
          top: 8,
          height: 134,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _error ?? '',
                  key: const Key('chordSiteCheck'),
                  style: const TextStyle(fontSize: 15, height: 1.3),
                ),
              ),
              IconButton(
                tooltip: 'Cancelar',
                onPressed: () => setState(() {
                  _generation++;
                  _siteCheck = false;
                  _loading = false;
                  _error = null;
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
    ],
  );
}

class ChordBrowserPage extends StatefulWidget {
  const ChordBrowserPage({
    super.key,
    this.initialQuery = '',
    this.sessionFactory,
  });
  final String initialQuery;
  final ChordBrowserSession Function()? sessionFactory;
  @override
  State<ChordBrowserPage> createState() => _ChordBrowserPageState();
}

class _ChordBrowserPageState extends State<ChordBrowserPage> {
  late final ChordBrowserSession _session =
      widget.sessionFactory?.call() ?? WebViewChordBrowser();
  late final Widget _view = _session.buildView();
  bool _preparing = false;
  ImportedChord? _prepared;
  Uri? _observedUri, _requestedUri;
  int _generation = 0, _lastProgress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session.addListener(_sessionChanged);
    final query = widget.initialQuery.trim();
    unawaited(
      _run(
        () => _session.open(query.isEmpty ? cifrasHome : chordSearchUri(query)),
      ),
    );
  }

  @override
  void dispose() {
    _session.removeListener(_sessionChanged);
    _session.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _error = null);
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar. Tente novamente.');
      }
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    final uri = _session.currentUri;
    final progress = _session.progress;
    if (uri != _observedUri || (progress < 100 && _lastProgress == 100)) {
      _generation++;
      _observedUri = uri;
      _requestedUri = null;
      _prepared = null;
      _preparing = false;
      _error = null;
    }
    _lastProgress = progress;
    if (uri != null &&
        isChordPageUri(uri) &&
        progress >= 100 &&
        _requestedUri != uri) {
      _requestedUri = uri;
      unawaited(_prepare(uri, _generation));
    }
    setState(() {});
  }

  Future<void> _prepare(Uri uri, int generation) async {
    if (!mounted || generation != _generation) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (!mounted || generation != _generation || !sameChordPage(_session.currentUri, uri)) {
        return;
      }
      try {
        final chord = await _session.extract();
        if (!mounted ||
            generation != _generation ||
            !sameChordPage(_session.currentUri, uri)) {
          return;
        }
        setState(() {
          _prepared = chord;
          _preparing = false;
          _error = null;
        });
        return;
      } on Object {
        // The visible chord block may appear shortly after page load.
      }
    }
    if (mounted && generation == _generation && sameChordPage(_session.currentUri, uri)) {
      setState(() {
        _preparing = false;
        _error = 'Não foi possível ler esta cifra. Abra uma página de música com os acordes visíveis ou tente novamente.';
      });
    }
  }

  void _retryPreparation() {
    final uri = _session.currentUri;
    if (uri == null || !isChordPageUri(uri) || _preparing) return;
    _requestedUri = uri;
    unawaited(_prepare(uri, _generation));
  }

  void _usePrepared() {
    final chord = _prepared;
    if (chord == null || chord.url != _session.currentUri) return;
    Navigator.pop(context, chord);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('chordBrowserPage'),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _session,
        builder: (context, _) => Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('chordBrowserClose'),
                  tooltip: 'Voltar ao player',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                const Expanded(
                  child: Text(
                    'Cifras.com.br',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('chordBrowserBack'),
                  tooltip: 'Página anterior',
                  onPressed: _session.canGoBack
                      ? () => _run(_session.goBack)
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  key: const Key('chordBrowserReload'),
                  tooltip: 'Atualizar',
                  onPressed: () => _run(_session.reload),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_session.progress < 100)
              LinearProgressIndicator(value: _session.progress / 100),
            if (_error != null || _session.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error ?? _session.error!,
                        key: const Key('chordBrowserError'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_error != null &&
                        _session.currentUri != null &&
                        isChordPageUri(_session.currentUri!))
                      TextButton(
                        key: const Key('chordBrowserRetry'),
                        onPressed: _retryPreparation,
                        child: const Text('Tentar ler'),
                      ),
                  ],
                ),
              ),
            Expanded(child: _view),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('chordBrowserImport'),
                    onPressed:
                        _prepared != null &&
                            _prepared!.url == _session.currentUri
                        ? _usePrepared
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      _preparing ? 'A preparar cifra…' : 'Usar esta cifra',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
