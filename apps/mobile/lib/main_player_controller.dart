import 'dart:async';
import 'dart:typed_data';

import 'package:player_core/player_core.dart';

import 'media/local_player_controller.dart';
import 'player_panel_model.dart';
import 'player_presets.dart';
import 'youtube_browser.dart';
import 'loop_observation.dart';

/// A single selected source. Navigation/fullscreen never creates a new player.
class MainPlayerController extends PlayerPanelModel {
  MainPlayerController({
    LocalPlayerController? local,
    YouTubeBrowserSession Function()? youtubeFactory,
    Uri? youtubeHome,
  }) : local = local ?? LocalPlayerController(),
       _youtubeHome = youtubeHome ?? Uri.https('m.youtube.com', '/'),
       _youtubeFactory = youtubeFactory ?? WebViewYouTubeSession.new {
    this.local.addListener(_changed);
  }
  final LocalPlayerController local;
  final YouTubeBrowserSession Function() _youtubeFactory;

  /// First page of the browser: m.youtube.com, or music.youtube.com.
  final Uri _youtubeHome;
  YouTubeBrowserSession? _youtube;
  YouTubeBrowserSession? get youtube => _youtube;
  bool _online = false, _disposed = false;
  bool _youtubePauseRequested = false, _pausingYouTube = false;
  DateTime? _lastNativeVideoTouch;
  Completer<void>? _restoreCancellation;
  int _pending = 0;
  int _pauseRevision = 0;
  int _sourceIntentRevision = 0;
  int _manualControlRevision = 0, _automatedControlDepth = 0;
  int get manualControlRevision => _manualControlRevision;
  int get interruptionRevision => local.interruptionRevision;

  /// Tag only the synchronous submission, never unrelated input during await.
  Future<void> automatedCommand(Future<void> Function() action) {
    _automatedControlDepth++;
    try {
      return action();
    } finally {
      _automatedControlDepth--;
    }
  }

  String? _message;
  Future<void> _tail = Future<void>.value();
  bool get isYouTube => _online;
  bool get isRhythmPreview =>
      !_online && local.sourceId.startsWith('rhythm-preview-');
  @override
  LoopObservation? get loopObservation => !_online
      ? local.loopObservation
      : !_media.loopEventsSupported || _media.isAd
      ? null
      : LoopObservation(
          epoch: _media.loopEpoch,
          count: _media.loopCount,
          ready: _media.playbackReady,
          playing: _media.playing,
        );
  String get sourceKey => !loaded
      ? ''
      : _online
      ? 'youtube:${_media.videoId}'
      : 'local:${local.locator ?? ''}';
  bool _lastRestoreSucceeded = false;
  bool get lastRestoreSucceeded => _lastRestoreSucceeded;
  YouTubeMediaState get _media => _youtube?.media ?? const YouTubeMediaState();
  @override
  bool get loaded => _online ? _media.hasVideo : local.loaded;
  @override
  bool get playing => _online ? _media.playing : local.playing;
  @override
  bool get busy => _pending > 0 || (!_online && local.busy);
  @override
  bool get muted => _online && _media.muted;
  @override
  bool get pitchPending => _online && _media.pitchStatus == 'loading';
  @override
  bool get canPitch =>
      loaded &&
      (_online
          ? !_media.isAd &&
                _media.pitchStatus != 'loading' &&
                _media.pitchStatus != 'unavailable'
          : local.canPitch);
  @override
  bool get canSpeed => loaded && (_online ? !_media.isAd : local.canSpeed);
  @override
  bool get canLoop =>
      loaded && (_online ? !_media.isAd && _media.duration > 0 : local.canLoop);
  @override
  bool get canSeek =>
      loaded && duration > Duration.zero && (!_online || !_media.isAd);
  @override
  String get title => _online ? _media.title : local.title;
  @override
  String get sourceLabel =>
      _online ? 'YouTube · navegador integrado' : 'Ficheiro local';
  @override
  String? get message =>
      _message ??
      (_online
          ? _youtube?.error ??
                (_media.isAd
                    ? 'Anúncio · aguarde o vídeo para usar os ajustes.'
                    : _media.pitchMessage.isEmpty
                    ? null
                    : _media.pitchMessage)
          : local.message);
  static Duration _duration(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());
  @override
  Duration get position =>
      _online ? _duration(_media.position) : local.position;
  @override
  Duration get duration =>
      _online ? _duration(_media.duration) : local.duration;
  @override
  double get pitch => _online ? _media.pitch : local.pitch;
  @override
  int? get detectedKeyRoot => _online ? _media.keyRoot : null;
  @override
  String get detectedKeyMode => _online ? _media.keyMode : '';
  @override
  String get keyDetectionStatus => _online ? _media.keyStatus : 'unavailable';
  @override
  double get speed => _online ? _media.speed : local.speed;
  @override
  Duration? get markerA => _online
      ? (_media.loopA == null ? null : _duration(_media.loopA!))
      : local.markerA;
  @override
  Duration? get markerB => _online
      ? (_media.loopB == null ? null : _duration(_media.loopB!))
      : local.markerB;
  @override
  bool get loopEnabled => _online ? _media.loopEnabled : local.loopEnabled;

