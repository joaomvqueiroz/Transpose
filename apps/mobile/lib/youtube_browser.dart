import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'youtube_search.dart';
import 'web_media_command.dart';

/// Values reported by the media element and the in-browser audio graph.
/// A successful command alone never changes the displayed pitch.
@immutable
class YouTubeMediaState {
  const YouTubeMediaState({
    this.videoId = '',
    this.title = '',
    this.hasVideo = false,
    this.playing = false,
    this.muted = false,
    this.position = 0,
    this.duration = 0,
    this.speed = 1,
    this.pitch = 0,
    this.pitchStatus = 'idle',
    this.pitchMessage = '',
    this.loopA,
    this.loopB,
    this.loopEnabled = false,
    this.isAd = false,
    this.loopCount = 0,
    this.loopEpoch = 0,
    this.loopEventsSupported = false,
    this.playbackReady = false,
  });

  factory YouTubeMediaState.fromJson(Map<String, dynamic> json) {
    double? number(String key) {
      final Object? value = json[key];
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    String string(String key) => json[key] is String ? json[key] as String : '';
    int? counter(String key) {
      final double? value = number(key);
      return value != null &&
              value >= 0 &&
              value <= 9007199254740991 &&
              value == value.truncateToDouble()
          ? value.toInt()
          : null;
    }

    final int? loopCount = counter('loopCount');
    final int? loopEpoch = counter('loopEpoch');
    return YouTubeMediaState(
      videoId: string('videoId'),
      title: string('title'),
      hasVideo: json['hasVideo'] == true,
      playing: json['playing'] == true,
      muted: json['muted'] == true,
      position: (number('position') ?? 0).clamp(0, double.maxFinite),
      duration: (number('duration') ?? 0).clamp(0, double.maxFinite),
      speed: number('speed') ?? 1,
      pitch: (number('pitch') ?? 0).clamp(-12, 12),
      pitchStatus: string('pitchStatus'),
      pitchMessage: string('pitchMessage'),
      loopA: number('loopA'),
      loopB: number('loopB'),
      loopEnabled: json['loopEnabled'] == true,
      isAd: json['isAd'] == true,
      loopCount: loopCount ?? 0,
      loopEpoch: loopEpoch ?? 0,
      loopEventsSupported:
          json['loopEventsSupported'] == true &&
          loopCount != null &&
          loopEpoch != null,
      playbackReady:
          json['playbackReady'] == true &&
          json['hasVideo'] == true &&
          json['isAd'] != true,
    );
  }

  final String videoId, title, pitchStatus, pitchMessage;
  final bool hasVideo, playing, muted, loopEnabled, isAd;
  final bool loopEventsSupported, playbackReady;
  final int loopCount, loopEpoch;
  final double position, duration, speed, pitch;
  final double? loopA, loopB;
}

/// The browser has one media element/graph; Flutter only issues commands and
/// observes acknowledgements. This seam also permits network-free UI tests.
abstract class YouTubeBrowserSession extends ChangeNotifier {
  YouTubeMediaState get media;
  int get progress;
  String? get error;
  bool get canGoBack;
  Future<void> start(Uri uri);
  Future<void> openVideo(String videoId) => start(_youtubeVideoUri(videoId));
  Future<void> focusVideo() async {}
  Future<void> search(String query);
  Future<void> reload();
  Future<void> goBack();
  Future<void> command(String action, [num? value]);
  Widget buildView();
}

Uri _youtubeVideoUri(String videoId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
    throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
  }
  return Uri.https('m.youtube.com', '/watch', <String, String>{'v': videoId});
}

class WebViewYouTubeSession extends YouTubeBrowserSession {
  WebViewYouTubeSession({WebViewController? controller}) {
    if (controller != null) {
      this.controller = controller;
      return;
    }
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    this.controller = WebViewController.fromPlatformCreationParams(params);
  }

  late final WebViewController controller;
  late final WebMediaCommandRunner _commands = WebMediaCommandRunner(
    submitScript: controller.runJavaScript,
    readScript: controller.runJavaScriptReturningResult,
  );
  YouTubeMediaState _media = const YouTubeMediaState();
  int _progress = 0;
  String? _error;
  bool _canGoBack = false;
  bool _disposed = false;
  bool _refreshing = false;
  int _document = 0;
  int _snapshotRevision = -1;
  String? _pauseOnReadyVideoId;
  int _pauseOnReadyDocument = 0;
  Timer? _timer;
  String? _bridge;
  String? _dsp;
  String? _dspAdapter;

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

