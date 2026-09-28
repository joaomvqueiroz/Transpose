import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';
import 'package:video_player/video_player.dart';

import 'native_audio_media_loader.dart';
import 'local_media_importer.dart';
import 'video_player_media_loader.dart';
import '../loop_observation.dart';

/// Owns the local source used by the main player, including its native output.
///
/// All commands, including source replacement and [close], are serialized.
/// Android audio uses native Media3 A/B clipping. Video A/B is a coarse seek
/// fallback checked every 250 ms; it is not sample-accurate or gapless.
class LocalPlayerController extends ChangeNotifier {
  LocalPlayerController({
    MediaLoader? loader,
    LocalMediaImporter? importer,
    Future<PlatformFile?> Function()? filePicker,
  }) : _loader = loader ?? VideoPlayerMediaLoader(),
       _importer = importer ?? LocalMediaImporter(),
       _filePicker = filePicker ?? FilePicker.pickFile {
    _session = PlayerSession(sessionId: 'studio-local-player', loader: _loader);
    _states = _session.states.listen((_) => _notify());
  }

  final MediaLoader _loader;
  final LocalMediaImporter _importer;
  final Future<PlatformFile?> Function() _filePicker;
  late final PlayerSession _session;
  late final StreamSubscription<PlayerState> _states;
  Future<void> _tail = Future<void>.value();
  Timer? _refresh;
  VideoPlayerController? _video;
  NativeAudioLoadedMedia? _audio;
  GeneratedLocalMedia? _ownedPreview;
  int _pending = 0;
  bool _disposed = false;
  bool _picking = false;
  bool _loopSeekPending = false;
  bool _videoLoop = false;
  double _pitch = 0;
  double _speed = 1;
  Duration? _markerA;
  Duration? _markerB;
  String? _message;

  bool get loaded =>
      _session.source != null &&
      _session.state != PlayerState.error &&
      _session.state != PlayerState.loading;

  LoopObservation? get loopObservation {
    final audio = _audio;
    if (!loaded || audio == null || !audio.loopEventsAvailable) return null;
    return LoopObservation(
      epoch: audio.loopEpoch,
      count: audio.loopCount,
      ready: audio.nativeReady,
      playing: audio.nativePlaying,
    );
  }

  /// Also true after a failed release. Check this after [close] before handing
  /// audio ownership to another player so a release error cannot overlap output.
  bool get hasResource => _session.source != null;
  bool get playing => _session.state == PlayerState.playing;
  int get interruptionRevision => _session.interruptionRevision;
  bool get busy => _pending > 0;
  bool get canPitch => loaded && _audio != null;
  bool get canSpeed => loaded && (_audio != null || _video != null);
  bool get canLoop =>
      loaded && duration > Duration.zero && (_audio != null || _video != null);
  String get title => _session.source?.displayName ?? '';
  String get sourceId => _session.source?.id ?? '';
  String? get locator => _session.source?.locator.toString();
  Duration get position => _session.position ?? Duration.zero;
  Duration get duration => _session.duration ?? Duration.zero;
  double get pitch => _pitch;
  double get speed => _speed;
  Duration? get markerA => _markerA;
  Duration? get markerB => _markerB;
  bool get loopEnabled => loaded && (_audio?.loopEnabled ?? _videoLoop);
  VideoPlayerController? get videoController => _video;
  String? get message => _message;

  Future<void> load(LocalFileSource source) => _run(() async {
    await _load(source);
    await _clearOwnedPreview();
  });

  /// A generated WAV replaces the source only after it is staged. On decoder
  /// failure, restore the prior local selection and controls without autoplay.
  Future<bool> loadGeneratedPreview(
    Uint8List bytes, {
    bool Function()? canCommit,
  }) async {
    var committed = false;
    await _run(() async {
      final previous = _session.source;
      final previousPitch = _pitch, previousSpeed = _speed;
      final previousPosition = position;
      final previousA = _markerA, previousB = _markerB;
      final previousLoop = loopEnabled;
      final staged = await _importer.importGeneratedPreview(bytes);
      bool active() => !_disposed && (canCommit?.call() ?? true);
      if (!active()) {
        await staged.dispose();
        return;
      }
      try {
        await _load(staged.source);
        if (!active()) {
          throw StateError('A newer media request superseded the preview.');
        }
        final old = _ownedPreview;
        _ownedPreview = staged;
        committed = true;
        try {
          await old?.dispose();
        } on FileSystemException {
          // Playback is already committed; cache cleanup can be retried later.
        }
      } on Object {
        // PlayerSession releases the previous decoder before loading. Reopen
        // its still-existing file and restore the controls in a paused state.
        if (!_disposed &&
            previous is LocalFileSource &&
            !identical(_session.source, previous)) {
          try {
            await _load(previous);
            if (canSpeed) {
              await _setParameters(pitch: previousPitch, speed: previousSpeed);
            }
            _markerA = previousA;
            _markerB = previousB;
            if (previousLoop && previousA != null && previousB != null) {
              await _applyLoop(previousA, previousB);
            }
            await _session.seek(
              previousPosition > duration ? duration : previousPosition,
            );
          } on Object {
            _message = 'A prévia falhou e não foi possível restaurar a faixa anterior.';
          }
        }
        if (identical(_session.source, staged.source)) {
          try {
            _detach();
            await _session.unload();
          } on Object {
            // Keep the lease if the decoder still owns the generated file.
          }
        }
        if (identical(_session.source, staged.source)) {
          final old = _ownedPreview;
          _ownedPreview = staged;
          try {
            await old?.dispose();
          } on FileSystemException {
            // The old decoder was released before this source was loaded.
          }
          _message =
              'A prévia foi cancelada, mas a saída ainda está a ser libertada.';
        } else {
          try {
            await staged.dispose();
          } on FileSystemException {
            // The generated copy is disposable after decoder release.
          }
        }
        if (identical(_session.source, previous) && !_disposed) {
          _pitch = previousPitch;
          _speed = previousSpeed;
          _markerA = previousA;
          _markerB = previousB;
          _videoLoop = previousLoop;
          _attachCurrent();
        }
        _message ??=
            'Não foi possível abrir a prévia; a faixa anterior foi mantida.';
      }
    });
    return committed;
  }

