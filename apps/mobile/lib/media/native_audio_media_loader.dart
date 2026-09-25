import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:player_core/player_core.dart';

/// Android audio-only Media3 adapter. The same native player owns playback and
/// pitch/speed, so no parallel DSP output is started for the loaded resource.
final class NativeAudioMediaLoader implements MediaLoader {
  NativeAudioMediaLoader({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('transpose/native_audio_player');

  final MethodChannel _channel;
  NativeAudioLoadedMedia? currentAudio;

  @override
  Future<LoadedMedia> load(MediaSource source) async {
    if (source is! LocalFileSource) {
      throw UnsupportedError('Only local files are supported.');
    }
    final NativeAudioLoadedMedia media = NativeAudioLoadedMedia._(_channel);
    try {
      await _channel.invokeMethod<Object>('load', <String, Object>{
        'uri': source.locator.toString(),
      });
      await media._waitReady();
      media._startPolling();
      currentAudio = media;
      media._onRelease = () {
        if (identical(currentAudio, media)) currentAudio = null;
      };
      return media;
    } on Object {
      await _channel.invokeMethod<void>('release');
      rethrow;
    }
  }
}

final class NativeAudioLoadedMedia implements InterruptedLoadedMedia {
  NativeAudioLoadedMedia._(this._channel);

  final MethodChannel _channel;
  final StreamController<void> _ends = StreamController<void>.broadcast();
  final StreamController<void> _interruptions =
      StreamController<void>.broadcast(sync: true);
  Timer? _pollTimer;
  void Function()? _onRelease;
  Duration? _duration;
  Duration _position = Duration.zero;
  bool _released = false;
  bool _polling = false;
  bool _endSent = false;
  double _requestedSemitones = 0;
  double _requestedSpeed = 1;
  double _platformPitch = 1;
  double _platformSpeed = 1;
  LoopRange? _loopRange;
  bool _loopEnabled = false;
  int _loopCount = 0;
  int _loopEpoch = 0;
  int _snapshotRevision = -1;
  bool _loopEventsAvailable = false;
  bool _nativeReady = false;
  bool _nativePlaying = false;
  Map<Object?, Object?> _lastSnapshot = <Object?, Object?>{};
  int _interruptionRevision = 0;

  double get requestedSemitones => _requestedSemitones;
  double get requestedSpeed => _requestedSpeed;

  /// Media3-reported parameters, not an acoustic output measurement.
  double get platformPitch => _platformPitch;
  double get platformSpeed => _platformSpeed;
  LoopRange? get loopRange => _loopRange;
  bool get loopEnabled => _loopEnabled;

  /// Complete A-to-B repetitions reported by the native engine. Seeks are not
  /// repetitions, and a first partial traversal is excluded by the engine.
  int get loopCount => _loopCount;

  /// Changes on source/loop replacement or explicit seeking; never compare
  /// counts across epochs. Pausing/resuming alone keeps the epoch unchanged.
  int get loopEpoch => _loopEpoch;

  /// False for older/incompatible native implementations. Consumers must not
  /// invent repetition counts from position changes when this is unavailable.
  bool get loopEventsAvailable => _loopEventsAvailable && !_released;
  bool get nativeReady => _nativeReady && !_released;
  bool get nativePlaying => _nativePlaying && !_released;

  @override
  Duration? get duration => _duration;

  @override
  Duration get position => _position;

  @override
  Stream<void> get endEvents => _ends.stream;

  @override
  Stream<void> get interruptionEvents => _interruptions.stream;

  Future<void> _waitReady() async {
    for (int attempt = 0; attempt < 50; ++attempt) {
      final Map<Object?, Object?> state = await _snapshot();
      if (state['ready'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Native audio did not prepare within five seconds.');
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_released || _polling) return;
      _polling = true;
      unawaited(
        _snapshot()
            .catchError((Object _) {
              // A transient platform failure must not create a false end event.
              return <Object?, Object?>{};
            })
            .whenComplete(() => _polling = false),
      );
    });
  }

  Future<Map<Object?, Object?>> _snapshot() async {
    final Map<Object?, Object?> state =
        await _channel.invokeMapMethod<Object?, Object?>('snapshot') ??
        <Object?, Object?>{};
    if (_released) return state;
    final int? snapshotRevision = (state['snapshotRevision'] as num?)?.toInt();
    if (snapshotRevision != null && snapshotRevision <= _snapshotRevision) {
      // Polling and command acknowledgements may complete out of order. Never
      // roll back a confirmed epoch/count (or position/playback state).
      return _lastSnapshot;
    }
    if (snapshotRevision != null) _snapshotRevision = snapshotRevision;
    _lastSnapshot = state;
    _nativeReady = state['ready'] == true;
    _nativePlaying = state['playing'] == true;
    final int? durationMs = state['durationMs'] as int?;
    if (durationMs != null && durationMs > 0) {
      _duration = Duration(milliseconds: durationMs);
    }
    final int? positionMs = state['positionMs'] as int?;
    if (positionMs != null && positionMs >= 0) {
      _position = Duration(milliseconds: positionMs);
    }
    _loopEnabled = state['loopEnabled'] == true;
    final int? loopEpoch = (state['loopEpoch'] as num?)?.toInt();
    final int? loopCount = (state['loopCount'] as num?)?.toInt();
    if (loopCount != null && loopCount >= 0) _loopCount = loopCount;
    _loopEventsAvailable =
        state['loopEventsAvailable'] == true &&
        snapshotRevision != null &&
        loopEpoch != null &&
        loopEpoch >= 0 &&
        loopCount != null &&
        loopCount >= 0;
    if (_loopEventsAvailable) {
      _loopEpoch = loopEpoch!;
      _loopCount = loopCount!;
    }
    _platformSpeed = (state['speed'] as num?)?.toDouble() ?? _platformSpeed;
    _platformPitch = (state['pitch'] as num?)?.toDouble() ?? _platformPitch;
    final int revision =
        (state['interruptionRevision'] as num?)?.toInt() ??
        _interruptionRevision;
    if (revision > _interruptionRevision &&
        state['playing'] == false &&
        state['playWhenReady'] == false) {
      _interruptionRevision = revision;
      _interruptions.add(null);
    }
    if (state['ended'] == true && !_endSent) {
      _endSent = true;
      _ends.add(null);
    }
    return state;
  }

  @override
  Future<void> play() async {
    _requireActive();
    _endSent = false;
    final int revision = _interruptionRevision;
    await _channel.invokeMethod<Object>('play', <String, Object>{
      'interruptionRevision': revision,
    });
    Map<Object?, Object?> state = await _snapshot();
    // A seek can be accepted before Media3 has buffered its new position.
    // playWhenReady acknowledges the intent; wait for actual playback without
    // converting a short buffering interval into a fatal media-load error.
    for (
      int attempt = 0;
      attempt < 40 &&
          !_released &&
          revision == _interruptionRevision &&
          state['playing'] != true &&
          state['playWhenReady'] == true &&
          state['ended'] != true;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_released) throw StateError('Native audio was released.');
      state = await _snapshot();
    }
    if (revision != _interruptionRevision) {
      throw const MediaPlaybackInterrupted();
    }
    if (state['playing'] != true) {
      if (state['playWhenReady'] == false) {
        // A denied focus request leaves the source prepared and silent. This
        // is not a corrupt/unsupported file and must not destroy the session.
        _interruptions.add(null);
        throw const MediaPlaybackInterrupted();
      }
      throw StateError('Native audio did not play.');
    }
  }

  @override
  Future<void> pause() async {
    _requireActive();
    await _channel.invokeMethod<Object>('pause');
    final Map<Object?, Object?> state = await _snapshot();
    if (state['playing'] == true) {
      throw StateError('Native audio did not pause.');
    }
  }

  @override
  Future<Duration> seek(Duration position) async {
    _requireActive();
    _endSent = false;
    await _channel.invokeMethod<Object>('seek', <String, Object>{
      'positionMs': position.inMilliseconds,
    });
    await _snapshot();
    _position = position;
    return position; // Command accepted; acoustic seek completion is unmeasured.
  }

  /// Native clipping + repeat; never schedules a Dart/Flutter boundary timer.
  Future<void> setLoop(LoopRange range) async {
    _requireActive();
    if (range.end.inMilliseconds <= range.start.inMilliseconds) {
      throw RangeError('A/B markers must be at least one millisecond apart.');
    }
    final Duration? total = _duration;
    if (total == null || range.end > total) {
      throw RangeError('Loop B is beyond the media duration.');
    }
    await _channel.invokeMethod<Object>('setLoop', <String, Object>{
      'startMs': range.start.inMilliseconds,
      'endMs': range.end.inMilliseconds,
    });
    await _waitReady();
    _loopRange = range;
    _loopEnabled = true;
  }

  /// Disables repeat without discarding the A/B markers.
  Future<void> clearLoop() async {
    _requireActive();
    await _channel.invokeMethod<Object>('clearLoop');
    await _waitReady();
    _loopEnabled = false;
  }

  /// Acknowledged by Media3, not an acoustic-output or latency measurement.
  Future<void> setParameters({
    required double semitones,
    required double speed,
  }) async {
    _requireActive();
    if (!semitones.isFinite || semitones < -12 || semitones > 12) {
      throw ArgumentError.value(
        semitones,
        'semitones',
        'must be within -12..12',
      );
    }
    if (!speed.isFinite || speed < 0.5 || speed > 2) {
      throw ArgumentError.value(speed, 'speed', 'must be within 0.5..2.0');
    }
    final Map<Object?, Object?> state =
        await _channel.invokeMapMethod<Object?, Object?>(
          'setParameters',
          <String, Object>{'semitones': semitones, 'speed': speed},
        ) ??
        <Object?, Object?>{};
    final double acceptedSpeed = (state['speed'] as num?)?.toDouble() ?? -1;
    final double acceptedPitch = (state['pitch'] as num?)?.toDouble() ?? -1;
    if ((acceptedSpeed - speed).abs() > 0.001 ||
        (acceptedPitch - math.pow(2, semitones / 12)).abs() > 0.001) {
      throw StateError('Media3 did not accept pitch/speed.');
    }
    _requestedSemitones = semitones;
    _requestedSpeed = speed;
    _platformSpeed = acceptedSpeed;
    _platformPitch = acceptedPitch;
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _pollTimer?.cancel();
    await _channel.invokeMethod<void>('release');
    _released = true;
    await _ends.close();
    await _interruptions.close();
    _onRelease?.call();
  }

  void _requireActive() {
    if (_released) throw StateError('Native audio has been released.');
  }
}
