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
    this.keyRoot,
    this.keyMode = '',
    this.keyStatus = 'waiting',
    this.audioEffects = const <String, double>{},
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
    final rawEffects = json['audioEffects'];
    const effectLimits = <String, (double, double)>{
      'bass': (-12, 12),
      'mid': (-12, 12),
      'treble': (-12, 12),
      'gain': (-12, 6),
      'chorus': (0, .5),
      'feedback': (0, .55),
      'delay': (0, .35),
      'reverb': (0, .4),
    };
    final effects = <String, double>{};
    for (final entry in effectLimits.entries) {
      final value = rawEffects is Map ? rawEffects[entry.key] : null;
      effects[entry.key] = value is num && value.isFinite
          ? value.toDouble().clamp(entry.value.$1, entry.value.$2)
          : 0;
    }
    return YouTubeMediaState(
      audioEffects: Map<String, double>.unmodifiable(effects),
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
      keyRoot: (counter('keyRoot') ?? -1) <= 11 ? counter('keyRoot') : null,
      keyMode: string('keyMode'),
      keyStatus: string('keyStatus'),
    );
  }

  final String videoId, title, pitchStatus, pitchMessage;
  final bool hasVideo, playing, muted, loopEnabled, isAd;
  final bool loopEventsSupported, playbackReady;
  final int loopCount, loopEpoch;
  final double position, duration, speed, pitch;
  final double? loopA, loopB;
  final int? keyRoot;
  final String keyMode, keyStatus;
  final Map<String, double> audioEffects;
}

/// Observation of the *player clock*, not the time its sound reaches a speaker.
/// The browser's performance.now() has a different origin from Dart's clock;
/// the host midpoint only brackets the JavaScript evaluation, within half RTT.
@immutable
class YouTubeTimelineSample {
  const YouTubeTimelineSample({
    required this.videoId,
    required this.revision,
    required this.epoch,
    required this.positionMs,
    required this.speed,
    required this.browserTimeMs,
    required this.hostMidpointUs,
    required this.uncertaintyMs,
  });

  final String videoId;
  final int revision, epoch, hostMidpointUs;
  final double positionMs, speed, browserTimeMs, uncertaintyMs;
}

/// Validates a single video's sampled timeline. No media samples are captured.
class YouTubeTimelineTracker {
  YouTubeTimelineSample? _latest;
  YouTubeTimelineSample? get latest => _latest;
  int epoch = 0;
  int _revision = -1;
  String? _videoId;
  int? _sourceEpoch, _seekEpoch, _rateEpoch;
  double? _speed;

  void reset() {
    _latest = null;
    _revision = -1;
    _videoId = null;
    _sourceEpoch = _seekEpoch = _rateEpoch = null;
    _speed = null;
    epoch++;
  }

  /// Without an RTT bracket, a push/command can invalidate but cannot sample.
  bool observe(Map<String, dynamic> state, {int? startUs, int? endUs}) {
    int? counter(String key) {
      final value = state[key];
      return value is num &&
              value.isFinite &&
              value >= 0 &&
              value <= 9007199254740991 &&
              value == value.truncateToDouble()
          ? value.toInt()
          : null;
    }

    double? finite(String key) {
      final value = state[key];
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    final revision = counter('snapshotRevision');
    if (revision == null || revision <= _revision) return false;
    _revision = revision;
    final id = state['videoId'];
    final source = counter('timelineSourceEpoch');
    final seek = counter('timelineSeekEpoch');
    final rate = counter('timelineRateEpoch');
    final browserTime = finite('sampleTimeMs');
    final position = finite('position');
    final duration = finite('duration');
    final speed = finite('speed');
    final validFields =
        id is String &&
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) &&
        source != null &&
        seek != null &&
        rate != null &&
        browserTime != null &&
        browserTime >= 0 &&
        position != null &&
        position >= 0 &&
        duration != null &&
        duration > 0 &&
        position <= duration + 1 &&
        speed != null &&
        speed > 0 &&
        speed <= 4;
    if (!validFields) {
      if (_latest != null) epoch++;
      _latest = null;
      return false;
    }
    final videoId = id;
    final sourceEpoch = source;
    final seekEpoch = seek;
    final rateEpoch = rate;
    final sampleTimeMs = browserTime;
    final positionSeconds = position;
    final playbackSpeed = speed;
    final changedContext =
        _videoId != videoId ||
        _sourceEpoch != sourceEpoch ||
        _seekEpoch != seekEpoch ||
        _rateEpoch != rateEpoch ||
        (_speed != null && _speed != playbackSpeed);
    if (changedContext) {
      _latest = null;
      epoch++;
    }
    _videoId = videoId;
    _sourceEpoch = sourceEpoch;
    _seekEpoch = seekEpoch;
    _rateEpoch = rateEpoch;
    _speed = playbackSpeed;
    // A changed source, seek, or rate begins a new segment; do not treat its
    // first observation as a continuation or an immediately usable anchor.
    if (changedContext) return false;
    if (state['hasVideo'] != true ||
        state['isAd'] == true ||
        state['seeking'] == true ||
        state['playbackReady'] != true ||
        state['playing'] != true) {
      if (_latest != null) epoch++;
      _latest = null;
      return false;
    }
    if (startUs == null || endUs == null) return false;
    final rttUs = endUs - startUs;
    if (startUs < 0 || rttUs < 0 || rttUs > 250000) {
      if (_latest != null) epoch++;
      _latest = null;
      return false;
    }
    final midpoint = startUs + rttUs ~/ 2;
    final previous = _latest;
    if (previous != null) {
      if (sampleTimeMs < previous.browserTimeMs ||
          midpoint <= previous.hostMidpointUs) {
        epoch++;
        _latest = null;
        return false;
      }
      final predicted =
          previous.positionMs +
          (midpoint - previous.hostMidpointUs) / 1000 * previous.speed;
      final tolerance = 200 + previous.uncertaintyMs + rttUs / 2000;
      if ((positionSeconds * 1000 - predicted).abs() > tolerance) {
        epoch++;
        _latest = null;
        return false;
      }
    }
    _latest = YouTubeTimelineSample(
      videoId: videoId,
      revision: revision,
      epoch: epoch,
      positionMs: positionSeconds * 1000,
      speed: playbackSpeed,
      browserTimeMs: sampleTimeMs,
      hostMidpointUs: midpoint,
      uncertaintyMs: rttUs / 2000,
    );
    return true;
  }
}