  Future<void> _clearOwnedPreview() async {
    final old = _ownedPreview;
    _ownedPreview = null;
    try {
      await old?.dispose();
    } on FileSystemException {
      // A released decoder may briefly hold the file on some devices.
    }
  }

  @visibleForTesting
  void debugSeedProcessing({
    required double pitch,
    required double speed,
    required Duration markerA,
    required Duration markerB,
    required bool loop,
  }) {
    _pitch = pitch;
    _speed = speed;
    _markerA = markerA;
    _markerB = markerB;
    _videoLoop = loop;
  }

  @visibleForTesting
  bool get debugVideoLoop => _videoLoop;

  Future<void> _load(LocalFileSource source) async {
    _detach();
    _resetValues();
    await _session.load(source);
    _attachCurrent();
  }

  void _attachCurrent() {
    if (_refresh != null || _disposed) return;
    final MediaLoader loader = _loader;
    if (loader is VideoPlayerMediaLoader) {
      _video = loader.currentController;
      _audio = loader.currentAudio;
    }
    _video?.addListener(_notify);
    _refresh = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
  }

  Future<void> loadSample() => _run(() async {
    final ByteData data = await rootBundle.load('assets/qa_tone.wav');
    final source = await _importer.importSample(data);
    if (!_disposed) {
      await _load(source);
      await _clearOwnedPreview();
    }
  });

  Future<void> pickFile() async {
    if (_disposed || _picking) return;
    _picking = true;
    try {
      await _run(() async {
        final PlatformFile? picked = await _filePicker();
        if (picked == null || _disposed) return;
        _message = 'A importar uma cópia para o Transpono…';
        _notify();
        final LocalFileSource source;
        try {
          source = await _importer.importPickedFile(picked);
        } on Object {
          _message =
              'Não foi possível importar. Verifique o espaço livre e o acesso '
              'ao ficheiro. A faixa anterior foi mantida.';
          return;
        }
        if (_disposed) return;
        _message = null;
        await _load(source);
        await _clearOwnedPreview();
      });
    } finally {
      _picking = false;
    }
  }

  Future<void> playPause() {
    final int revision = interruptionRevision;
    return _run(() async {
      if (!loaded || revision != interruptionRevision) return;
      if (playing) {
        await _session.pause();
      } else {
        if (_session.state == PlayerState.ended) {
          await _session.seek(loopEnabled ? _markerA! : Duration.zero);
        }
        if (revision != interruptionRevision) return;
        await _session.play();
      }
    });
  }

  /// Queue this even during loading/play: backgrounding must pause pending play.
  Future<void> pause() => _run(() async {
    if (playing) await _session.pause();
  });

  Future<void> seek(Duration target) => _run(() async {
    if (!loaded) return;
    final int milliseconds = target.inMilliseconds.clamp(
      0,
      duration.inMilliseconds,
    );
    final Duration next = Duration(milliseconds: milliseconds);
    if (loopEnabled &&
        (_markerA == null ||
            _markerB == null ||
            next < _markerA! ||
            next >= _markerB!)) {
      await _disableLoop();
    }
    await _session.seek(next);
  });

  Future<void> changePitch(double value) => _run(() async {
    if (!canPitch) {
      _message = 'O tom está disponível para ficheiros de áudio no Android.';
      return;
    }
    if (!value.isFinite || value < -12 || value > 12) {
      _message = 'Escolhe um tom entre −12 e +12 semitons.';
      return;
    }
    await _audio!.setParameters(semitones: value, speed: _speed);
    _pitch = value;
  });