  Future<void> _ensureYouTube({Uri? first}) async {
    if (_disposed || _youtube != null) return;
    final session = _youtubeFactory();
    _youtube = session;
    session.addListener(_changed);
    _changed(); // Mount the platform view before loading the document.
    try {
      await session.start(first ?? _youtubeHome);
    } on Object {
      if (identical(_youtube, session)) {
        session.removeListener(_changed);
        session.dispose();
        _youtube = null;
      }
      rethrow;
    }
  }

  void _cancelRestore() {
    final cancellation = _restoreCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<bool> _releaseLocal() async {
    await local.close();
    if (!local.hasResource) return true;
    _message =
        local.message ??
        'Não foi possível fechar o áudio local. Tente novamente.';
    return false;
  }

  Future<void> openYouTube() {
    ++_sourceIntentRevision;
    _cancelRestore();
    _youtubePauseRequested = false;
    _lastNativeVideoTouch = null;
    return _run(() async {
      if (!await _releaseLocal() || _disposed) return;
      await _ensureYouTube();
      if (_disposed) return;
      _online = true;
    });
  }

  /// Two-page mode: plays the video chosen in the browse page here, in the
  /// player page (the one with the audio bridge).
  Future<void> playWatch(Uri watch) {
    ++_sourceIntentRevision;
    _cancelRestore();
    _youtubePauseRequested = false;
    _lastNativeVideoTouch = null;
    return _run(() async {
      if (!await _releaseLocal() || _disposed) return;
      if (_youtube == null) {
        await _ensureYouTube(first: watch);
      } else {
        await _youtube!.playWatch(watch);
      }
      if (_disposed) return;
      _online = true;
    });
  }

  Future<void> search(String query) {
    if (query.trim().isEmpty) return Future<void>.value();
    ++_sourceIntentRevision;
    _cancelRestore();
    _youtubePauseRequested = false;
    _lastNativeVideoTouch = null;
    return _run(() async {
      if (!await _releaseLocal() || _disposed) return;
      await _ensureYouTube();
      if (_disposed) return;
      _online = true;
      await _youtube!.search(query.trim());
    });
  }

  Future<void> pickFile() {
    ++_sourceIntentRevision;
    _cancelRestore();
    _youtubePauseRequested = true;
    return _run(() async {
      await _youtube?.command('pause');
      if (_disposed) return;
      await local.pickFile();
      if (local.loaded) _online = false;
    });
  }

  Future<void> loadSample() {
    ++_sourceIntentRevision;
    _cancelRestore();
    _youtubePauseRequested = true;
    return _run(() async {
      await _youtube?.command('pause');
      if (_disposed) return;
      await local.loadSample();
      _online = false;
    });
  }

  /// Loads an approved, already mixed local WAV on the shared transport.
  /// Newer media choices and lifecycle pause cannot start an old preview.
  Future<void> loadApprovedRhythmPreview(Uint8List bytes) {
    final intent = ++_sourceIntentRevision;
    final pauseRevision = _pauseRevision;
    final videoId = _online ? _media.videoId : null;
    _cancelRestore();
    bool active() =>
        !_disposed &&
        intent == _sourceIntentRevision &&
        (videoId == null || !_online || _media.videoId == videoId);
    return _run(() async {
      if (!active()) return;
      await _youtube?.command('pause');
      if (!active()) return;
      final loaded = await local.loadGeneratedPreview(bytes, canCommit: active);
      if (!loaded) {
        if (active()) _message = local.message;
        return;
      }
      if (!active()) return;
      _online = false;
      _youtubePauseRequested = true;
      _changed();
      if (pauseRevision != _pauseRevision) return;
      await local.playPause();
    });
  }

  Future<void> stopRhythmPreview() {
    ++_sourceIntentRevision;
    if (!isRhythmPreview) return Future<void>.value();
    ++_pauseRevision;
    _youtubePauseRequested = true;
    return local.pause();
  }

  @override
  Future<void> playPause() {
    // Stopping audible playback must never queue behind DSP/network work.
    if (loaded && playing && !muted) return pause();
    final revision = _pauseRevision;
    final interruption = local.interruptionRevision;
    // Capture the user's intent before queued work or page autoplay changes it.
    final onlineAction = muted
        ? 'unmute'
        : playing
        ? 'pause'
        : 'play';
    return _run(() async {
      if (!loaded ||
          revision != _pauseRevision ||
          interruption != local.interruptionRevision) {
        return;
      }
      if (_online) {
        await local.pause();
        if (_disposed || revision != _pauseRevision) return;
        _youtubePauseRequested = onlineAction == 'pause';
        await _youtube!.command(onlineAction);
        if (!_disposed && revision != _pauseRevision) {
          await _youtube?.command('pause');
        }
      } else {
        await _youtube?.command('pause');
        if (_disposed ||
            revision != _pauseRevision ||
            interruption != local.interruptionRevision) {
          return;
        }
        await local.playPause();
        if (!_disposed && revision != _pauseRevision) await local.pause();
      }
    });
  }

  /// Lifecycle pause must not wait behind a network/preset readiness operation.
  Future<void> pause() async {
    if (_disposed) return;
    if (_automatedControlDepth == 0) _manualControlRevision++;
    _pauseRevision++;
    _cancelRestore();
    _youtubePauseRequested = true;
    _lastNativeVideoTouch = null;
    try {
      await Future.wait<void>(<Future<void>>[
        local.pause(),
        if (_youtube != null) _youtube!.command('pause'),
      ]);
    } on Object {
      _message = 'Não foi possível pausar a reprodução. Tente novamente.';
    }
    _changed();
  }

  @override
  Future<void> seek(Duration target) => _run(() async {
    if (!canSeek) return;
    final ms = target.inMilliseconds.clamp(0, duration.inMilliseconds);
    if (_online) {
      await _youtube!.command('seekTo', ms / 1000);
    } else {
      await local.seek(Duration(milliseconds: ms));
    }
  });

  @override
  Future<void> changePitch(double value) => _run(() async {
    if (!value.isFinite || value < -12 || value > 12) return;
    if (!canPitch && !(value == 0 && loaded && _online && !_media.isAd)) return;
    if (_online) {
      await _youtube!.command('pitch', value);
    } else {
      await local.changePitch(value);
    }
  });
  @override
  Future<void> changeSpeed(double value) => _run(() async {
    if (!value.isFinite ||
        value < (_online ? .25 : .5) ||
        value > 2 ||
        !canSpeed) {
      return;
    }
    if (_online) {
      await _youtube!.command('speed', value);
    } else {
      await local.changeSpeed(value);
    }
  });
  @override
  Future<void> markA() => _run(() async {
    if (!canLoop) return;
    if (_online) {
      await _youtube!.command('markA');
    } else {
      await local.markA();
    }
  });
  @override
  Future<void> markB() => _run(() async {
    if (!canLoop) return;
    if (_online) {
      await _youtube!.command('markB');
    } else {
      await local.markB();
    }
  });
  @override
  Future<void> toggleLoop() => _run(() async {
    if (!canLoop) return;
    if (_online) {
      await _youtube!.command('toggleLoop');
    } else {
      await local.toggleLoop();
    }
  });
  @override
  Future<void> clearLoop() => _run(() async {
    if (_online) {
      await _youtube!.command('clearLoop');
    } else {
      await local.clearLoop();
    }
  });
  @override
  Future<void> resetProcessing() => _run(() async {
    if (!loaded) return;
    if (_online) {
      await _youtube!.command('pitch', 0);
      await _youtube!.command('speed', 1);
      await _youtube!.command('clearLoop');
    } else {
      await local.resetProcessing();
    }
  });

  PlayerPreset? snapshot(String name) {
    if (!loaded ||
        isRhythmPreview ||
        busy ||
        (_online && (_media.isAd || _media.pitchStatus == 'loading'))) {
      return null;
    }
    return PlayerPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      title: title.isEmpty ? 'Vídeo do YouTube' : title,
      sourceId: _online ? _media.videoId : local.sourceId,
      locator: _online ? _media.videoId : local.locator ?? '',
      youtube: _online,
      pitch: pitch,
      speed: speed,
      positionMs: position.inMilliseconds,
      aMs: markerA?.inMilliseconds,
      bMs: markerB?.inMilliseconds,
      loop: loopEnabled,
    );
  }

