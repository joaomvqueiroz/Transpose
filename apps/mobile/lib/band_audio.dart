import 'package:flutter/services.dart';

abstract class BandAudio {
  Future<void> prepare(int Function() now);
  Future<void> schedule({
    required int revision,
    required int startUs,
    required int bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  });
  Future<Map<String, dynamic>> status();
  Future<void> stop();
}

/// Fractional tempo path used by the isolated YouTube QA scheduler. The band
/// protocol continues to send integer BPM through [BandAudio.schedule].
abstract class FractionalBeatAudio {
  Future<void> prepare(int Function() now);
  Future<void> scheduleFractional({
    required int revision,
    required int startUs,
    required double bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  });
  Future<void> stop();
}

/// Translates the Dart monotonic epoch into Android CLOCK_MONOTONIC using
/// minimum-round-trip samples. AudioTrack timestamps stay entirely native.
class NativeBandAudio implements BandAudio, FractionalBeatAudio {
  static const _channel = MethodChannel('transpose/band_audio');
  int _nativeOffset = 0;
  @override
  Future<void> prepare(int Function() now) async {
    var best = 1 << 62;
    for (var i = 0; i < 7; i++) {
      final before = now();
      final native = (await _channel.invokeMethod<int>('clock'))!;
      final after = now();
      if (after - before < best) {
        best = after - before;
        _nativeOffset = native - ((before + after) ~/ 2);
      }
    }
    await _channel.invokeMethod<void>('prepare');
  }

  @override
  Future<void> schedule({
    required int revision,
    required int startUs,
    required int bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  }) => _channel.invokeMethod<void>('schedule', {
    'revision': revision,
    'startUs': startUs + _nativeOffset,
    'bpm': bpm,
    'beats': beats,
    'validUntilUs': validUntilUs + _nativeOffset,
    'correctionUs': correctionUs,
  });
  @override
  Future<void> scheduleFractional({
    required int revision,
    required int startUs,
    required double bpm,
    required int beats,
    required int validUntilUs,
    required int correctionUs,
  }) {
    if (!bpm.isFinite || bpm < 40 || bpm > 240) {
      throw ArgumentError.value(bpm, 'bpm', 'Must be finite and 40–240.');
    }
    return _channel.invokeMethod<void>('schedule', {
      'revision': revision,
      'startUs': startUs + _nativeOffset,
      'bpm': bpm,
      'beats': beats,
      'validUntilUs': validUntilUs + _nativeOffset,
      'correctionUs': correctionUs,
    });
  }

  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>('status') ?? {},
  );
  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      /* No native output exists on this platform. */
    }
  }
}