/// The browser has one media element/graph; Flutter only issues commands and
/// observes acknowledgements. This seam also permits network-free UI tests.
abstract class YouTubeBrowserSession extends ChangeNotifier {
  YouTubeMediaState get media;
  int get progress;
  String? get error;

  /// Ready to reveal the first page, not just finished downloading its shell.
  bool get contentReady => progress >= 100 || error != null;
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
  final YouTubeTimelineTracker _timeline = YouTubeTimelineTracker();
  final Stopwatch _timelineClock = Stopwatch()..start();
  YouTubeTimelineSample? get timeline => _timeline.latest;
  int _progress = 0;
  bool _contentReady = false;
  bool _checkingContent = false;
  String? _error;
  bool _canGoBack = false;
  bool _disposed = false;
  bool _refreshing = false;
  int _document = 0;
  int _snapshotRevision = -1;
  String? _pauseOnReadyVideoId;
  String? _focusOnReadyVideoId;
  int _pauseOnReadyDocument = 0;
  Timer? _timer;
  String? _bridge;
  String? _dsp;
  String? _dspAdapter;
  String? _keyDetector;

  @override
  YouTubeMediaState get media => _media;

  /// Local monotonic epoch for timeline brackets; not Android System.nanoTime.
  int get timelineClockUs => _timelineClock.elapsedMicroseconds;
  @override
  int get progress => _progress;
  @override
  bool get contentReady => _contentReady || _error != null;
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
    _keyDetector = await rootBundle.loadString(
      'assets/web/transpono_key_detector.js',
    );
    _dsp = await rootBundle.loadString('assets/web/SignalsmithStretch.js');
    _dspAdapter = await rootBundle.loadString(
      'assets/web/transpono_stretch.js',
    );
    if (_disposed) return;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF080809));
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
          _timeline.reset();
          _contentReady = false;
          _snapshotRevision = -1;
          _error = null;
          _media = const YouTubeMediaState();
          _notify();
        },
        onPageFinished: (_) {
          unawaited(_installBridge());
          unawaited(_checkContentReady());
        },
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
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(refresh());
      unawaited(_checkContentReady());
    });
    await controller.loadRequest(uri);
  }

  Future<void> _checkContentReady() async {
    if (_disposed || _contentReady || _checkingContent || _progress < 100) {
      return;
    }
    _checkingContent = true;
    final document = _document;
    try {
      final result = await controller.runJavaScriptReturningResult('''
        (() => {
          const body = document.body;
          if (!body || document.readyState !== 'complete') return false;
          const hasVideo = !!body.querySelector('a[href*="/watch"]');
          const hasReadablePage = (body.innerText || '').trim().length > 150;
          return hasVideo || hasReadablePage;
        })()
      ''');
      if (_disposed || document != _document) return;
      if (result == true || result.toString() == 'true') {
        _contentReady = true;
        _notify();
      }
    } on Object {
      // The page may still be replacing its document; the next poll retries.
    } finally {
      _checkingContent = false;
    }
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
      await controller.runJavaScript(_keyDetector!);
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
      final int startUs = _timelineClock.elapsedMicroseconds;
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
      final int endUs = _timelineClock.elapsedMicroseconds;
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
      if (decoded is Map<String, dynamic>) {
        _acceptSnapshot(decoded, startUs: startUs, endUs: endUs);
      }
      if (_focusOnReadyVideoId != null &&
          decoded is Map<String, dynamic> &&
          decoded['videoId'] == _focusOnReadyVideoId &&
          decoded['hasVideo'] == true &&
          decoded['isAd'] != true) {
        // A restored watch page can retain YouTube's own scroll position and
        // display its small sticky player. Focus once when its video exists;
        // never keep pulling the page back while the user browses it.
        try {
          await focusVideo();
          if (generation == _document &&
              decoded['videoId'] == _focusOnReadyVideoId) {
            _focusOnReadyVideoId = null;
          }
        } on Object {
          // A navigation can replace the JS context; the next refresh retries.
        }
      }
      _canGoBack = back;
      _notify();
    } on Object {
      // Navigation temporarily destroys the JS context; the next document
      // installs its own bridge. Keep navigation failures separate from this.
    } finally {
      _refreshing = false;
    }
  }

  void _acceptSnapshot(Map<String, dynamic> state, {int? startUs, int? endUs}) {
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
    if (selectedAnotherVideo) {
      _pauseOnReadyVideoId = null;
      _focusOnReadyVideoId = null;
    }
    if (pausedVideoId == null ||
        selectedAnotherVideo ||
        state['isAd'] == true ||
        state['restoreReady'] == true) {
      _media = YouTubeMediaState.fromJson(state);
      _timeline.observe(state, startUs: startUs, endUs: endUs);
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
    _timeline.reset();
    _pauseOnReadyVideoId = videoId;
    _focusOnReadyVideoId = videoId;
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
    _focusOnReadyVideoId = null;
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
    _focusOnReadyVideoId = null;
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
