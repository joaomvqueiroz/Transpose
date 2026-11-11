import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'home_button_visibility.dart';

import 'package:flutter/services.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'youtube_native_audio_follower.dart';
import 'youtube_search.dart';
import 'web_media_command.dart';
import 'studio_appearance.dart';

/// Appearance-only override for the embedded mobile site. It never touches
/// video frames, playback or audio, and is reapplied after page navigation.
String youtubeAppearanceScript(StudioAppearanceMode mode) {
  final dark = mode != StudioAppearanceMode.light;
  return '''
    (() => {
      const host = location.hostname.toLowerCase();
      if (host !== 'youtube.com' && !host.endsWith('.youtube.com')) return;
      const dark = $dark;
      const root = document.documentElement;
      const desired = dark ? 'dark' : 'light';
      root.setAttribute('data-transpono-theme', desired);
      root.toggleAttribute('dark', dark);
      root.style.colorScheme = desired;
      // YouTube keeps its own "Aparência" choice in the PREF cookie (f6, hex
      // flags: 0x400 dark, 0x80000 light) and only takes it when a page
      // loads. A page loaded with the other theme keeps that theme's text
      // colours, and the overrides below only repaint part of it (white
      // panels in dark, light text on white). So: make the cookie follow the
      // app, and reload any page that was loaded with the other theme.
      try {
        const found = document.cookie.match(/(?:^|; )PREF=([^;]*)/);
        const parts = found ? found[1].split('&').filter(Boolean) : [];
        let seen = false;
        let cookieTheme = '';
        const next = parts.map(part => {
          if (part.indexOf('f6=') !== 0) return part;
          seen = true;
          const flags = parseInt(part.slice(3), 16) || 0;
          cookieTheme = (flags & 0x400) ? 'dark'
            : (flags & 0x80000) ? 'light' : '';
          const want = dark
            ? ((flags & ~0x80000) | 0x400)
            : ((flags & ~0x400) | 0x80000);
          return 'f6=' + (want >>> 0).toString(16);
        });
        if (!seen) next.unshift('f6=' + (dark ? '400' : '80000'));
        const value = next.join('&');
        // The theme this page was loaded with: YouTube's own record of it,
        // or else what the cookie said the first time this page was seen
        // (the other page of the app may have changed the cookie since).
        let pageTheme = '';
        try {
          const context = window.ytcfg && window.ytcfg.get &&
            window.ytcfg.get('INNERTUBE_CONTEXT');
          const theme = context && context.client &&
            context.client.userInterfaceTheme;
          if (theme === 'USER_INTERFACE_THEME_DARK') pageTheme = 'dark';
          if (theme === 'USER_INTERFACE_THEME_LIGHT') pageTheme = 'light';
        } catch (_) {}
        if (!pageTheme) {
          if (typeof window.__transponoPageTheme !== 'string') {
            window.__transponoPageTheme = cookieTheme;
          }
          pageTheme = window.__transponoPageTheme;
        }
        let ready = !!found && found[1] === value;
        if (!ready) {
          document.cookie = 'PREF=' + value +
            '; domain=.youtube.com; path=/; max-age=63072000; secure';
          const written = document.cookie.match(/(?:^|; )PREF=([^;]*)/);
          ready = !!written && written[1] === value;
        }
        if (ready && pageTheme !== desired) {
          // Never a loop: at most two reloads for the same theme.
          let tries = 0;
          try {
            const mark = (sessionStorage.getItem('transponoThemeReload') || '')
              .split(':');
            tries = mark[0] === desired ? (parseInt(mark[1], 10) || 0) : 0;
            sessionStorage.setItem(
              'transponoThemeReload', desired + ':' + (tries + 1));
          } catch (_) { tries = window.__transponoThemeTried ? 2 : 0; }
          window.__transponoThemeTried = true;
          if (tries < 2) {
            // A video being watched comes back at the same moment.
            const video = document.querySelector('video.html5-main-video');
            const watching = location.pathname === '/watch' && !!video &&
              video.currentTime > 1 && !video.ended;
            if (watching) {
              const url = new URL(location.href);
              url.searchParams.set('t', Math.floor(video.currentTime) + 's');
              location.replace(url.href);
            } else {
              location.reload();
            }
            return;
          }
        }
      } catch (_) {}
      for (const app of document.querySelectorAll('ytm-app, ytd-app')) {
        app.toggleAttribute('dark', dark);
      }
      let style = document.getElementById('transpono-youtube-appearance');
      if (!style) {
        style = document.createElement('style');
        style.id = 'transpono-youtube-appearance';
        (document.head || root).appendChild(style);
      }
      style.textContent = `
        html[data-transpono-theme="dark"],
        html[data-transpono-theme="dark"] ytm-app {
          --yt-spec-base-background: #0f0f0f;
          --yt-spec-raised-background: #272727;
          --yt-spec-menu-background: #272727;
          --yt-spec-text-primary: #f1f1f1;
          --yt-spec-text-secondary: #aaaaaa;
        }
        html[data-transpono-theme="light"],
        html[data-transpono-theme="light"] ytm-app {
          --yt-spec-base-background: #ffffff;
          --yt-spec-raised-background: #f2f2f2;
          --yt-spec-menu-background: #ffffff;
          --yt-spec-text-primary: #0f0f0f;
          --yt-spec-text-secondary: #606060;
        }
        html[data-transpono-theme="dark"] body,
        html[data-transpono-theme="dark"] ytm-app {
          background-color: #0f0f0f !important;
          color: #f1f1f1 !important;
        }
        html[data-transpono-theme="light"] body,
        html[data-transpono-theme="light"] ytm-app {
          background-color: #ffffff !important;
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="dark"] ytm-mobile-topbar-renderer,
        html[data-transpono-theme="dark"] ytm-feed-filter-chip-bar-renderer,
        html[data-transpono-theme="dark"] ytm-pivot-bar-renderer,
        html[data-transpono-theme="dark"] .ytmDrawerLayoutContainerDrawerLayout {
          background-color: #0f0f0f !important;
          color: #f1f1f1 !important;
        }
        html[data-transpono-theme="light"] ytm-mobile-topbar-renderer,
        html[data-transpono-theme="light"] ytm-feed-filter-chip-bar-renderer,
        html[data-transpono-theme="light"] ytm-pivot-bar-renderer,
        html[data-transpono-theme="light"] .ytmDrawerLayoutContainerDrawerLayout {
          background-color: #ffffff !important;
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="dark"] ytm-mobile-topbar-renderer c3-icon,
        html[data-transpono-theme="dark"] ytm-mobile-topbar-renderer button,
        html[data-transpono-theme="dark"] ytm-pivot-bar-renderer * {
          color: #f1f1f1 !important;
        }
        html[data-transpono-theme="light"] ytm-mobile-topbar-renderer c3-icon,
        html[data-transpono-theme="light"] ytm-mobile-topbar-renderer button,
        html[data-transpono-theme="light"] ytm-pivot-bar-renderer * {
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="dark"] .chip-container {
          background-color: #272727 !important;
          color: #f1f1f1 !important;
        }
        html[data-transpono-theme="light"] .chip-container {
          background-color: #f2f2f2 !important;
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="dark"] ytm-chip-cloud-chip-renderer[aria-selected="true"] .chip-container {
          background-color: #f1f1f1 !important;
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="dark"] ytm-chip-cloud-chip-renderer[aria-selected="true"] .chip-container * {
          color: #0f0f0f !important;
        }
        html[data-transpono-theme="light"] ytm-chip-cloud-chip-renderer[aria-selected="true"] .chip-container {
          background-color: #0f0f0f !important;
          color: #ffffff !important;
        }
        html[data-transpono-theme="light"] ytm-chip-cloud-chip-renderer[aria-selected="true"] .chip-container * {
          color: #ffffff !important;
        }
      `;
      if (window.__transponoThemeObserver) window.__transponoThemeObserver.disconnect();
      window.__transponoThemeObserver = new MutationObserver(() => {
        if (root.hasAttribute('dark') !== dark) root.toggleAttribute('dark', dark);
      });
      window.__transponoThemeObserver.observe(root, {
        attributes: true, attributeFilter: ['dark']
      });
    })();
  ''';
}

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

  YouTubeMediaState copyWith({
    bool? muted,
    double? pitch,
    String? pitchStatus,
    String? pitchMessage,
    Map<String, double>? audioEffects,
  }) => YouTubeMediaState(
    videoId: videoId,
    title: title,
    hasVideo: hasVideo,
    playing: playing,
    muted: muted ?? this.muted,
    position: position,
    duration: duration,
    speed: speed,
    pitch: pitch ?? this.pitch,
    pitchStatus: pitchStatus ?? this.pitchStatus,
    pitchMessage: pitchMessage ?? this.pitchMessage,
    loopA: loopA,
    loopB: loopB,
    loopEnabled: loopEnabled,
    isAd: isAd,
    loopCount: loopCount,
    loopEpoch: loopEpoch,
    loopEventsSupported: loopEventsSupported,
    playbackReady: playbackReady,
    keyRoot: keyRoot,
    keyMode: keyMode,
    keyStatus: keyStatus,
    audioEffects: audioEffects ?? this.audioEffects,
  );

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

  /// Plays a watch page (YouTube or YouTube Music) chosen in the browse
  /// page of the two-page mode.
  Future<void> playWatch(Uri watch) => start(watch);
  Future<void> focusVideo() async {}

  /// Closes the site's search field (and its suggestions) if it is open.
  Future<void> leaveSearch() async {}

  /// Opens one of the bottom bar's pages: "home", "shorts" or "you" on
  /// YouTube; "home", "explore" or "library" on YouTube Music.
  ///
  /// With [keepPlace], a page that is already the one being shown is left
  /// exactly as it is (no scroll back to the top, no reload).
  Future<void> openTab(String name, {bool keepPlace = false}) async {}

  /// YouTube Music's player: opens the song tab [index] (A seguir, Letra,
  /// ...), or with -1 goes back to the player.
  /// [top] is where its panel starts on the page (under the app's tabs).
  Future<void> openSongTab(int index, {double top = 0}) async {}

  /// YouTube Music's next (or previous) song, from the notification.
  Future<void> musicSkip({required bool forward}) async {}

  /// The studio's adjustments opened ([shown]) or closed: on opening, the
  /// page's video list is scrolled back to the player at the top; on
  /// closing, it returns to where the user was.
  Future<void> adjustmentsShown(bool shown) async {}

  /// The user touched the app outside the page: the page's text field gives
  /// up its focus, so touching it again opens the keyboard.
  Future<void> releaseFocus() async {}
  Future<void> setAppearanceMode(StudioAppearanceMode mode) async {}
  Future<void> search(String query);
  Future<void> reload();
  Future<void> goBack();
  Future<void> command(String action, [num? value]);
  Widget buildView();

  // Two-page mode (the app's own mini player): one session plays (it keeps
  // the audio bridge), another one browses and searches.

  /// This session only browses: a video chosen here goes to [onOpenRequest]
  /// and does not play here.
  bool browseOnly = false;

  /// The page's drag-down on the video asks the app (via
  /// [onMinimizeRequest]) to shrink it, instead of its own CSS mini player.
  bool appMini = false;

  /// This session's page state (search field focus, scroll direction)
  /// drives the app's floating controls.
  bool publishesPageState = true;

  /// True only while Flutter places this player WebView in its small overlay.
  /// The page then renders just the video into the WebView's real viewport.
  bool appMiniSurface = false;

  /// A Short started playing in a [browseOnly] page, in the site's own
  /// vertical player (Shorts are not handed to the player page).
  VoidCallback? onShortsPlaying;

  /// A video chosen in a [browseOnly] page.
  void Function(Uri watch)? onOpenRequest;

  /// The video was dragged down in an [appMini] page.
  VoidCallback? onMinimizeRequest;

  /// Applies [browseOnly] and [appMini] to the current page.
  Future<void> applyPageRoles() async {}

  Future<void> setAppMiniSurface(bool visible) async {
    appMiniSurface = visible;
    await applyPageRoles();
  }
}

