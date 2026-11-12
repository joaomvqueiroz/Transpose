import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gecko_view/gecko_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'home_button_visibility.dart';
import 'studio_appearance.dart';
import 'youtube_browser.dart';
import 'youtube_search.dart';

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
      host == 'accounts.youtube.com' ||
      host == 'appleid.apple.com' ||
      host == 'idmsa.apple.com' ||
      host == 'www.facebook.com' ||
      host == 'm.facebook.com';
}

/// Counts the times the Spotify page (on iPhone's Gecko engine) headed for
/// Spotify's sign-in: that page refuses this engine, so the app opens the
/// sign-in in Safari's engine instead (see `spotify_sign_in.dart`).
final ValueNotifier<int> spotifySignInRequests = ValueNotifier<int>(0);

/// Spotify's own sign-in pages.
bool isSpotifySignInUri(Uri uri) =>
    uri.scheme == 'https' && uri.host == 'accounts.spotify.com';

/// The song the Spotify web player reports, from Media Session or the title.
class SpotifyTrack {
  const SpotifyTrack({required this.title, this.artist = ''});

  final String title, artist;

  bool get isEmpty => title.trim().isEmpty;

  /// Search text for YouTube and chord sites.
  String get query => artist.isEmpty ? title : '$title $artist';

  /// "Song - Artist", the shape the studio's chord search expects.
  String get displayTitle => artist.isEmpty ? title : '$title - $artist';

  /// Stable id for the studio (chords, setlist). Never an 11-character
  /// YouTube id, so it can never be opened as a YouTube video by mistake.
  String get id =>
      'spotify-${base64Url.encode(utf8.encode(query.toLowerCase())).replaceAll('=', '')}';

  /// Reads `{title, artist, documentTitle}` from the page script below.
  static SpotifyTrack? decode(Object? raw) {
    final Map<Object?, Object?>? value = _decodeMap(raw);
    if (value == null) return null;
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

Map<Object?, Object?>? _decodeMap(Object? raw) {
  Object? value = raw;
  // Android may return the JSON quoted; WebKit and Gecko return the string.
  for (var i = 0; value is String && i < 2; i++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? value : null;
}

/// "rgb(r, g, b)" or "rgba(r, g, b, a)" from the page, as an opaque colour.
Color? _cssColor(Object? value) {
  final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)')
      .firstMatch('${value ?? ''}');
  if (match == null) return null;
  int part(int i) => int.parse(match.group(i)!).clamp(0, 255);
  return Color.fromARGB(255, part(1), part(2), part(3));
}

/// "1:23" or "1:02:03" from the player's time labels, in seconds.
double parseSpotifyClock(Object? text) {
  final parts = '${text ?? ''}'.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return 0;
  var seconds = 0.0;
  for (final part in parts) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) return 0;
    seconds = seconds * 60 + value;
  }
  return seconds;
}

/// Reads what the web player shows. Text and attributes only; no audio.
/// Covers both pages Spotify serves: the desktop-like player and the mobile
/// one (a floating bar with the song, and no media session in a WebView).
const String _snapshotScript = '''
(() => {
  const session = navigator.mediaSession;
  const m = session && session.metadata;
  const text = s => { const e = document.querySelector(s); return e ? (e.textContent || '').trim() : ''; };
  const button = document.querySelector('[data-testid="control-button-playpause"]');
  const label = button ? (button.getAttribute('aria-label') || '') : '';
  const clock = v => {
    if (!isFinite(v) || v < 0) return '';
    const t = Math.floor(v);
    return Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
  };
  let title = (m && m.title) || '';
  let artist = (m && m.artist) || '';
  let position = text('[data-testid="playback-position"]');
  let duration = text('[data-testid="playback-duration"]');
  let state = (session && session.playbackState) || '';
  const bar = document.querySelector('[data-testid="floating-now-playing-bar"]');
  if (bar) {
    const lines = [...bar.querySelectorAll('span')]
      .map(e => (e.textContent || '').trim()).filter(Boolean);
    if (!title && lines.length) { title = lines[0]; artist = lines[1] || ''; }
    const progress = bar.querySelector('[style*="animationPlayState"]');
    const style = progress ? progress.getAttribute('style') || '' : '';
    const number = name => {
      const found = style.match(new RegExp(name + ':\\\\s*(-?[0-9.]+)ms'));
      return found ? Math.abs(parseFloat(found[1])) / 1000 : NaN;
    };
    let seconds = number('--animationDelay');
    let total = number('--finalAnimationDuration');
    let playing = style.indexOf('animationPlayState: running') >= 0;
    // The player's own audio element (kept by the mute hook) is exact.
    for (const audio of (window.__transponoMedia || [])) {
      if (!isFinite(audio.duration) || audio.duration < 2) continue;
      seconds = audio.currentTime;
      total = audio.duration;
      playing = !audio.paused;
      if (!audio.paused) break;
    }
    if (!position) position = clock(seconds);
    if (!duration) duration = clock(total);
    if (!state) state = playing ? 'playing' : 'paused';
  }
  return JSON.stringify({
    title: title,
    artist: artist,
    documentTitle: document.title || '',
    position: position,
    duration: duration,
    state: state,
    label: label
  });
})()
''';