  Future<void> changeSpeed(double value) => _run(() async {
    if (!canSpeed) return;
    if (!value.isFinite || value < 0.5 || value > 2) {
      _message = 'Escolhe uma velocidade entre 0,5× e 2×.';
      return;
    }
    await _setParameters(pitch: _pitch, speed: value);
  });

  Future<void> _setParameters({
    required double pitch,
    required double speed,
  }) async {
    if (_audio != null) {
      await _audio!.setParameters(semitones: pitch, speed: speed);
    } else if (_video != null) {
      await _video!.setPlaybackSpeed(speed);
    } else {
      return;
    }
    _pitch = pitch;
    _speed = speed;
  }

  Future<void> markA() => _run(() async {
    if (!canLoop) return;
    final Duration a = position;
    if (duration - a < const Duration(milliseconds: 250) ||
        (_markerB != null &&
            _markerB! - a < const Duration(milliseconds: 250))) {
      _message = 'Deixa pelo menos 0,25 s entre A e B e antes do fim da faixa.';
      return;
    }
    if (loopEnabled) await _applyLoop(a, _markerB!);
    _markerA = a;
  });

  Future<void> markB() => _run(() async {
    if (!canLoop) return;
    final Duration b = position;
    if (_markerA == null || b - _markerA! < const Duration(milliseconds: 250)) {
      _message = 'Marca A primeiro e coloca B pelo menos 0,25 s depois.';
      return;
    }
    if (loopEnabled) await _applyLoop(_markerA!, b);
    _markerB = b;
  });

  Future<void> setLoopMarkers(Duration a, Duration b) => _run(() async {
    if (!canLoop) return;
    if (a.isNegative ||
        b - a < const Duration(milliseconds: 250) ||
        b > duration) {
      _message =
          'O loop precisa de pelo menos 0,25 s entre A e B, dentro da faixa.';
      return;
    }
    if (loopEnabled) await _applyLoop(a, b);
    _markerA = a;
    _markerB = b;
  });

  Future<void> toggleLoop() => _run(() async {
    if (!canLoop) return;
    if (loopEnabled) {
      await _disableLoop();
      return;
    }
    final Duration? a = _markerA;
    final Duration? b = _markerB;
    if (a == null || b == null) {
      _message = 'Marca os pontos A e B para ativar o loop.';
      return;
    }
    await _applyLoop(a, b);
  });

  Future<void> _applyLoop(Duration a, Duration b) async {
    if (_audio != null) {
      await _audio!.setLoop(LoopRange(start: a, end: b));
    } else if (_video != null) {
      if (position < a || position >= b) await _session.seek(a);
      _videoLoop = true;
    }
  }

  Future<void> _disableLoop() async {
    if (_audio?.loopEnabled == true) await _audio!.clearLoop();
    _videoLoop = false;
  }

  Future<void> clearLoop() => _run(() async {
    await _disableLoop();
    _markerA = null;
    _markerB = null;
  });

  Future<void> resetProcessing() => _run(() async {
    if (!loaded) return;
    await _setParameters(pitch: 0, speed: 1);
    await _disableLoop();
    _markerA = null;
    _markerB = null;
  });

  /// Releases output before a different player takes over; remains reusable.
  Future<void> close() => _run(() async {
    _detach();
    await _session.unload();
    await _clearOwnedPreview();
    _resetValues();
  });

  void _tick() {
    if (_disposed) return;
    _notify();
    if (_pending > 0 ||
        _loopSeekPending ||
        !_videoLoop ||
        _markerA == null ||
        _markerB == null ||
        _video == null ||
        (!playing && _session.state != PlayerState.ended) ||
        position < _markerB!) {
      return;
    }
    _loopSeekPending = true;
    unawaited(
      _run(() async {
        if (!_videoLoop || _markerA == null || _video == null) return;
        final bool ended = _session.state == PlayerState.ended;
        await _session.seek(_markerA!);
        if (ended) await _session.play();
      }).whenComplete(() => _loopSeekPending = false),
    );
  }

  Future<void> _run(Future<void> Function() action) {
    if (_disposed) return Future<void>.value();
    _pending++;
    _notify();
    final Future<void> result = _tail
        .then((_) async {
          if (_disposed) return;
          _message = null;
          try {
            await action();
          } on Object {
            _message = 'Não foi possível concluir. Tenta novamente ou escolhe outro ficheiro.';
            if (_session.source == null) _detach();
          } finally {
            _notify();
          }
        })
        .whenComplete(() {
          _pending--;
          _notify();
        });
    _tail = result;
    return result;
  }

  void _resetValues() {
    _pitch = 0;
    _speed = 1;
    _markerA = null;
    _markerB = null;
    _videoLoop = false;
  }

  void _detach() {
    _refresh?.cancel();
    _refresh = null;
    _video?.removeListener(_notify);
    _video = null;
    _audio = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detach();
    unawaited(_states.cancel());
    unawaited(
      _tail
          .then((_) async {
            await _session.dispose();
            await _clearOwnedPreview();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }
}