Uri _youtubeVideoUri(String videoId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
    throw ArgumentError.value(videoId, 'videoId', 'Invalid YouTube video ID');
  }
  return Uri.https('m.youtube.com', '/watch', <String, String>{'v': videoId});
}

class WebViewYouTubeSession extends YouTubeBrowserSession {
  /// The page's picture is never seen (Spotify's sound): lowest quality.
  bool lowVideo = false;
  int _pollTick = 0;

  WebViewYouTubeSession({WebViewController? controller}) {
    if (controller != null) {
      this.controller = controller;
      return;
    }
    if (GeckoEngine.isAvailable) {
      // iPhone builds with the Gecko engine kit: YouTube plays through MSE,
      // so the same page-local Web Audio bridge as on Android can attach.
      final GeckoWebViewController gecko = GeckoWebViewController();
      _gecko = gecko;
      this.controller = WebViewController.fromPlatform(gecko);
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
  GeckoWebViewController? _gecko;

  /// Started on SoundCloud (the SoundCloud choice) rather than YouTube.
  bool _soundCloud = false;

  /// Whether this session renders with Gecko instead of the platform WebView.
  bool get usesGecko => _gecko != null;
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
  StudioAppearanceMode _appearanceMode = StudioAppearanceMode.dark;

  /// iPhone WebKit cannot feed YouTube's HLS audio to Web Audio, so pitch and
  /// effects are rendered by a native copy of the audio track instead.
  late final NativeYouTubeAudioFollower? _native =
      defaultTargetPlatform == TargetPlatform.iOS && _gecko == null
      ? NativeYouTubeAudioFollower(
          setWebMuted: _setWebMuted,
          onChanged: _notify,
        )
      : null;

  Future<void> _setWebMuted(bool muted) => controller.runJavaScript('''(() => {
    const video = document.querySelector('video.html5-main-video') || document.querySelector('video');
    if (video) video.muted = $muted;
  })()''');

  @override
  Future<void> setAppearanceMode(StudioAppearanceMode mode) async {
    if (_disposed || _appearanceMode == mode) return;
    _appearanceMode = mode;
    try {
      await controller.setBackgroundColor(
        mode == StudioAppearanceMode.light
            ? Colors.white
            : const Color(0xFF080809),
      );
    } on Object {
      // The document may be navigating; its next load reapplies the theme.
    }
    await _applyAppearance();
  }

  Future<void> _applyAppearance() async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(youtubeAppearanceScript(_appearanceMode));
    } on Object {
      // A navigation may replace the document; onPageFinished retries.
    }
  }