  @override
  Future<void> start(Uri uri) async {
    if (!isYouTubeBrowserUri(uri)) throw ArgumentError.value(uri);
    _bridge = await rootBundle.loadString('assets/web/transpono_media.js');
    _dsp = await rootBundle.loadString('assets/web/SignalsmithStretch.js');
    _dspAdapter = await rootBundle.loadString(
      'assets/web/transpono_stretch.js',
    );
    if (_disposed) return;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF07121F));
    if (controller.platform is AndroidWebViewController) {
      await AndroidWebViewController.enableDebugging(kDebugMode);
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int value) {
          _progress = value;
          _notify();
        },
        onPageStarted: (_) {
          _document++;
          _snapshotRevision = -1;
          _error = null;
          _media = const YouTubeMediaState();
          _notify();
        },
        onPageFinished: (_) => unawaited(_installBridge()),
        onWebResourceError: (WebResourceError failure) {
          if (failure.isForMainFrame != true) return;
          _error = 'Não foi possível carregar o YouTube. Verifique a ligação.';
          _progress = 100;
          _notify();
        },
        onNavigationRequest: (NavigationRequest request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final Uri? uri = embeddedYouTubeUri(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.toString() != request.url) {
            unawaited(controller.loadRequest(uri));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );
    if (_disposed) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => unawaited(refresh()),
    );
    await controller.loadRequest(uri);
  }

  Future<void> _installBridge() async {
    final int generation = _document;
    try {
      final String? current = await controller.currentUrl();
      final Uri? uri = Uri.tryParse(current ?? '');
      if (_disposed || generation != _document || uri == null) return;
      // Never inject an audio bridge into account/consent pages.
      if (uri.host != 'youtube.com' && !uri.host.endsWith('.youtube.com')) {
        return;
      }
      await controller.runJavaScript(_dsp!);
      if (_disposed || generation != _document) return;
      await controller.runJavaScript(_dspAdapter!);
      if (_disposed || generation != _document) return;
      await controller.runJavaScript(_bridge!);
      await refresh();
    } on Object {
      if (!_disposed && generation == _document) {
        _error = 'O vídeo pode ser reproduzido, mas os controlos de áudio não carregaram. Tente atualizar.';
        _notify();
      }
    }
  }

  /// Public for the on-device integration probe; no media is copied out.
  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    if (_pauseOnReadyVideoId != null && _document < _pauseOnReadyDocument) {
      return;
    }
    _refreshing = true;
    final int generation = _document;
    final String? pausedVideoId = _pauseOnReadyVideoId;
    try {
      final Object result = await controller.runJavaScriptReturningResult(
        pausedVideoId == null
            ? 'JSON.stringify(window.TransponoMedia?.snapshot() || {})'
            : '''(() => {
              const bridge = window.TransponoMedia;
              if (!bridge) return '{}';
              let state = bridge.snapshot();
              if (state.videoId === ${jsonEncode(pausedVideoId)} && state.hasVideo && !state.isAd) {
                const video = document.querySelector('video.html5-main-video') || document.querySelector('video');
                if (video) video.pause();
                state = bridge.snapshot();
                state.restoreReady = !!video && video.readyState >= 2 && !state.playing;
              }
              return JSON.stringify(state);
            })()''',
      );
      dynamic decoded = result;
      // Android may return the JSON string quoted; WKWebView returns its value.
      for (int count = 0; decoded is String && count < 2; count++) {
        decoded = jsonDecode(decoded);
      }
      final bool back = await controller.canGoBack();
      if (_disposed ||
          generation != _document ||
          pausedVideoId != _pauseOnReadyVideoId) {
        return;
      }
      if (decoded is Map<String, dynamic>) _acceptSnapshot(decoded);
      _canGoBack = back;
      _notify();
    } on Object {
      // Navigation temporarily destroys the JS context; the next document
      // installs its own bridge. Keep navigation failures separate from this.
    } finally {
      _refreshing = false;
    }
  }

  void _acceptSnapshot(Map<String, dynamic> state) {
    final revision = state['snapshotRevision'];
    if (revision is! num ||
        !revision.isFinite ||
        revision < 0 ||
        revision > 9007199254740991 ||
        revision != revision.truncateToDouble() ||
        revision <= _snapshotRevision) {
      return;
    }
    _snapshotRevision = revision.toInt();
    final pausedVideoId = _pauseOnReadyVideoId;
    final selectedAnotherVideo =
        pausedVideoId != null &&
        state['videoId'] is String &&
        (state['videoId'] as String).isNotEmpty &&
        state['videoId'] != pausedVideoId;
    if (selectedAnotherVideo) _pauseOnReadyVideoId = null;
    if (pausedVideoId == null ||
        selectedAnotherVideo ||
        state['isAd'] == true ||
        state['restoreReady'] == true) {
      _media = YouTubeMediaState.fromJson(state);
      if (state['restoreReady'] == true) _pauseOnReadyVideoId = null;
    }
  }

  @override
  Future<void> command(String action, [num? value]) async {
    if (_disposed) return;
    final generation = _document;
    bool current() => !_disposed && generation == _document;
    try {
      final state = await _commands.execute(
        action,
        value: value,
        isCurrent: current,
      );
      if (current()) {
        _acceptSnapshot(state);
        _notify();
      }
    } on Object catch (error) {
      if (current() &&
          error is WebMediaCommandException &&
          error.snapshot != null) {
        _acceptSnapshot(error.snapshot!);
        _notify();
      }
      if (action == 'pause' && current()) {
        // Search/consent can precede bridge installation. A global Pause must
        // still silence existing elements and permit normal page navigation.
        await controller
            .runJavaScript('''
          window.TransponoMedia?.command({action:'pause'}).catch(() => {});
          document.querySelectorAll('video,audio').forEach(v => v.pause());
        ''')
            .timeout(const Duration(seconds: 2));
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> openVideo(String videoId) async {
    final Uri uri = _youtubeVideoUri(videoId);
    await command('pause');
    if (_disposed) return;
    _pauseOnReadyVideoId = videoId;
    _pauseOnReadyDocument = _document + 1;
    _media = const YouTubeMediaState();
    _error = null;
    _progress = 0;
    _notify();
    await controller.loadRequest(uri);
  }

  @override
  Future<void> focusVideo() async {
    if (_disposed) return;
    await controller.runJavaScript('''(() => {
      const player = document.querySelector('video.html5-main-video') || document.querySelector('.html5-video-player');
      // The watch player is at the top of the page. Scrolling its sticky video
      // into the centre can instead put YouTube into its small scrolled state.
      // Only move the viewport; do not resize/hide the page's player or controls.
      if (player) window.scrollTo({top: 0, left: 0, behavior: 'instant'});
    })()''');
  }

  @override
  Future<void> search(String query) async {
    await command('pause');
    if (_disposed) return;
    _pauseOnReadyVideoId = null;
    _error = null;
    await controller.loadRequest(youtubeSearchUri(query));
  }

  @override
  Future<void> reload() async {
    _error = null;
    _notify();
    await controller.reload();
  }

  @override
  Future<void> goBack() async {
    await command('pause');
    _pauseOnReadyVideoId = null;
    if (await controller.canGoBack()) await controller.goBack();
  }

  @override
  Widget buildView() =>
      WebViewWidget(key: const Key('youtubeWebView'), controller: controller);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(
      controller
          .runJavaScript(
            'window.TransponoMedia?.dispose(); document.querySelectorAll("video,audio").forEach(v => v.pause());',
          )
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}

class YouTubeBrowserScreen extends StatefulWidget {
  const YouTubeBrowserScreen({super.key, this.initialQuery = '', this.session});

  final String initialQuery;
  final YouTubeBrowserSession? session;

  @override
  State<YouTubeBrowserScreen> createState() => _YouTubeBrowserScreenState();
}

class _YouTubeBrowserScreenState extends State<YouTubeBrowserScreen>
    with WidgetsBindingObserver {
  late final YouTubeBrowserSession _session =
      widget.session ?? WebViewYouTubeSession();
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  late final Widget _browser = _session.buildView();
  String? _startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    final Uri uri = widget.initialQuery.trim().isEmpty
        ? Uri.https('m.youtube.com', '/')
        : youtubeSearchUri(widget.initialQuery);
    unawaited(
      _session.start(uri).catchError((Object _) {
        if (mounted) {
          setState(
            () => _startupError = 'Não foi possível iniciar o navegador.',
          );
        }
      }),
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_session.command('pause').catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    await _perform(() => _session.search(_query.text));
  }

  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível concluir. Tente novamente.'),
          ),
        );
      }
    }
  }

  void _command(String action, [num? value]) =>
      unawaited(_perform(() => _session.command(action, value)));

  @override
  Widget build(BuildContext context) {
    final YouTubeMediaState media = _session.media;
    final String? error = _startupError ?? _session.error;
    final Size size = MediaQuery.sizeOf(context);
    final bool sideControls = size.width >= 600 && size.width > size.height;
    final bool showControls =
        media.hasVideo && MediaQuery.viewInsetsOf(context).bottom == 0;
    return PopScope(
      canPop: !_session.canGoBack,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_perform(_session.goBack));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'YouTube · Transpono',
            style: TextStyle(fontSize: 18),
          ),
          leading: IconButton(
            key: const Key('youtubeClose'),
            tooltip: 'Fechar YouTube',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Página anterior',
              onPressed: _session.canGoBack
                  ? () => _perform(_session.goBack)
                  : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              key: const Key('youtubeReload'),
              tooltip: 'Atualizar',
              onPressed: () => _perform(_session.reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  key: const Key('youtubeSearchInput'),
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
                      key: const Key('youtubeSearchSubmit'),
                      tooltip: 'Pesquisar',
                      onPressed: _search,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
              if (_session.progress < 100 && error == null)
                LinearProgressIndicator(value: _session.progress / 100),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(error, key: const Key('youtubeError')),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: SizedBox(
                        key: const Key('youtubeBrowserViewport'),
                        child: _browser,
                      ),
                    ),
                    if (showControls && sideControls)
                      SizedBox(
                        width: 300,
                        child: SingleChildScrollView(
                          child: _MediaControls(
                            media: media,
                            onCommand: _command,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showControls && !sideControls)
                _MediaControls(media: media, onCommand: _command),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaControls extends StatelessWidget {
  const _MediaControls({required this.media, required this.onCommand});
  final YouTubeMediaState media;
  final void Function(String, [num?]) onCommand;

  static String time(double value) {
    final int seconds = value.floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = !media.isAd;
    final bool pitchReady = enabled && media.pitchStatus != 'loading';
    return Container(
      key: const Key('youtubeMediaControls'),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1B2F),
        border: Border(top: BorderSide(color: Color(0xFF20384E))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            media.isAd ? 'Anúncio · aguarde o vídeo' : media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                key: const Key('youtubePitchDown'),
                tooltip: 'Diminuir tom',
                onPressed: pitchReady && media.pitch > -12
                    ? () => onCommand('pitch', media.pitch - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('youtubePitchReset'),
                  onPressed: enabled ? () => onCommand('pitch', 0) : null,
                  child: Text(
                    'TOM ${media.pitch > 0 ? '+' : ''}${media.pitch.toStringAsFixed(0)} st',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                key: const Key('youtubePitchUp'),
                tooltip: 'Aumentar tom',
                onPressed: pitchReady && media.pitch < 12
                    ? () => onCommand('pitch', media.pitch + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                key: const Key('youtubeSpeed'),
                enabled: enabled,
                tooltip: 'Velocidade',
                onSelected: (double value) => onCommand('speed', value),
                itemBuilder: (_) => <PopupMenuEntry<double>>[
                  for (final double value in <double>[0.5, 0.75, 1, 1.25, 1.5])
                    PopupMenuItem(
                      value: value,
                      child: Text('${value.toStringAsFixed(2)}×'),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '${media.speed.toStringAsFixed(2)}×',
                    style: const TextStyle(color: Color(0xFF00E5FF)),
                  ),
                ),
              ),
            ],
          ),
          if (media.pitchMessage.isNotEmpty)
            Text(
              media.pitchMessage,
              key: const Key('youtubePitchStatus'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFB4C4D5)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                '${time(media.position)} / ${time(media.duration)}',
                style: const TextStyle(fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Voltar 10 segundos',
                onPressed: enabled ? () => onCommand('seekBy', -10) : null,
                icon: const Icon(Icons.replay_10),
              ),
              IconButton(
                key: const Key('youtubePlayPause'),
                tooltip: media.muted
                    ? 'Ativar som'
                    : media.playing
                    ? 'Pausar'
                    : 'Reproduzir',
                onPressed: () =>
                    onCommand(media.muted ? 'unmute' : 'playPause'),
                icon: Icon(
                  media.muted
                      ? Icons.volume_up
                      : media.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 34,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              IconButton(
                tooltip: 'Avançar 10 segundos',
                onPressed: enabled ? () => onCommand('seekBy', 10) : null,
                icon: const Icon(Icons.forward_10),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  key: const Key('youtubeMarkA'),
                  onPressed: enabled && media.duration > 0
                      ? () => onCommand('markA')
                      : null,
                  child: Text(
                    media.loopA == null
                        ? 'Marcar A'
                        : 'A ${time(media.loopA!)}',
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('youtubeMarkB'),
                  onPressed: enabled && media.loopA != null
                      ? () => onCommand('markB')
                      : null,
                  child: Text(
                    media.loopB == null
                        ? 'Marcar B'
                        : 'B ${time(media.loopB!)}',
                  ),
                ),
              ),
              IconButton(
                tooltip: media.loopEnabled
                    ? 'Desativar repetição'
                    : 'Ativar repetição',
                onPressed: enabled && media.loopB != null
                    ? () => onCommand('toggleLoop')
                    : null,
                icon: Icon(
                  Icons.repeat,
                  color: media.loopEnabled ? const Color(0xFF00E5FF) : null,
                ),
              ),
              IconButton(
                tooltip: 'Limpar A/B',
                onPressed: media.loopA != null
                    ? () => onCommand('clearLoop')
                    : null,
                icon: const Icon(Icons.clear, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