/// Dresses Spotify's mobile page for the studio: the "Obter app" tab becomes
/// "Ajustes", the open player gets the same button, and the home page's top
/// bar gets the start-screen button beside its gear. Taps are counted; the
/// app reads the counters.
/// The start-screen button beside Spotify's gear, in the place of the
/// site's "Abrir app" (hidden). Part of [_dressScript]; needs `S`, `icon`,
/// `count`, `grid` and `home` in scope.
const String _spotifyHomeButtonJs = r'''
  // "Abrir app" / "Open app": never shown; the start-screen button takes
  // its place, just left of the gear.
  for (const link of document.querySelectorAll('a, button')) {
    if (link.dataset.transpono) continue;
    const text = (link.textContent || '').trim();
    if (/^(abrir (a |o )?app|abrir no app|open (the )?app|get (the )?app|obter (a )?app)$/i.test(text) &&
        link.style.display !== 'none') {
      link.style.setProperty('display', 'none', 'important');
    }
  }
  const gear = document.querySelector('[data-testid="settings-container"] [data-testid="gears-button"]');
  if (gear) {
    let button = gear.parentNode.querySelector('[data-transpono="home"]');
    if (!button) {
      button = gear.cloneNode(true);
      button.dataset.transpono = 'home';
      button.removeAttribute('data-testid');
      button.setAttribute('aria-label', 'Voltar ao ecrã inicial');
      button.style.marginLeft = 'auto';
      button.style.marginRight = '4px';
      icon(button, grid);
      count(button, 'home');
      gear.parentNode.insertBefore(button, gear);
    }
    const box = button.getBoundingClientRect();
    home = box.bottom > 0 && box.top < window.innerHeight;
  }
''';

