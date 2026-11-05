import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of the native engine clock.
@immutable
class NativeAudioState {
  const NativeAudioState({
    this.ready = false,
    this.playing = false,
    this.position = 0,
    this.duration = 0,
  });

  factory NativeAudioState.fromMap(Object? raw) {
    if (raw is! Map) return const NativeAudioState();
    double number(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : 0;
    return NativeAudioState(
      ready: raw['ready'] == true,
      playing: raw['playing'] == true,
      position: number(raw['position']),
      duration: number(raw['duration']),
    );
  }

  final bool ready, playing;
  final double position, duration;
}

/// Pitch in semitones, rate as playback speed, effects in the same units and
/// ranges as the in-page Web Audio bridge (`transpono_media.js`).
@immutable
class NativeAudioSettings {
  const NativeAudioSettings({
    this.pitch = 0,
    this.rate = 1,
    this.bass = 0,
    this.mid = 0,
    this.treble = 0,
    this.gain = 0,
    this.chorus = 0,
    this.reverb = 0,
    this.delay = 0,
    this.feedback = 0,
  });

  static const Map<String, (double, double)> limits = {
    'pitch': (-12, 12),
    'bass': (-12, 12),
    'mid': (-12, 12),
    'treble': (-12, 12),
    'gain': (-12, 6),
    'chorus': (0, .5),
    'feedback': (0, .55),
    'delay': (0, .35),
    'reverb': (0, .4),
  };

  final double pitch, rate, bass, mid, treble, gain;
  final double chorus, reverb, delay, feedback;

  /// Effects as the media state reports them (pitch and rate excluded).
  Map<String, double> get effects => Map<String, double>.unmodifiable({
    'bass': bass,
    'mid': mid,
    'treble': treble,
    'gain': gain,
    'chorus': chorus,
    'feedback': feedback,
    'delay': delay,
    'reverb': reverb,
  });

  NativeAudioSettings withValue(String key, double value) {
    final (double, double)? range = key == 'rate' ? (0.25, 2) : limits[key];
    if (range == null || !value.isFinite) return this;
    final double v = value.clamp(range.$1, range.$2).toDouble();
    return NativeAudioSettings(
      pitch: key == 'pitch' ? v : pitch,
      rate: key == 'rate' ? v : rate,
      bass: key == 'bass' ? v : bass,
      mid: key == 'mid' ? v : mid,
      treble: key == 'treble' ? v : treble,
      gain: key == 'gain' ? v : gain,
      chorus: key == 'chorus' ? v : chorus,
      reverb: key == 'reverb' ? v : reverb,
      delay: key == 'delay' ? v : delay,
      feedback: key == 'feedback' ? v : feedback,
    );
  }

  Map<String, double> toMap() => {
    'pitch': pitch,
    'rate': rate,
    'bass': bass,
    'mid': mid,
    'treble': treble,
    'gain': gain,
    'reverb': reverb,
    'delay': delay,
    'feedback': feedback,
  };
}

/// iOS-only bridge to the native YouTube audio engine.
class YouTubeNativeAudio {
  YouTubeNativeAudio({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('transpose/youtube_native_audio');

  final MethodChannel _channel;

  /// Fetches (or reuses the cached) audio track; returns its duration.
  Future<double> load(String videoId) async {
    final Object? raw = await _channel.invokeMethod<Object>('load', {
      'videoId': videoId,
    });
    final Object? duration = raw is Map ? raw['duration'] : null;
    return duration is num ? duration.toDouble() : 0;
  }

  Future<NativeAudioState> play(double position) async => NativeAudioState
      .fromMap(await _channel.invokeMethod<Object>('play', {'position': position}));

  Future<NativeAudioState> pause() async =>
      NativeAudioState.fromMap(await _channel.invokeMethod<Object>('pause'));

  Future<NativeAudioState> seek(double position) async => NativeAudioState
      .fromMap(await _channel.invokeMethod<Object>('seek', {'position': position}));

  Future<NativeAudioState> state() async =>
      NativeAudioState.fromMap(await _channel.invokeMethod<Object>('state'));

  Future<void> configure(NativeAudioSettings settings) =>
      _channel.invokeMethod<void>('configure', settings.toMap());

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