  bool _youtubeReady(String videoId) =>
      _media.hasVideo &&
      _media.videoId == videoId &&
      _media.duration > 0 &&
      !_media.isAd;

  Future<bool> _waitForYouTube(
    String videoId,
    Completer<void> cancellation,
  ) async {
    if (_disposed || cancellation.isCompleted) return false;
    if (_youtubeReady(videoId)) return true;
    final session = _youtube!;
    final ready = Completer<bool>();
    void check() {
      if (ready.isCompleted) return;
      if (_disposed || cancellation.isCompleted || session.error != null) {
        ready.complete(false);
      } else if (_youtubeReady(videoId)) {
        ready.complete(true);
      }
    }

    session.addListener(check);
    final timer = Timer(const Duration(seconds: 25), () {
      if (!ready.isCompleted) ready.complete(false);
    });
    unawaited(
      cancellation.future.then((_) {
        if (!ready.isCompleted) ready.complete(false);
      }),
    );
    check();
    try {
      return await ready.future;
    } finally {
      timer.cancel();
      session.removeListener(check);
    }
  }

  Future<void> restore(PlayerPreset preset) {
    ++_sourceIntentRevision;
    _lastRestoreSucceeded = false;
    _cancelRestore();
    final cancellation = Completer<void>();
    _restoreCancellation = cancellation;
    _youtubePauseRequested = !preset.youtube;
    _lastNativeVideoTouch = null;
    bool active() => !_disposed && !cancellation.isCompleted;
    return _run(() async {
      if (!active()) return;
      await local.pause();
      if (!active()) return;
      // Let an already-running ad finish while restoring this same video.
      // User/lifecycle pause remains immediate and cancels restoration.
      if (!preset.youtube || _media.videoId != preset.locator || !_media.isAd) {
        await _youtube?.command('pause');
      }
      if (!active()) return;
      if (preset.youtube) {
        if (!await _releaseLocal() || !active()) return;
        await _ensureYouTube();
        if (!active()) return;
        _online = true;
        // A saved YouTube item can be opened directly from Stage/collections,
        // without visiting the browser screen first. Mount the shared surface
        // before awaiting page readiness; otherwise the UI remains on local
        // media until the entire restore operation has already finished.
        _changed();
        if (_media.videoId != preset.locator || !_media.hasVideo) {
          await _youtube!.openVideo(preset.locator);
        }
        if (!active()) return;
        final ready = await _waitForYouTube(preset.locator, cancellation);
        if (!active()) return;
        if (!ready) {
          _message = _youtube?.error ?? 'Abra um vídeo com duração definida e volte a aplicar a predefinição.';
          return;
        }
        Future<bool> command(String action, [num? value]) async {
          if (!active() || !_youtubeReady(preset.locator)) return false;
          await _youtube!.command(action, value);
          return active() && _youtubeReady(preset.locator);
        }

        if (!await command('pause')) return;
        if (!await command('clearLoop')) return;
        if (!await command('speed', preset.speed)) return;
        if (!await command('pitch', preset.pitch)) return;
        final validA =
            preset.aMs != null &&
            preset.aMs! >= 0 &&
            duration.inMilliseconds - preset.aMs! >= 250;
        final validMarkers =
            validA &&
            preset.bMs != null &&
            preset.bMs! - preset.aMs! >= 250 &&
            preset.bMs! <= duration.inMilliseconds;
        if (validA) {
          if (!await command('seekTo', preset.aMs! / 1000)) return;
          if (!await command('markA')) return;
        }
        if (validMarkers) {
          if (!await command('seekTo', preset.bMs! / 1000)) return;
          if (!await command('markB')) return;
          if (!preset.loop && !await command('toggleLoop')) return;
        }
        if (!await command(
          'seekTo',
          _restoredPosition(preset, validMarkers) / 1000,
        )) {
          return;
        }
      } else {
        _online = false;
        if (local.locator != preset.locator || !local.loaded) {
          await local.load(
            LocalFileSource(
              id: preset.sourceId,
              displayName: preset.title,
              locator: Uri.parse(preset.locator),
            ),
          );
        }
        if (!active() || !local.loaded) return;
        Future<bool> apply(Future<void> Function() operation) async {
          if (!active()) return false;
          await operation();
          if (local.message != null) {
            _message = local.message;
            return false;
          }
          return active();
        }

        if (!await apply(local.resetProcessing)) return;
        if (local.canPitch &&
            !await apply(() => local.changePitch(preset.pitch))) {
          return;
        }
        if (!await apply(() => local.changeSpeed(preset.speed))) return;
        final validA =
            local.canLoop &&
            preset.aMs != null &&
            preset.aMs! >= 0 &&
            duration.inMilliseconds - preset.aMs! >= 250;
        final validMarkers =
            validA &&
            preset.bMs != null &&
            preset.bMs! - preset.aMs! >= 250 &&
            preset.bMs! <= duration.inMilliseconds;
        if (validMarkers) {
          if (!await apply(
            () => local.setLoopMarkers(
              Duration(milliseconds: preset.aMs!),
              Duration(milliseconds: preset.bMs!),
            ),
          )) {
            return;
          }
          if (preset.loop && !await apply(local.toggleLoop)) return;
        } else if (validA) {
          if (!await apply(
            () => local.seek(Duration(milliseconds: preset.aMs!)),
          )) {
            return;
          }
          if (!await apply(local.markA)) return;
        }
        if (!await apply(
          () => local.seek(
            Duration(milliseconds: _restoredPosition(preset, validMarkers)),
          ),
        )) {
          return;
        }
      }
      if (active()) {
        _lastRestoreSucceeded = true;
        // A recovered item stays paused even if the page later attempts autoplay.
        // The user's explicit Play/open/search releases this guard.
        _youtubePauseRequested = true;
      }
    }).whenComplete(() {
      if (!cancellation.isCompleted) cancellation.complete();
      if (identical(_restoreCancellation, cancellation)) {
        _restoreCancellation = null;
      }
    });
  }