const String _dressScript = '''
(() => {
  const S = window.__transponoSp || (window.__transponoSp = {adjust: 0, home: 0});
  const tune = '<path fill="currentColor" d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/>';
  const grid = '<path fill="currentColor" d="M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"/>';
  const icon = (host, path) => {
    const svg = host.querySelector('svg');
    if (!svg) return;
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.innerHTML = path;
  };
  const count = (element, key) => element.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    S[key] += 1;
  }, true);
  let adjust = false;
  const nav = document.querySelector('[data-testid="bottom-tab-navigation"]');
  // Spotify's bottom bar a little shorter (70 -> 56 px): its icons and
  // labels stay centred in it.
  if (nav && !document.getElementById('transpono-slim-nav')) {
    const slim = document.createElement('style');
    slim.id = 'transpono-slim-nav';
    slim.textContent = '[data-testid="bottom-tab-navigation"],' +
      '[data-testid="bottom-tab-navigation"] > div,' +
      '[data-testid="bottom-tab-navigation"] > div > a{height:56px!important}';
    document.head.appendChild(slim);
  }
  if (nav) {
    let tab = nav.querySelector('[data-transpono="adjust"]');
    if (!tab) {
      tab = nav.querySelector('a[href*="download"]');
      if (tab) {
        tab.dataset.transpono = 'adjust';
        tab.removeAttribute('href');
        tab.setAttribute('role', 'button');
        tab.setAttribute('aria-label', 'Ajustes');
        icon(tab, tune);
        const label = tab.querySelector('span');
        if (label) label.textContent = 'Ajustes';
        count(tab, 'adjust');
      }
    }
    adjust = !!tab;
  }
  const share = document.querySelector('[data-testid="npv-share-button"]');
  if (share && !document.querySelector('[data-transpono="npv-adjust"]')) {
    // An arrow up: it brings the adjustments up from under the song.
    const button = share.cloneNode(true);
    button.dataset.transpono = 'npv-adjust';
    button.removeAttribute('data-testid');
    button.setAttribute('aria-label', 'Mostrar ajustes');
    icon(button, '<path fill="currentColor" d="M2.79 16.2a1 1 0 0 0 1.42 0L12 8.41l7.79 7.8a1 1 0 0 0 1.42-1.42L12 5.59l-9.21 9.2a1 1 0 0 0 0 1.42z"/>');
    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      if (window.TransponoSpotify) window.TransponoSpotify.postMessage('o');
    }, true);
    share.parentNode.insertBefore(button, share);
    // In the middle of the screen's width, whatever sits beside it.
    const row = share.parentNode;
    if (getComputedStyle(row).position === 'static') row.style.position = 'relative';
    button.style.position = 'absolute';
    button.style.left = '50%';
    button.style.top = '50%';
    button.style.transform = 'translate(-50%, -50%)';
    button.style.margin = '0';
    // In sight for a few seconds every 15 s, then it fades out.
    button.style.transition = 'opacity .7s ease';
    const show = () => {
      button.style.opacity = '1';
      button.style.pointerEvents = 'auto';
      clearTimeout(button.__hide);
      button.__hide = setTimeout(() => {
        button.style.opacity = '0';
        button.style.pointerEvents = 'none';
      }, 3500);
    };
    show();
    button.__cycle = setInterval(() => {
      if (!document.contains(button)) { clearInterval(button.__cycle); return; }
      show();
    }, 15000);
  }
  if (share) adjust = true;
  let home = false;
$_spotifyHomeButtonJs
  // Over the open player (song, cover, controls) there is no start-screen
  // button at all: it would sit on the cover.
  // The start-screen button lives only in the home page's top bar, beside
  // the gear: on every other Spotify page there is none floating either
  // (the "Início" tab leads back to it).
  if (nav) home = true;
  let tint = '';
  let tintEnd = '';
  const npv = document.querySelector('[data-testid="npv-container"]');
  if (npv) {
    home = true;
    // The colour Spotify paints behind the song.
    for (let e = npv; e && !tint; e = e.parentElement) {
      const style = getComputedStyle(e);
      if (style.backgroundColor && !/rgba\\(0, 0, 0, 0\\)|transparent/.test(style.backgroundColor)) {
        tint = style.backgroundColor;
      } else {
        const found = (style.backgroundImage || '').match(/rgba?\\([^)]*\\)/g);
        if (found) { tint = found[0]; tintEnd = found[found.length - 1]; }
      }
    }
    // Layers from the top down, each element's gradient over its own
    // colour, until the colour is solid.
    let over = null;
    const add = (c) => {
      if (!c || c.length < 3) return;
      const ca = c[3] === undefined ? 1 : c[3];
      if (ca <= 0) return;
      if (!over) { over = [c[0], c[1], c[2], ca]; return; }
      const oa = over[3];
      const a = oa + ca * (1 - oa);
      over = [0, 1, 2].map((j) => (over[j] * oa + c[j] * ca * (1 - oa)) / a).concat([a]);
    };
    // The player's own last line (it may end above the screen's bottom).
    const lastY = Math.max(1, Math.min(innerHeight, npv.getBoundingClientRect().bottom) - 3);
    for (let e = document.elementFromPoint(innerWidth / 2, lastY); e && !(over && over[3] >= .99); e = e.parentElement) {
      const style = getComputedStyle(e);
      const stops = [...(style.backgroundImage || '').matchAll(/rgba?\\(([^)]*)\\)\\s*([0-9.]+%)?/g)];
      if (stops.length) {
        const r = e.getBoundingClientRect();
        const t = Math.max(0, Math.min(1, (lastY - r.top) / (r.height || 1)));
        const pts = stops.map((m, i) => ({
          c: m[1].split(',').map(Number),
          p: m[2] ? parseFloat(m[2]) / 100 : i / Math.max(1, stops.length - 1),
        }));
        let a = pts[0], b = pts[0];
        for (let i = 0; i < pts.length; i++) {
          if (pts[i].p <= t) a = pts[i];
          b = pts[i];
          if (pts[i].p >= t) break;
        }
        const k = b.p > a.p ? (t - a.p) / (b.p - a.p) : 0;
        add([0, 1, 2, 3].map((j) => {
          const x = a.c[j] === undefined ? 1 : a.c[j];
          const y = b.c[j] === undefined ? 1 : b.c[j];
          return x + (y - x) * k;
        }));
      }
      const plain = (style.backgroundColor || '').match(/[0-9.]+/g);
      if (plain && plain.length >= 3) add(plain.map(Number));
    }
    if (over) {
      if (over[3] < .99) add([18, 18, 18, 1]);
      tintEnd = 'rgb(' + over.slice(0, 3).map(Math.round).join(', ') + ')';
      // Below the player, the page goes on in that colour: no black band
      // between it and the adjustments or Android's buttons.
      document.documentElement.style.backgroundColor = tintEnd;
      document.body.style.backgroundColor = tintEnd;
      window.__transponoBg = true;
    }
  } else if (window.__transponoBg) {
    window.__transponoBg = false;
    document.documentElement.style.backgroundColor = '';
    document.body.style.backgroundColor = '';
  }
  return JSON.stringify({adjust: S.adjust, home: S.home, hasAdjust: adjust, hasHome: home, tint: tint, tintEnd: tintEnd, npv: !!npv, npvBottom: npv ? npv.getBoundingClientRect().bottom * devicePixelRatio : null});
})()
''';

