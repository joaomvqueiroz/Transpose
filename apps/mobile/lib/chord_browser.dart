import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'player_chord_sheet.dart';
import 'studio_native_pages.dart';

enum ChordSite {
  cifraClub('Cifra Club', 'www.cifraclub.com.br'),
  cifras('Cifras.com.br', 'www.cifras.com.br');

  const ChordSite(this.label, this.host);
  final String label, host;
  Uri get home => Uri.https(host, '/');
}

bool isChordSourceUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    const {
      'www.cifraclub.com.br',
      'cifraclub.com.br',
      'm.cifraclub.com.br',
      'www.cifras.com.br',
      'cifras.com.br',
    }.contains(uri.host);

/// Search remains a visible browser page, never a scraped results API.
Uri chordSearchUri(ChordSite site, String query) {
  final value = query.trim();
  if (value.isEmpty || value.length > 240) {
    throw const FormatException(
      'Escreva uma música ou artista (até 240 caracteres).',
    );
  }
  return Uri.https('www.google.com', '/search', {
    'q': 'site:${site.host} $value',
    'hl': 'pt-PT',
  });
}

Uri? chordNavigationUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (isChordSourceUri(uri)) return uri;
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
    return null;
  }
  if (uri.host == 'www.google.com' || uri.host == 'google.com') {
    if (uri.path == '/url') {
      final target = Uri.tryParse(
        uri.queryParameters['q'] ?? uri.queryParameters['url'] ?? '',
      );
      return target != null && isChordSourceUri(target) ? target : null;
    }
    if (uri.path == '/search' || uri.path == '/sorry/index') return uri;
  }
  if (uri.host == 'consent.google.com') return uri;
  return null;
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
    if (value['error'] != null) {
      throw const FormatException(
        'Abra a página de uma música com a cifra visível. Não é possível importar pesquisa, bloqueios ou conteúdo protegido.',
      );
    }
    final uri = Uri.tryParse(value['url']);
    if (uri == null || !isChordSourceUri(uri) || uri != expectedUrl) {
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

/// Read-only DOM extraction, called only after a user presses Importar.
/// Does not fetch hidden APIs, alter the site, bypass challenges or execute HTML.
const chordExtractionScript = r'''(() => {
  const result = {title: (document.querySelector('h1')?.innerText || document.title || '').trim().slice(0, 240),
    url: location.href, text: '', error: null};
  const visible = el => {
    for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
      const css = getComputedStyle(node);
      if (node.hidden || node.getAttribute('aria-hidden') === 'true' || css.display === 'none' || css.visibility === 'hidden') return false;
    }
    return el.getClientRects().length > 0;
  };
  const candidates = [...document.querySelectorAll('pre, .cifra_cnt, .cifra-content, #cifra')]
    .filter(visible).map(el => el.innerText || '').filter(text => text.trim().length > 0);
  const score = text => text.split('\n').filter(line => /(^|\s)[A-G](?:#|b)?(?:m|maj|sus|dim|add)?\d*(?:\/[A-G][#b]?)?(?=\s|$)/.test(line)).length;
  candidates.sort((a, b) => score(b) - score(a));
  const chosen = candidates[0] || '';
  if (!chosen || score(chosen) === 0) result.error = 'no-visible-chord';
  else if (chosen.length > 10000) result.error = 'too-long';
  else result.text = chosen;
  return JSON.stringify(result);
})()''';

abstract class ChordBrowserSession extends ChangeNotifier {
  Uri? get currentUri;
  int get progress;
  String? get error;
  bool get canGoBack;
  Future<void> open(Uri uri);
  Future<void> goBack();
  Future<void> reload();
  Future<ImportedChord> extract();
  Widget buildView();
}

class WebViewChordBrowser extends ChordBrowserSession {
  WebViewChordBrowser()
    : controller = WebViewController(
        onPermissionRequest: (request) => request.deny(),
      );
  final WebViewController controller;
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
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final target = chordNavigationUri(request.url);
          if (target == null) {
            _error = 'Este link não pertence aos sites de cifras suportados.';
            _notify();
            return NavigationDecision.prevent;
          }
          if (target.toString() != request.url) {
            unawaited(open(target));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {
          _revision++;
          _uri = Uri.tryParse(url);
          _progress = 0;
          _error = null;
          _notify();
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri != _uri) {
            _revision++;
            _uri = uri;
            _notify();
          }
        },
        onProgress: (value) {
          _progress = value;
          _notify();
        },
        onPageFinished: (_) async {
          final revision = _revision;
          try {
            final back = await controller.canGoBack();
            if (_disposed || revision != _revision) return;
            _back = back;
            _progress = 100;
            _notify();
          } on Object {
            // Closing the browser may destroy its platform view mid-callback.
            if (!_disposed && revision == _revision) {
              _progress = 100;
              _notify();
            }
          }
        },
        onWebResourceError: (failure) {
          if (failure.isForMainFrame != true) return;
          _error = 'Não foi possível abrir a página. Verifique a ligação ou escolha outro site.';
          _progress = 100;
          _notify();
        },
      ),
    );
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
    if (current == null || !isChordSourceUri(current) || _disposed) {
      throw const FormatException('Escolha primeiro uma página de cifra.');
    }
    final result = await controller
        .runJavaScriptReturningResult(chordExtractionScript)
        .timeout(const Duration(seconds: 8));
    final after = Uri.tryParse(await controller.currentUrl() ?? '');
    if (_disposed || revision != _revision || current != after) {
      throw const FormatException(
        'A página mudou durante a importação. Tente novamente.',
      );
    }
    return ImportedChord.decode(result, expectedUrl: current);
  }

  @override
  Widget buildView() => WebViewWidget(controller: controller);
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
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
  late final _query = TextEditingController(text: widget.initialQuery);
  ChordSite _site = ChordSite.cifraClub;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run(() => _session.open(_site.home)));
  }

  @override
  void dispose() {
    _query.dispose();
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

  Future<void> _search() => _run(() async {
    FocusScope.of(context).unfocus();
    final query = _query.text.trim();
    final direct = Uri.tryParse(query);
    if (direct != null && direct.hasScheme) {
      if (!isChordSourceUri(direct)) {
        throw const FormatException(
          'Use um link HTTPS do Cifra Club ou Cifras.com.br.',
        );
      }
      await _session.open(direct);
    } else {
      await _session.open(chordSearchUri(_site, query));
    }
  });

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final chord = await _session.extract();
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Confirmar cifra'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chord.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    chord.url.host,
                    style: const TextStyle(color: studioCyan),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Confira a versão e o tom. Importe apenas conteúdo que tem direito de guardar para o seu uso.',
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      chord.text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('chordImportCancel'),
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              key: const Key('chordImportConfirm'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Usar esta cifra'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) Navigator.pop(context, chord);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível importar. Abra a cifra no site; bloqueios e páginas protegidas não são contornados.',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
                    'Pesquisar cifra',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('chordBrowserBack'),
                  tooltip: 'Página anterior',
                  onPressed: !_importing && _session.canGoBack
                      ? () => _run(_session.goBack)
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  key: const Key('chordBrowserReload'),
                  tooltip: 'Atualizar',
                  onPressed: _importing ? null : () => _run(_session.reload),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<ChordSite>(
                      key: const Key('chordBrowserSite'),
                      value: _site,
                      isExpanded: true,
                      items: [
                        for (final site in ChordSite.values)
                          DropdownMenuItem(
                            value: site,
                            child: Text(site.label),
                          ),
                      ],
                      onChanged: _importing
                          ? null
                          : (site) {
                              if (site == null) return;
                              setState(() => _site = site);
                              unawaited(_run(() => _session.open(site.home)));
                            },
                    ),
                  ),
                  TextButton(
                    onPressed: _importing
                        ? null
                        : () => _run(() => _session.open(_site.home)),
                    child: const Text('Início do site'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                key: const Key('chordSearchInput'),
                controller: _query,
                enabled: !_importing,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Música, artista ou link da cifra',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const Key('chordSearchSubmit'),
                    tooltip: 'Pesquisar neste site',
                    onPressed: _importing ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
            if (_session.progress < 100)
              LinearProgressIndicator(value: _session.progress / 100),
            if (_error != null || _session.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error ?? _session.error!,
                  key: const Key('chordBrowserError'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Expanded(
              child: AbsorbPointer(absorbing: _importing, child: _view),
            ),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('chordBrowserImport'),
                    onPressed:
                        !_importing &&
                            _session.currentUri != null &&
                            isChordSourceUri(_session.currentUri!)
                        ? _import
                        : null,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                      _importing ? 'A ler cifra…' : 'Importar esta cifra',
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
