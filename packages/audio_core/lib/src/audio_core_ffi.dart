import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _VersionNative = Int32 Function();
typedef _VersionDart = int Function();
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _PingNative = Int32 Function(Pointer<Void>, Int32);
typedef _PingDart = int Function(Pointer<Void>, int);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _CommandNative = Int32 Function(Pointer<Void>);
typedef _CommandDart = int Function(Pointer<Void>);
typedef _FramesNative = Int64 Function(Pointer<Void>);
typedef _FramesDart = int Function(Pointer<Void>);
typedef _StartWavNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _StartWavDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _StartLiveNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Double, Double, Int32);
typedef _StartLiveDart = int Function(
    Pointer<Void>, Pointer<Utf8>, double, double, int);
typedef _RenderDspNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Double,
  Double,
  Int32,
);
typedef _RenderDspDart = int Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  double,
  double,
  int,
);

/// FFI bridge for the isolated Android audio spike, not product playback.
final class AudioCoreFfi {
  AudioCoreFfi({DynamicLibrary? library})
      : _library = library ?? DynamicLibrary.open('libaudio_core.so') {
    _version = _library.lookupFunction<_VersionNative, _VersionDart>(
      'ac_abi_version',
    );
    _dspAvailable = _library.lookupFunction<_VersionNative, _VersionDart>(
      'ac_dsp_available',
    );
    _renderDsp = _library.lookupFunction<_RenderDspNative, _RenderDspDart>(
      'ac_render_wav_dsp',
    );
    _create = _library.lookupFunction<_CreateNative, _CreateDart>('ac_create');
    _ping = _library.lookupFunction<_PingNative, _PingDart>('ac_ping');
    _setBufferBursts = _library.lookupFunction<_PingNative, _PingDart>(
      'ac_set_buffer_bursts',
    );
    _destroy = _library.lookupFunction<_DestroyNative, _DestroyDart>(
      'ac_destroy',
    );
    _startTone = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_start_tone',
    );
    _stopTone = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_stop_tone',
    );
    _startWav = _library.lookupFunction<_StartWavNative, _StartWavDart>(
      'ac_start_wav',
    );
    _startLive = _library.lookupFunction<_StartLiveNative, _StartLiveDart>(
      'ac_start_live_dsp',
    );
    _liveFrames = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_live_frames',
    );
    _liveFinished = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_live_finished',
    );
    _liveUnderruns = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_live_queue_underruns',
    );
    _wavFrames = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_wav_frames',
    );
    _wavFinished = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_wav_finished',
    );
    _callbackCalls = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_callback_calls',
    );
    _callbackMaxUs = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_callback_max_us',
    );
    _callbackOverBudget = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_callback_over_budget',
    );
    _toneFrames = _library.lookupFunction<_FramesNative, _FramesDart>(
      'ac_tone_frames',
    );
    _toneSampleRate = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_tone_sample_rate',
    );
    _toneBurstFrames = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_tone_burst_frames',
    );
    _toneBufferFrames = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_tone_buffer_frames',
    );
    _toneXruns = _library.lookupFunction<_CommandNative, _CommandDart>(
      'ac_tone_xruns',
    );
  }

  final DynamicLibrary _library;
  late final _VersionDart _version;
  late final _VersionDart _dspAvailable;
  late final _RenderDspDart _renderDsp;
  late final _CreateDart _create;
  late final _PingDart _ping;
  late final _PingDart _setBufferBursts;
  late final _DestroyDart _destroy;
  late final _CommandDart _startTone;
  late final _CommandDart _stopTone;
  late final _StartWavDart _startWav;
  late final _StartLiveDart _startLive;
  late final _FramesDart _liveFrames;
  late final _CommandDart _liveFinished;
  late final _FramesDart _liveUnderruns;
  late final _FramesDart _wavFrames;
  late final _CommandDart _wavFinished;
  late final _FramesDart _callbackCalls;
  late final _FramesDart _callbackMaxUs;
  late final _FramesDart _callbackOverBudget;
  late final _FramesDart _toneFrames;
  late final _CommandDart _toneSampleRate;
  late final _CommandDart _toneBurstFrames;
  late final _CommandDart _toneBufferFrames;
  late final _CommandDart _toneXruns;

  int get abiVersion => _version();

  bool get dspAvailable => _dspAvailable() == 1;

  /// Internal, synchronous S-003 WAV render; never called by product playback.
  void renderWavDsp({
    required String inputPath,
    required String outputPath,
    required double semitones,
    required double speed,
    required bool finer,
  }) {
    final Pointer<Utf8> input = inputPath.toNativeUtf8(allocator: calloc);
    final Pointer<Utf8> output = outputPath.toNativeUtf8(allocator: calloc);
    try {
      final int result = _renderDsp(
        input,
        output,
        semitones,
        speed,
        finer ? 1 : 0,
      );
      if (result != 0) {
        throw StateError('Native DSP render failed (code $result).');
      }
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  AudioCoreHandle create() {
    final Pointer<Void> pointer = _create();
    if (pointer == nullptr) throw StateError('Native core allocation failed.');
    return AudioCoreHandle._(
      pointer,
      _ping,
      _setBufferBursts,
      _destroy,
      _startTone,
      _stopTone,
      _startWav,
      _startLive,
      _liveFrames,
      _liveFinished,
      _liveUnderruns,
      _wavFrames,
      _wavFinished,
      _callbackCalls,
      _callbackMaxUs,
      _callbackOverBudget,
      _toneFrames,
      _toneSampleRate,
      _toneBurstFrames,
      _toneBufferFrames,
      _toneXruns,
    );
  }
}

/// Explicit ownership of a native diagnostic handle.
final class AudioCoreHandle {
  AudioCoreHandle._(
    this._pointer,
    this._ping,
    this._setBufferBursts,
    this._destroy,
    this._startTone,
    this._stopTone,
    this._startWav,
    this._startLive,
    this._liveFrames,
    this._liveFinished,
    this._liveUnderruns,
    this._wavFrames,
    this._wavFinished,
    this._callbackCalls,
    this._callbackMaxUs,
    this._callbackOverBudget,
    this._toneFrames,
    this._toneSampleRate,
    this._toneBurstFrames,
    this._toneBufferFrames,
    this._toneXruns,
  );

  Pointer<Void> _pointer;
  final _PingDart _ping;
  final _PingDart _setBufferBursts;
  final _DestroyDart _destroy;
  final _CommandDart _startTone;
  final _CommandDart _stopTone;
  final _StartWavDart _startWav;
  final _StartLiveDart _startLive;
  final _FramesDart _liveFrames;
  final _CommandDart _liveFinished;
  final _FramesDart _liveUnderruns;
  final _FramesDart _wavFrames;
  final _CommandDart _wavFinished;
  final _FramesDart _callbackCalls;
  final _FramesDart _callbackMaxUs;
  final _FramesDart _callbackOverBudget;
  final _FramesDart _toneFrames;
  final _CommandDart _toneSampleRate;
  final _CommandDart _toneBurstFrames;
  final _CommandDart _toneBufferFrames;
  final _CommandDart _toneXruns;

  /// Starts a quiet 440 Hz native test tone, never the app's loaded media.
  void startTone() {
    _requireActive();
    if (_startTone(_pointer) != 0) {
      throw StateError('Native tone output could not start.');
    }
  }

  void stopTone() {
    _requireActive();
    if (_stopTone(_pointer) != 0) {
      throw StateError('Native tone output could not stop.');
    }
  }

  /// Starts an isolated PCM16 WAV diagnostic from a local file path.
  /// Returns no PCM to Dart and does no file I/O on the audio callback.
  void startWav(String path) {
    _requireActive();
    if (path.isEmpty) throw ArgumentError.value(path, 'path');
    final Pointer<Utf8> nativePath = path.toNativeUtf8(allocator: calloc);
    try {
      final int result = _startWav(_pointer, nativePath);
      if (result != 0) {
        throw StateError('Native WAV output could not start (code $result).');
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  /// Experimental worker-to-Oboe streaming, only in an opt-in DSP build.
  void startLiveDsp(String path,
      {required double semitones, required double speed, required bool finer}) {
    _requireActive();
    if (path.isEmpty) throw ArgumentError.value(path, 'path');
    final Pointer<Utf8> nativePath = path.toNativeUtf8(allocator: calloc);
    try {
      final int result =
          _startLive(_pointer, nativePath, semitones, speed, finer ? 1 : 0);
      if (result != 0) {
        throw StateError('Native live DSP could not start (code $result).');
      }
    } finally {
      calloc.free(nativePath);
    }
  }

  int get liveFrames {
    _requireActive();
    return _liveFrames(_pointer);
  }

  bool get liveFinished {
    _requireActive();
    return _liveFinished(_pointer) == 1;
  }

  int get liveQueueUnderruns {
    _requireActive();
    return _liveUnderruns(_pointer);
  }

  /// Closes the current diagnostic output, including WAV output.
  void stopOutput() => stopTone();

  int get wavFrames {
    _requireActive();
    return _wavFrames(_pointer);
  }

  bool get wavFinished {
    _requireActive();
    return _wavFinished(_pointer) == 1;
  }

  /// Number of native audio callbacks in the current diagnostic run.
  int get callbackCalls {
    _requireActive();
    return _callbackCalls(_pointer);
  }

  /// Maximum callback work time, excluding time waiting to be scheduled.
  int get callbackMaxMicroseconds {
    _requireActive();
    return _callbackMaxUs(_pointer);
  }

  /// Callbacks whose work time exceeded their own buffer duration.
  int get callbacksOverBudget {
    _requireActive();
    return _callbackOverBudget(_pointer);
  }

  int get toneFrames {
    _requireActive();
    return _toneFrames(_pointer);
  }

  int get toneSampleRate {
    _requireActive();
    return _toneSampleRate(_pointer);
  }

  int get toneBurstFrames {
    _requireActive();
    return _toneBurstFrames(_pointer);
  }

  int get toneBufferFrames {
    _requireActive();
    return _toneBufferFrames(_pointer);
  }

  /// Null means that the platform API did not expose an XRun count.
  int? get toneXruns {
    _requireActive();
    final int value = _toneXruns(_pointer);
    return value < 0 ? null : value;
  }

  void _requireActive() {
    if (_pointer == nullptr) throw StateError('Native handle is disposed.');
  }

  int ping(int value) {
    _requireActive();
    if (value < 0 || value > 2147483646) {
      throw RangeError.range(value, 0, 2147483646, 'value');
    }
    return _ping(_pointer, value);
  }

  /// Chooses the requested diagnostic buffer size before starting output.
  void setBufferBursts(int bursts) {
    _requireActive();
    if (bursts < 2 || bursts > 4) {
      throw RangeError.range(bursts, 2, 4, 'bursts');
    }
    final int result = _setBufferBursts(_pointer, bursts);
    if (result != 0) {
      throw StateError('Cannot configure audio buffer (code $result).');
    }
  }

  void dispose() {
    if (_pointer == nullptr) return;
    _destroy(_pointer);
    _pointer = nullptr;
  }
}