/// Keeps Spotify's own sound off while the same song plays from YouTube
/// (where the tone works). Volume only: nothing is read from the audio.
const String _muteScript = '''
(() => {
  if (!window.__transponoMuteHook) {
    window.__transponoMuteHook = true;
    window.__transponoMedia = new Set();
    const play = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      window.__transponoMedia.add(this);
      this.muted = true;
      return play.apply(this, arguments);
    };
  }
  for (const m of document.querySelectorAll('audio, video')) m.muted = true;
  for (const m of window.__transponoMedia) m.muted = true;
  return true;
})()
''';

/// Moves Spotify on to its next song: its own "next" button where the page
/// shows one, or else its muted audio is taken to its end, and Spotify
/// follows on by itself.
const String _nextScript = '''
(() => {
  const button = document.querySelector('[data-testid="npv-skip-forward-button"]') ||
    document.querySelector('[data-testid="control-button-skip-forward"]');
  if (button && !button.disabled) { button.click(); return true; }
  for (const audio of (window.__transponoMedia || [])) {
    if (isFinite(audio.duration) && audio.duration > 3) {
      audio.currentTime = audio.duration - 0.3;
      return true;
    }
  }
  return false;
})()
''';

/// Spotify's "previous": its own button, or else the song from the start.
const String _previousScript = '''
(() => {
  const button = document.querySelector('[data-testid="npv-skip-back-button"]') ||
    document.querySelector('[data-testid="control-button-skip-back"]');
  if (button && !button.disabled) { button.click(); return true; }
  for (const audio of (window.__transponoMedia || [])) audio.currentTime = 0;
  return false;
})()
''';

/// The page always believes it is on screen, so that neither Spotify nor
/// YouTube stops the song when the app goes to the background.
const String keepAwakeScript = '''
(() => {
  if (window.__transponoAwake) return true;
  window.__transponoAwake = true;
  try {
    const proto = Document.prototype;
    Object.defineProperty(proto, 'hidden', {configurable: true, get: () => false});
    Object.defineProperty(proto, 'visibilityState', {configurable: true, get: () => 'visible'});
    Object.defineProperty(proto, 'webkitVisibilityState', {configurable: true, get: () => 'visible'});
    proto.hasFocus = () => true;
  } catch (e) {}
  for (const type of ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'blur', 'freeze']) {
    window.addEventListener(type, (event) => event.stopImmediatePropagation(), true);
    document.addEventListener(type, (event) => event.stopImmediatePropagation(), true);
  }
  return true;
})()
''';

/// Takes Spotify's muted audio back, so that it ends with the YouTube song.
String _holdScript(double seconds) =>
    '''
(() => {
  for (const audio of (window.__transponoMedia || [])) {
    if (isFinite(audio.duration) && audio.duration > 3) {
      audio.currentTime = Math.max(0, Math.min(audio.duration - 1, $seconds));
      return true;
    }
  }
  return false;
})()
''';

/// The first video of a YouTube results page (never a Short).
const String _firstVideoScript = '''
(() => {
  for (const a of document.querySelectorAll('a[href*="/watch?v="]')) {
    const href = a.href || '';
    if (href.indexOf('list=') < 0) return href;
  }
  return '';
})()
''';

/// Presses the player's own play/pause button when its state differs.
String _playPauseScript(bool play) =>
    '''
(() => {
  const button = document.querySelector('[data-testid="control-button-playpause"]');
  if (button) {
    const label = (button.getAttribute('aria-label') || '').toLowerCase();
    const showsPause = label.includes('pause') || label.includes('pausa');
    if (showsPause !== $play) button.click();
    return true;
  }
  // The mobile page: the floating bar's button (or the open player's).
  const mobile = document.querySelector('[data-testid="npv-play-button"]') ||
    document.querySelector('[data-test-id="play-pause-button"]');
  if (!mobile) return false;
  let playing = null;
  for (const audio of (window.__transponoMedia || [])) {
    if (isFinite(audio.duration) && audio.duration > 2) { playing = !audio.paused; if (playing) break; }
  }
  if (playing === null) {
    const bar = document.querySelector('[data-testid="floating-now-playing-bar"] [style*="animationPlayState"]');
    playing = !!bar && (bar.getAttribute('style') || '').indexOf('running') >= 0;
  }
  if (playing !== $play) mobile.click();
  return true;
})()
''';