  @override
  YouTubeMediaState get media => _native?.overlay(_media) ?? _media;

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
    if (!isYouTubeBrowserUri(uri) && !isSoundCloudBrowserUri(uri)) {
      throw ArgumentError.value(uri);
    }
    _soundCloud = isSoundCloudBrowserUri(uri);
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
    await controller.setBackgroundColor(
      _appearanceMode == StudioAppearanceMode.light
          ? Colors.white
          : const Color(0xFF080809),
    );
    if (controller.platform is AndroidWebViewController) {
      // Page inspection from a computer: debug builds, or a build made on
      // purpose with --dart-define=TRANSPONO_WEB_DEBUG=true.
      await AndroidWebViewController.enableDebugging(
        kDebugMode || const bool.fromEnvironment('TRANSPONO_WEB_DEBUG'),
      );
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    await controller.setNavigationDelegate(
      _navigationDelegate(
        onProgress: (int value) {
          _progress = value;
          _notify();
        },
        onPageStarted: (_) {
          _document++;
          _timeline.reset();
          _contentReady = false;
          _snapshotRevision = -1;
          // A new document counts its requests from zero.
          _minimizeSeq = null;
          _homeSeq = null;
          _openSeq = null;
          _error = null;
          _media = const YouTubeMediaState();
          _notify();
        },
        onPageFinished: (_) {
          unawaited(_applyAppearance());
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
      // A page that only browses (the player is another page) is read
      // less often: every call to a page costs the phone's main thread.
      if (browseOnly && _pollTick++ % 3 != 0) return;
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
    // Gecko's script relay can connect a moment after the page reports it
    // finished; give it a few seconds before treating the bridge as failed.
    final int attempts = usesGecko ? 8 : 1;
    String step = 'url';
    for (int attempt = 1; ; attempt++) {
      try {
        step = 'url';
        final String? current = await controller.currentUrl();
        final Uri? uri = Uri.tryParse(current ?? '');
        if (_disposed || generation != _document || uri == null) return;
        // Never inject an audio bridge into account/consent pages.
        final bool youtubePage =
            uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com');
        if (!youtubePage && !isSoundCloudBrowserUri(uri)) return;
        // The browse page of the two-page mode never processes audio: only
        // the page bridge (page state, video hand-over), no pitch engine.
        if (!browseOnly) {
          step = 'dsp';
          await controller.runJavaScript(_dsp!);
          if (_disposed || generation != _document) return;
          step = 'stretch';
          await controller.runJavaScript(_dspAdapter!);
          if (_disposed || generation != _document) return;
          step = 'key';
          await controller.runJavaScript(_keyDetector!);
          if (_disposed || generation != _document) return;
        }
        step = 'media';
        await controller.runJavaScript(_bridge!);
        await applyPageRoles();
        await refresh();
        return;
      } on GeckoJavaScriptException catch (failure) {
        final bool noContext =
            failure.message.startsWith('NO_CONTEXT') ||
            failure.message == 'JS timeout';
        if (noContext && attempt < attempts) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (_disposed || generation != _document) return;
          continue;
        }
        _bridgeFailed(generation, '$step: ${failure.message}');
        return;
      } on Object catch (failure) {
        _bridgeFailed(generation, '$step: $failure');
        return;
      }
    }
  }

  void _bridgeFailed(int generation, String reason) {
    if (_disposed || generation != _document) return;
    final String detail = reason.length > 160
        ? '${reason.substring(0, 160)}…'
        : reason;
    _error =
        'O vídeo pode ser reproduzido, mas os controlos de áudio não carregaram. '
        'Tente atualizar. ($detail)';
    _notify();
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
        // A video chosen in the browse page starts without a tap here, so
        // YouTube starts it muted: give it its sound once it is playing.
        final String? unmute = _unmuteOnReadyVideoId;
        if (unmute != null &&
            decoded['videoId'] == unmute &&
            decoded['hasVideo'] == true &&
            decoded['isAd'] != true) {
          if (decoded['muted'] == true) {
            unawaited(command('unmute'));
          } else if (decoded['playing'] == true) {
            _unmuteOnReadyVideoId = null;
          }
        }
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
    if (!browseOnly && state.containsKey('songTabs')) {
      final SongTabs? tabs = songTabsFromState(state['songTabs']);
      if (!sameSongTabs(tabs, musicSongTabs.value)) musicSongTabs.value = tabs;
    }
    if (publishesPageState) {
      pageInputFocused.value = state['inputFocused'] == true;
      pageScrolledDown.value = state['pageScroll'] == 'down';
      pageYouTubeBars.value = youTubeBarsFromState(state['bars']);
      if (pendingPageSearch.value && pageYouTubeBars.value?.topFree == true) {
        pendingPageSearch.value = false;
        unawaited(_openPageSearch());
      }
    }
    if (!browseOnly) {
      pageUnmutePrompt.value =
          _native == null &&
          state['hasVideo'] == true &&
          state['muted'] == true;
    }
    // Each request carries a counter (per page); act on a new one once.
    final Object? minimizeSeq = state['minimizeSeq'];
    if (minimizeSeq is num && minimizeSeq.toInt() != _minimizeSeq) {
      final bool first = _minimizeSeq == null;
      _minimizeSeq = minimizeSeq.toInt();
      if (!first || _minimizeSeq! > 0) onMinimizeRequest?.call();
    }
    final Object? homeSeq = state['homeSeq'];
    if (homeSeq is num && homeSeq.toInt() != _homeSeq) {
      final bool first = _homeSeq == null;
      _homeSeq = homeSeq.toInt();
      if (!first || _homeSeq! > 0) pageHomeRequests.value++;
    }
    final Object? openSeq = state['openSeq'];
    final Object? asked = state['openRequest'];
    if (openSeq is num && openSeq.toInt() != _openSeq) {
      final bool first = _openSeq == null;
      _openSeq = openSeq.toInt();
      if (browseOnly &&
          (!first || _openSeq! > 0) &&
          asked is String &&
          asked.isNotEmpty) {
        final Uri? watch = Uri.tryParse(asked);
        if (watch != null && isYouTubeBrowserUri(watch)) {
          onOpenRequest?.call(watch);
        }
      }
    }
    if (browseOnly) {
      // A video started here anyway (YouTube Music plays in its own bar, a
      // link the tap interception missed): hand it to the player page and
      // stop it here; leave a watch page so the list stays behind.
      final Object? id = state['videoId'];
      // Back on a page without a video: the same one may be chosen again.
      if (id is! String || id.isEmpty) _handedOffVideoId = null;
      if (state['shortsPage'] == true) {
        // Shorts stay here, vertical; the other page's video gives way.
        if (id is String &&
            id.isNotEmpty &&
            state['playing'] == true &&
            id != _shortsVideoId) {
          _shortsVideoId = id;
          onShortsPlaying?.call();
        }
      } else if (id is String &&
          id.isNotEmpty &&
          state['hasVideo'] == true &&
          state['isAd'] != true &&
          id != _handedOffVideoId) {
        _shortsVideoId = null;
        _handedOffVideoId = id;
        unawaited(_handOffVideo(id));
      }
    }
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
      final native = _native;
      if (native != null) unawaited(native.sync(_media));
      if (state['restoreReady'] == true) _pauseOnReadyVideoId = null;
    }
  }

  @override
  Future<void> openTab(String name, {bool keepPlace = false}) async {
    if (_disposed ||
        !const {'home', 'shorts', 'you', 'explore', 'library'}.contains(name)) {
      return;
    }
    try {
      await controller.runJavaScript('''(() => {
          if (window.location.hostname === 'music.youtube.com') {
            const path = {home: '/', explore: '/explore', library: '/library'}['$name'];
            if (path && window.location.pathname !== path) window.location.href = path;
            return;
          }
          const here = window.location.pathname;
          const shown = {
            home: here === '/',
            shorts: here.indexOf('/shorts') === 0,
            you: here === '/feed/library',
          }['$name'];
          if ($keepPlace && shown) return;
          const tab = {home: 'pivot-w2w', shorts: 'pivot-shorts', you: 'pivot-you'}['$name'];
          const target = document.querySelector('ytm-pivot-bar-renderer .' + tab);
          if (target) { target.click(); return; }
          window.location.href =
            {home: '/', shorts: '/shorts/', you: '/feed/library'}['$name'];
        })()''');
    } on Object {
      // The page changed meanwhile.
    }
  }

  @override
  Future<void> musicSkip({required bool forward}) async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(
        'if (window.__transponoMusicSkip) window.__transponoMusicSkip($forward);',
      );
    } on Object {
      // The page changed meanwhile.
    }
  }

  @override
  Future<void> openSongTab(int index, {double top = 0}) async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(
        'if (window.__transponoSongTab) '
        'window.__transponoSongTab($index, ${top.round()});',
      );
    } on Object {
      // The page changed meanwhile.
    }
  }

  @override
  Future<void> leaveSearch() async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(
        'if (window.__transponoLeaveSearch) window.__transponoLeaveSearch();',
      );
    } on Object {
      // The page changed meanwhile.
    }
  }

  /// Opens the site's search field (the home-screen search widget).
  Future<void> _openPageSearch() async {
    if (_disposed) return;
    try {
      await controller.runJavaScript('''(() => {
          const button = document.querySelector(
            'ytm-mobile-topbar-renderer .topbar-button-search-button');
          if (button) button.click();
          setTimeout(() => {
            const field = document.querySelector(
              'ytm-mobile-topbar-renderer input.ytSearchboxComponentInput');
            if (field) field.focus();
          }, 300);
        })()''');
    } on Object {
      // The page changed meanwhile: the search icon is still there to tap.
    }
  }

  String? _handedOffVideoId;
  String? _shortsVideoId;
  String? _unmuteOnReadyVideoId;
  // Last request counters seen (null: none yet on this page).
  int? _minimizeSeq;
  int? _homeSeq;
  int? _openSeq;

  Future<void> _handOffVideo(String id) async {
    final Uri? page = Uri.tryParse(await controller.currentUrl() ?? '');
    final String host = page != null && page.host.endsWith('youtube.com')
        ? page.host
        : 'm.youtube.com';
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      onOpenRequest?.call(Uri.https(host, '/watch', <String, String>{'v': id}));
    }
    await command('pause');
    if (!_disposed &&
        page != null &&
        (page.path == '/watch' || page.path.startsWith('/shorts/'))) {
      await goBack();
    }
  }

  @override
  Future<void> applyPageRoles() async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(
        'window.__transponoIOS = '
        '${defaultTargetPlatform == TargetPlatform.iOS};'
        'window.__transponoNativeBar = ${nativeGlassBar.value};'
        'window.__transponoBrowseOnly = $browseOnly;'
        'window.__transponoLowVideo = $lowVideo;'
        'window.__transponoAutoSound = ${!browseOnly && _native == null};'
        'window.__transponoAppMini = $appMini;'
        'window.__transponoAppMiniSurface = $appMiniSurface;'
        'if (window.__transponoSetAppMiniSurface) {'
        'window.__transponoSetAppMiniSurface($appMiniSurface);'
        '} else {'
        'document.documentElement?.classList.toggle('
        '"transpono-app-mini-surface", $appMiniSurface);'
        '}',
      );
    } on Object {
      // No page yet: applied again when the bridge installs.
    }
  }

  @override
  Future<void> command(String action, [num? value]) async {
    if (_disposed) return;
    final native = _native;
    if (native != null && value != null && native.handles(action)) {
      await native.command(action, value);
      return;
    }
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
  Future<void> playWatch(Uri watch) async {
    if (!isYouTubeBrowserUri(watch)) throw ArgumentError.value(watch);
    await command('pause');
    if (_disposed) return;
    _timeline.reset();
    _pauseOnReadyVideoId = null;
    _focusOnReadyVideoId = watch.queryParameters['v'];
    _unmuteOnReadyVideoId = watch.queryParameters['v'];
    _media = const YouTubeMediaState();
    _error = null;
    _progress = 0;
    _notify();
    await controller.loadRequest(watch);
  }

  @override
  Future<void> releaseFocus() async {
    if (_disposed) return;
    try {
      await controller.runJavaScript('''(() => {
          const field = document.activeElement;
          if (field && field !== document.body && field.blur) field.blur();
        })()''');
    } on Object {
      // No page context (navigating); nothing has the focus then.
    }
  }

  @override
  Future<void> adjustmentsShown(bool shown) async {
    if (_disposed) return;
    try {
      await controller.runJavaScript(
        shown
            ? '''(() => {
                // The mini player stays off while the adjustments are open.
                window.__transponoAdjustmentsOpen = true;
                document.documentElement.classList.remove('transpono-mini');
                window.__transponoScrollBefore = window.scrollY;
                window.scrollTo({top: 0, left: 0, behavior: 'instant'});
              })()'''
            : '''(() => {
                window.__transponoAdjustmentsOpen = false;
                const y = window.__transponoScrollBefore;
                window.__transponoScrollBefore = undefined;
                if (typeof y === 'number' && y > 0) {
                  window.scrollTo({top: y, left: 0, behavior: 'instant'});
                }
              })()''',
      );
    } on Object {
      // No page context (navigating); scrolling is only a convenience.
    }
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
    await controller.loadRequest(
      _soundCloud ? soundCloudSearchUri(query) : youtubeSearchUri(query),
    );
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

  NavigationDelegate _navigationDelegate({
    required void Function(int) onProgress,
    required void Function(String) onPageStarted,
    required void Function(String) onPageFinished,
    required void Function(WebResourceError) onWebResourceError,
    required FutureOr<NavigationDecision> Function(NavigationRequest)
    onNavigationRequest,
  }) => _gecko == null
      ? NavigationDelegate(
          onProgress: onProgress,
          onPageStarted: onPageStarted,
          onPageFinished: onPageFinished,
          onWebResourceError: onWebResourceError,
          onNavigationRequest: onNavigationRequest,
        )
      : NavigationDelegate.fromPlatform(
          GeckoNavigationDelegate(),
          onProgress: onProgress,
          onPageStarted: onPageStarted,
          onPageFinished: onPageFinished,
          onWebResourceError: onWebResourceError,
          onNavigationRequest: onNavigationRequest,
        );

  @override
  Widget buildView() {
    final GeckoWebViewController? gecko = _gecko;
    if (gecko != null) {
      return WebViewWidget.fromPlatform(
        platform: GeckoWebViewWidget(gecko, key: const Key('youtubeWebView')),
      );
    }
    const Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers =
        <Factory<OneSequenceGestureRecognizer>>{};
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Keep the default texture composition after comparing it with Hybrid
      // Composition on the A16. The native mode did not fix the post-mini
      // click loss and made the overlapping mini view less predictable.
      // Leave gestures to the platform view: no Flutter recognizer should
      // consume taps intended for YouTube's controls.
      final PlatformWebViewWidgetCreationParams baseParams =
          PlatformWebViewWidgetCreationParams(
            key: const Key('youtubeWebView'),
            controller: controller.platform,
            gestureRecognizers: gestureRecognizers,
          );
      return WebViewWidget.fromPlatformCreationParams(
        params:
            AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
              baseParams,
              displayWithHybridComposition: false,
            ),
      );
    }
    return WebViewWidget(
      key: const Key('youtubeWebView'),
      controller: controller,
      gestureRecognizers: gestureRecognizers,
    );
  }

  @override
  void dispose() {
    pageInputFocused.value = false;
    pageScrolledDown.value = false;
    if (publishesPageState) pageYouTubeBars.value = null;
    if (!browseOnly) musicSongTabs.value = null;
    if (!browseOnly) pageUnmutePrompt.value = false;
    _disposed = true;
    _timer?.cancel();
    if (_native case final native?) native.dispose();
    unawaited(
      controller
          .runJavaScript(
            'window.TransponoMedia?.dispose(); document.querySelectorAll("video,audio").forEach(v => v.pause());',
          )
          .catchError((Object _) {}),
    );
    if (_gecko case final gecko?) {
      unawaited(gecko.dispose().catchError((Object _) {}));
    }
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