  int _restoredPosition(PlayerPreset preset, bool validMarkers) {
    final position = preset.positionMs.clamp(0, duration.inMilliseconds);
    if (preset.loop &&
        validMarkers &&
        (position < preset.aMs! || position >= preset.bMs!)) {
      return preset.aMs!;
    }
    return position;
  }

  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future<void>.value();
    if (_automatedControlDepth == 0) _manualControlRevision++;
    _pending++;
    _changed();
    final result = _tail
        .then((_) async {
          if (_disposed) return;
          _message = null;
          try {
            await action();
          } on Object {
            _message = 'Não foi possível concluir. Tente novamente.';
          }
        })
        .whenComplete(() {
          _pending--;
          _changed();
        });
    _tail = result;
    return result;
  }

  void _changed() {
    if (_disposed) return;
    final lastTouch = _lastNativeVideoTouch;
    if (_online &&
        _youtubePauseRequested &&
        _media.playing &&
        lastTouch != null &&
        DateTime.now().difference(lastTouch) < const Duration(seconds: 5)) {
      // The restored video stays paused against page autoplay. A real touch
      // on its WebView followed by native playback releases that guard.
      _youtubePauseRequested = false;
      _lastNativeVideoTouch = null;
    }
    if (_pending == 0 &&
        !_pausingYouTube &&
        _media.playing &&
        (_youtubePauseRequested || (!_online && local.hasResource))) {
      _pausingYouTube = true;
      unawaited(
        _youtube!
            .command('pause')
            .catchError((Object _) {
              _message = 'Não foi possível pausar o YouTube. Tente novamente.';
            })
            .whenComplete(() => _pausingYouTube = false),
      );
    }
    notifyListeners();
  }

  void noteNativeVideoTouch() {
    if (_online && _youtubePauseRequested && !_disposed) {
      _lastNativeVideoTouch = DateTime.now();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelRestore();
    local.removeListener(_changed);
    _youtube?.removeListener(_changed);
    local.dispose();
    _youtube?.dispose();
    _youtube = null;
    super.dispose();
  }
}