/// Moves the player's own progress slider, as a user drag would.
String _seekScript(double seconds) =>
    '''
(() => {
  const input = document.querySelector('[data-testid="playback-progressbar"] input[type="range"]');
  if (!input) return false;
  const max = Number(input.max) || 0;
  const value = max > 1000 ? ${seconds * 1000} : $seconds;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  setter.call(input, String(Math.max(0, Math.min(max || value, value))));
  input.dispatchEvent(new Event('input', {bubbles: true}));
  input.dispatchEvent(new Event('change', {bubbles: true}));
  return true;
})()
''';

/// iPhone: Spotify's page runs in Safari's engine (WKWebView), where its
/// protected songs play (Gecko has no such DRM: "Reprodução desativada") and
/// its sign-in works; the sound, with the tone, comes from YouTube in Gecko
/// behind it, as on Android. False puts the page back in Gecko.
bool spotifyInSafariEngine = true;

/// Spotify's web player as the studio's media source.
///
/// The studio shows exactly what it shows for YouTube. Spotify's audio is
/// DRM-protected, so Transpono cannot reach it: pitch, EQ and effects report
/// themselves unavailable here. Play, pause and seeking press the player's
/// own controls. The song title feeds the studio's chord search.
class SpotifyStudioSession extends YouTubeBrowserSession {
  SpotifyStudioSession() {
    if (GeckoEngine.isAvailable && !spotifyInSafariEngine) {
      final gecko = GeckoWebViewController();
      _gecko = gecko;
      _controller = WebViewController.fromPlatform(gecko);
    } else {
      final PlatformWebViewControllerCreationParams params =
          WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      _controller = WebViewController.fromPlatformCreationParams(
        params,
        // Spotify's songs are DRM-protected: Android's WebView asks before
        // it lets a page play them, and without an answer Spotify shows
        // "Reprodução desativada". Only that request is granted; camera,
        // microphone and the rest stay refused.
        onPermissionRequest: (WebViewPermissionRequest request) {
          final bool onlyProtectedMedia =
              request.types.isNotEmpty &&
              request.types.every(
                (type) =>
                    type ==
                    AndroidWebViewPermissionResourceType.protectedMediaId,
              );
          if (onlyProtectedMedia) {
            unawaited(request.grant());
          } else {
            unawaited(request.deny());
          }
        },
      );
    }
  }

  static final Uri home = Uri.https('open.spotify.com', '/');
  static const String protectedMessage =
      'No Spotify a música é protegida: o tom, o EQ e os efeitos só '
      'funcionam no YouTube.';

  late final WebViewController _controller;
  GeckoWebViewController? _gecko;
  Timer? _poll;
  bool _reading = false;
  int? _adjustSeq;
  int? _homeSeq;

  /// The song is heard from YouTube, where the tone works.
  bool get playsFromYouTube => _shadow != null;

  /// Spotify's own bars carry the studio's buttons; their taps come here.
  Future<void> _dressPage() async {
    // The same on iPhone's Gecko engine as on Android.
    try {
      final values = _decodeMap(
        await _controller.runJavaScriptReturningResult(_dressScript),
      );
      if (_disposed || values == null) return;
      pageDrawsAdjustButton.value = values['hasAdjust'] == true;
      spotifyPlayerOpen.value = values['npv'] == true;
      final Object? npvBottom = values['npvBottom'];
      // In the screen's own pixels, from the page's top.
      spotifyPlayerBottom.value = npvBottom is num && npvBottom > 0
          ? npvBottom.toDouble()
          : null;
      final Color? tint = _cssColor(values['tint']);
      if (tint != null) spotifyTint = tint;
      spotifyTintEnd = _cssColor(values['tintEnd']) ?? tint ?? spotifyTintEnd;
      pageDrawsHomeButton.value = values['hasHome'] == true;
      final Object? adjust = values['adjust'];
      if (adjust is num) {
        if (_adjustSeq != null && adjust.toInt() != _adjustSeq) {
          pageAdjustRequests.value++;
        }
        _adjustSeq = adjust.toInt();
      }
      final Object? home = values['home'];
      if (home is num) {
        if (_homeSeq != null && home.toInt() != _homeSeq) {
          pageHomeRequests.value++;
        }
        _homeSeq = home.toInt();
      }
    } on Object {
      // No page yet; the next poll dresses it.
    }
  }

  /// The same song, played from YouTube behind the Spotify page: Spotify
  /// stays as the remote control (songs, playlists, play, pause, next) with
  /// its sound off, and the tone, EQ and effects work on what is heard.
  /// Android, and iPhone with Gecko (the YouTube page plays in Gecko, the
  /// Spotify page in Safari's engine).
  late final WebViewYouTubeSession? _shadow =
      _gecko == null &&
          (defaultTargetPlatform == TargetPlatform.android ||
              (defaultTargetPlatform == TargetPlatform.iOS &&
                  GeckoEngine.isAvailable))
      ? (WebViewYouTubeSession()
          ..publishesPageState = false
          ..lowVideo = true
          ..addListener(_notify))
      : null;
  String? _shadowTrackId;
  String? _shadowSearchFor;
  int _shadowSearchTicks = 0;
  bool _shadowLoaded = false;
  bool _advancing = false;
  bool _disposed = false;
  bool _started = false;
  int _progress = 0;
  String? _error;
  bool _canGoBack = false;
  SpotifyTrack? _track;
  YouTubeMediaState _media = const YouTubeMediaState(
    pitchStatus: 'unavailable',
    keyStatus: 'unavailable',
  );

  /// The song playing now, for "Tocar no YouTube com tom".
  SpotifyTrack? get track => _track;

  /// With the song playing from YouTube, the studio hears and adjusts that
  /// player (tone, key, EQ, position); the name is still Spotify's.
  @override
  YouTubeMediaState get media {
    final shadow = _shadow;
    if (shadow == null || !_shadowLoaded || !shadow.media.hasVideo) {
      return _media;
    }
    final YouTubeMediaState heard = shadow.media;
    return YouTubeMediaState(
      videoId: _media.videoId,
      title: _media.title,
      hasVideo: true,
      playing: _media.playing,
      position: heard.position,
      duration: heard.duration,
      speed: heard.speed,
      pitch: heard.pitch,
      pitchStatus: heard.pitchStatus,
      pitchMessage: heard.pitchMessage,
      loopA: heard.loopA,
      loopB: heard.loopB,
      loopEnabled: heard.loopEnabled,
      isAd: heard.isAd,
      adSkippable: heard.adSkippable,
      loopCount: heard.loopCount,
      loopEpoch: heard.loopEpoch,
      loopEventsSupported: heard.loopEventsSupported,
      playbackReady: heard.playbackReady,
      keyRoot: heard.keyRoot,
      keyMode: heard.keyMode,
      keyStatus: heard.keyStatus,
      audioEffects: heard.audioEffects,
    );
  }

  @override
  int get progress => _progress;
  @override
  String? get error => _error;
  @override
  bool get canGoBack => _canGoBack;

  void _notify() {
    if (_disposed) return;
    final YouTubeMediaState m = media;
    final String now = [
      m.videoId,
      m.title,
      m.hasVideo,
      m.playing,
      (m.position * 2).floor(),
      m.duration.round(),
      m.pitch,
      m.speed,
      m.pitchStatus,
      m.pitchMessage,
      m.playbackReady,
      m.loopEnabled,
      m.loopA,
      m.loopB,
      m.keyRoot,
      m.keyMode,
      m.keyStatus,
      m.isAd,
      m.adSkippable,
      m.muted,
      m.audioEffects,
      _progress,
      _error,
      _canGoBack,
    ].join('|');
    if (now == _shown) return;
    _shown = now;
    notifyListeners();
  }

  // What the app was last told (see [_notify]).
  String? _shown;
  int _tick = 0;

  /// Always opens Spotify, whatever [uri] the studio passes for YouTube.
  @override
  Future<void> start(Uri uri) async {
    if (_started) return;
    _started = true;
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.black);
    // Play, pause and "next" are also pressed by the app (from the studio,
    // and to follow the YouTube player behind): without this, Android only
    // lets the page start its audio after a real touch, and Spotify hangs.
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }
    // iPhone, Safari's engine: WKWebView reports itself as Safari without
    // the final "Version/… Safari/…" words Safari itself sends, and Spotify
    // then serves its cut-down page (no player). Add them: it is Safari's
    // own engine, the one Spotify plays in.
    if (_gecko == null && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final String agent = await _controller.getUserAgent() ?? '';
        final RegExpMatch? os = RegExp(r'OS (\d+)_(\d+)').firstMatch(agent);
        if (agent.isNotEmpty && os != null && !agent.contains('Safari/')) {
          await _controller.setUserAgent(
            '$agent Version/${os.group(1)}.${os.group(2)} Safari/604.1',
          );
        }
      } on Object {
        // The default one, then.
      }
    }
    await _controller.setNavigationDelegate(_navigationDelegate());
    {
      // The finger on the open player, passed on as it moves. On Gecko the
      // relay extension provides window.TransponoSpotify.
      await _controller.addJavaScriptChannel(
        'TransponoSpotify',
        onMessageReceived: (JavaScriptMessage message) {
          final String text = message.message;
          if (text == 'o') {
            pageAdjustRequests.value++;
            return;
          }
          final double? value = double.tryParse(
            text.length > 2 ? text.substring(2) : '',
          );
          if (value == null || !value.isFinite) return;
          if (text.startsWith('d:')) spotifyPullDrag?.call(value);
          if (text.startsWith('e:')) spotifyPullEnd?.call(value);
        },
      );
    }
    if (_disposed) return;
    _poll = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => unawaited(_refresh()),
    );
    await _controller.loadRequest(home);
    final shadow = _shadow;
    if (shadow != null && !_disposed) {
      try {
        await shadow.start(Uri.https('m.youtube.com', '/'));
      } on Object {
        // Without YouTube the song still plays from Spotify itself.
      }
    }
  }

  /// One step of following Spotify with the YouTube player behind it.
  Future<void> _followWithYouTube(
    SpotifyTrack? track,
    bool spotifyPlaying,
    double spotifyPosition,
    double spotifyDuration,
  ) async {
    final shadow = _shadow;
    if (shadow == null || _disposed) return;
    try {
      // One call for the page: its sound off and, every few seconds, the
      // page kept "on screen" (both pages).
      final bool awake = _tick % 10 == 0;
      // The sound stays off once set: checked every few reads, and on a
      // new song.
      final bool mute = _tick % 4 == 0 || track?.id != _shadowTrackId;
      if (awake || mute) {
        await _controller.runJavaScript(
          awake ? '$_muteScript;$keepAwakeScript' : _muteScript,
        );
      }
      if (awake) await shadow.controller.runJavaScript(keepAwakeScript);
    } on Object {
      // No page yet.
    }
    if (track == null || track.isEmpty) return;
    // A new song on Spotify: find it on YouTube.
    if (track.id != _shadowTrackId) {
      _shadowTrackId = track.id;
      _shadowSearchFor = track.id;
      _shadowSearchTicks = 0;
      _shadowLoaded = false;
      _advancing = false;
      await shadow.command('pause');
      await shadow.controller.loadRequest(youtubeSearchUri(track.query));
      return;
    }
    // Waiting for the results page: open its first video.
    if (_shadowSearchFor == track.id) {
      _shadowSearchTicks++;
      Object? href;
      try {
        href = await shadow.controller.runJavaScriptReturningResult(
          _firstVideoScript,
        );
      } on Object {
        href = null;
      }
      final String link = '${href ?? ''}'.replaceAll('"', '');
      final Uri? watch = Uri.tryParse(link);
      if (watch != null &&
          isYouTubeBrowserUri(watch) &&
          watch.path == '/watch') {
        _shadowSearchFor = null;
        _shadowLoaded = true;
        await shadow.playWatch(watch);
      } else if (_shadowSearchTicks > 25) {
        // Nothing found in 20 s: give the search another go.
        _shadowTrackId = null;
      }
      return;
    }
    if (!_shadowLoaded) return;
    final YouTubeMediaState heard = shadow.media;
    if (!heard.hasVideo || heard.isAd) return;
    final double left = heard.duration - heard.position;
    // The song ended on YouTube: Spotify moves to the next one.
    if (heard.duration > 5 && left < 1.2 && !_advancing) {
      _advancing = true;
      try {
        await _controller.runJavaScript(_nextScript);
      } on Object {
        _advancing = false;
      }
      return;
    }
    // Spotify would end first (another version of the song): hold it back
    // so that both end together.
    final double spotifyLeft = spotifyDuration - spotifyPosition;
    if (spotifyPlaying &&
        spotifyDuration > 10 &&
        spotifyLeft < 5 &&
        left > spotifyLeft + 6) {
      try {
        await _controller.runJavaScript(
          _holdScript((spotifyDuration - left).clamp(0, spotifyDuration)),
        );
      } on Object {
        // Tried again at the next step.
      }
      return;
    }
    // Play and pause follow Spotify's own button.
    if (spotifyPlaying && !heard.playing && left > 1.5) {
      await shadow.command('play');
    } else if (!spotifyPlaying && heard.playing) {
      await shadow.command('pause');
    }
  }

  NavigationDelegate _navigationDelegate() {
    void onProgress(int value) {
      _progress = value;
      _notify();
    }

    void onPageStarted(String url) {
      // Gecko does not ask about every load (a server redirect to the
      // sign-in arrives unannounced): reaching Spotify's sign-in here also
      // opens it in Safari's engine, and the player goes back home.
      final Uri? started = Uri.tryParse(url);
      if (_gecko != null && started != null && isSpotifySignInUri(started)) {
        spotifySignInRequests.value++;
        unawaited(_controller.loadRequest(home).catchError((Object _) {}));
      }
      // A new document counts its taps from zero.
      _adjustSeq = null;
      _homeSeq = null;
      _error = null;
      _notify();
    }

    void onError(WebResourceError failure) {
      if (failure.isForMainFrame != true) return;
      // Safari's engine: a load cancelled or stopped by the app (a link to
      // the Spotify app, a refused page) is not a lost connection.
      if (failure.errorCode == -999 || failure.errorCode == 102) return;
      _error = 'Não foi possível carregar o Spotify. Verifique a ligação.';
      _progress = 100;
      _notify();
    }

    NavigationDecision decide(NavigationRequest request) {
      if (!request.isMainFrame) return NavigationDecision.navigate;
      final Uri? uri = Uri.tryParse(request.url);
      // On Gecko the sign-in happens in Safari's engine: Spotify's check
      // answers "Ocorreu um problema" to this one.
      if (_gecko != null && uri != null && isSpotifySignInUri(uri)) {
        spotifySignInRequests.value++;
        return NavigationDecision.prevent;
      }
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

  Future<void> _refresh() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _snapshotScript,
      );
      // Asked less often than the song's state: each call to the page costs
      // the phone's main thread.
      final back = _tick % 4 == 0 ? await _controller.canGoBack() : _canGoBack;
      if (_disposed) return;
      final values = _decodeMap(raw);
      final track = SpotifyTrack.decode(raw);
      final label = '${values?['label'] ?? ''}'.toLowerCase();
      final playing =
          values?['state'] == 'playing' ||
          label.contains('pause') ||
          label.contains('pausa');
      _track = track;
      _canGoBack = back;
      _tick++;
      if (_tick.isEven || spotifyPlayerOpen.value) unawaited(_dressPage());
      unawaited(
        _followWithYouTube(
          track,
          track != null && playing,
          parseSpotifyClock(values?['position']),
          parseSpotifyClock(values?['duration']),
        ),
      );
      _media = YouTubeMediaState(
        videoId: track?.id ?? '',
        title: track?.displayTitle ?? '',
        hasVideo: track != null,
        playing: track != null && playing,
        position: parseSpotifyClock(values?['position']),
        duration: parseSpotifyClock(values?['duration']),
        pitchStatus: 'unavailable',
        pitchMessage: track == null ? '' : protectedMessage,
        playbackReady: track != null,
        keyStatus: 'unavailable',
      );
      _notify();
    } on Object {
      // No page context yet (loading or navigating); the next poll retries.
    } finally {
      _reading = false;
    }
  }

  /// Spotify has no YouTube ids; a saved YouTube item cannot open here.
  @override
  Future<void> openVideo(String videoId) async {}

  /// Spotify's next song (from the notification or the lock screen).
  Future<void> next() async {
    try {
      await _controller.runJavaScript(_nextScript);
    } on Object {
      // The page may be navigating.
    }
  }

  /// Spotify's previous song.
  Future<void> previous() async {
    try {
      await _controller.runJavaScript(_previousScript);
    } on Object {
      // The page may be navigating.
    }
  }

  @override
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await _controller.loadRequest(
      Uri.https('open.spotify.com', '/search/${Uri.encodeComponent(trimmed)}'),
    );
  }

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Future<void> command(String action, [num? value]) async {
    String? script;
    switch (action) {
      case 'play':
        script = _playPauseScript(true);
      case 'pause':
        script = _playPauseScript(false);
      case 'seekTo':
        if (value != null && value.isFinite) {
          script = _seekScript(value.toDouble().clamp(0, 86400).toDouble());
        }
    }
    // Tone, speed, loop, EQ and effects act on the YouTube player behind;
    // Spotify's own protected audio is never touched.
    final shadow = _shadow;
    if (shadow != null && _shadowLoaded && !_disposed) {
      if (action == 'seekTo') {
        await shadow.command(action, value);
        return;
      }
      if (action != 'play' && action != 'pause') {
        await shadow.command(action, value);
        return;
      }
    }
    if (script == null || _disposed) return;
    try {
      await _controller.runJavaScript(script);
    } on Object {
      // The page may be navigating; the user can press the control again.
    }
    unawaited(_refresh());
  }

  @override
  Widget buildView() {
    final gecko = _gecko;
    if (gecko != null) {
      return WebViewWidget.fromPlatform(
        platform: GeckoWebViewWidget(gecko, key: const Key('spotifyWebView')),
      );
    }
    final Widget page = WebViewWidget(
      key: const Key('spotifyWebView'),
      controller: _controller,
    );
    final shadow = _shadow;
    if (shadow == null) return page;
    // Under the Spotify page, fully covered: it has to be on screen for
    // Android to keep it playing, but it is never seen nor touched.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: ExcludeSemantics(child: shadow.buildView())),
        page,
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _shadow?.dispose();
    pageDrawsAdjustButton.value = false;
    pageDrawsHomeButton.value = false;
    spotifyPlayerOpen.value = false;
    spotifyPlayerBottom.value = null;
    spotifyTint = spotifyBase;
    // Closing the Gecko session also stops Spotify's audio.
    final gecko = _gecko;
    if (gecko != null) unawaited(gecko.dispose());
    super.dispose();
  }
}
